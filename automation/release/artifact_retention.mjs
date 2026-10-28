import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';

const repository = 'festappnet/festapp';
const day = 86400000;
const candidateName = /^android-candidate-([a-z0-9-]+)-([a-f0-9]{40})$/;
const rawName = /^android-raw-([a-z0-9-]+)-([a-f0-9]{40})-(\d+)$/;
const producerPaths = new Set([
  '.github/workflows/android-candidate.yml',
  '.github/workflows/android-candidate-revalidate.yml',
]);
const consumerPaths = new Set([...producerPaths,
  '.github/workflows/android-production.yml',
  '.github/workflows/google-play-gateway.yml',
]);

export function retentionPlan({artifacts, runs, now = Date.now()}) {
  const byRun = new Map(runs.map(run => [run.id, run]));
  const owned = artifact => {
    const match = candidateName.exec(artifact.name) ?? rawName.exec(artifact.name);
    const run = byRun.get(artifact.workflow_run?.id);
    if (!match || artifact.expired || !run || run.status !== 'completed' ||
        run.head_branch !== 'main' || !producerPaths.has(run.path) ||
        run.head_sha !== artifact.workflow_run?.head_sha) return null;
    if (rawName.test(artifact.name) &&
        (Number(match[3]) !== run.id || run.path !== '.github/workflows/android-candidate.yml')) return null;
    return run;
  };
  const remove = [];
  for (const artifact of artifacts) {
    const run = owned(artifact);
    if (!run) continue;
    const age = now - Date.parse(artifact.created_at);
    if (!Number.isFinite(age) || age < 0) continue;
    if (candidateName.test(artifact.name)) {
      if (age >= 7 * day) remove.push({...artifact, reason: 'candidate promotion window expired'});
    } else {
      const [, tenant, sha] = rawName.exec(artifact.name);
      const verified = run.conclusion === 'success' && artifacts.some(a =>
        a.name === `android-candidate-${tenant}-${sha}` &&
        a.workflow_run?.id === run.id && owned(a));
      if (verified || age >= 3 * day) remove.push({...artifact,
        reason: verified ? 'verified candidate replaces raw output' : 'raw recovery window expired'});
    }
  }
  return remove;
}

export async function cleanArtifacts({api, apply = false, now = Date.now()}) {
  if ((await api.activeRuns()).some(run => consumerPaths.has(run.path))) {
    return {skipped: 'Android build, revalidation or publication is active or queued'};
  }
  const artifacts = await api.artifacts();
  const ids = [...new Set(artifacts.filter(a => candidateName.test(a.name) || rawName.test(a.name))
    .map(a => a.workflow_run?.id).filter(Boolean))];
  // Resolve exact producer provenance before deleting anything. API failures fail closed.
  const runs = [];
  for (const id of ids) runs.push(await api.run(id));
  const remove = retentionPlan({artifacts, runs, now});
  if (apply) {
    if ((await api.activeRuns()).some(run => consumerPaths.has(run.path))) {
      throw Error('Android operation started during planning; no artifacts deleted');
    }
    for (const artifact of remove) await api.remove(artifact.id);
  }
  const removedIds = new Set(remove.map(a => a.id));
  return {apply, removed: remove.map(({id, name, size_in_bytes, reason}) =>
    ({id, name, bytes: size_in_bytes, reason})),
  bytes: remove.reduce((sum, a) => sum + a.size_in_bytes, 0),
  retainedBytes: artifacts.filter(a => !a.expired && !removedIds.has(a.id))
    .reduce((sum, a) => sum + a.size_in_bytes, 0)};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.some(arg => arg !== '--apply')) throw Error('Use --apply or no arguments for a dry run');
  const apply = args.includes('--apply');
  if (apply && (process.env.GITHUB_ACTIONS !== 'true' || process.env.GITHUB_REPOSITORY !== repository ||
      process.env.GITHUB_WORKFLOW !== 'Actions artifact retention')) {
    throw Error('Deletion requires the serialized Actions artifact retention workflow');
  }
  const gh = args => execFileSync('gh', ['api', ...args], {maxBuffer: 32 * 1024 * 1024});
  const list = (endpoint, key) => JSON.parse(gh([`repos/${repository}/${endpoint}`, '--paginate', '--slurp']))
    .flatMap(page => page[key]);
  const api = {
    artifacts: async () => list('actions/artifacts?per_page=100', 'artifacts'),
    activeRuns: async () => ['in_progress', 'queued', 'waiting', 'pending', 'requested']
      .flatMap(status => list(`actions/runs?status=${status}&per_page=100`, 'workflow_runs')),
    run: async id => JSON.parse(gh([`repos/${repository}/actions/runs/${id}`])),
    remove: async id => { gh(['--method', 'DELETE', `repos/${repository}/actions/artifacts/${id}`]); },
  };
  console.log(JSON.stringify(await cleanArtifacts({api, apply}), null, 2));
}
