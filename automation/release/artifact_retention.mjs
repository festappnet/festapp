import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {stripVTControlCharacters} from 'node:util';

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

export function readJobLog(jobId, execute = execFileSync) {
  const endpoint = `repos/${repository}/actions/jobs/${jobId}/logs`;
  // Job logs are captured as data, never emitted to a terminal. Newer gh
  // versions require explicit consent even with piped stdout; older versions
  // do not support the flag. Only this exact read-only rejection is retried.
  const options = {maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']};
  let output;
  try {
    output = execute('gh', ['api', endpoint], options);
  } catch (error) {
    if (error.status !== 1 || error.stderr?.toString().trim() !==
        'the response contains terminal escape sequences; pass --allow-escape-sequences to output it anyway') throw error;
    output = execute('gh', ['api', '--allow-escape-sequences', endpoint], options);
  }
  return stripVTControlCharacters(output.toString());
}

// A successful publication includes exact candidate verification and Play readback.
// Read trusted action inputs, never truncated matrix job names or arbitrary output.
export function publicationFromJob(run, job, log) {
  const required = ['Download the exact authorized candidate from GitHub',
    'Verify the downloaded receipt and hash', 'Reverify the exact production input',
    'Publish the authorized AAB to full production', 'Read production state back from Google Play'];
  if (run.path !== '.github/workflows/android-production.yml' || run.head_branch !== 'main' ||
      run.event !== 'workflow_dispatch' || run.status !== 'completed' || run.conclusion !== 'success' ||
      job.run_id !== run.id || job.conclusion !== 'success' || !required.every(name =>
        job.steps?.some(step => step.name === name && step.conclusion === 'success'))) return null;
  const plain = log.replace(/^\d{4}-\d\d-\d\dT[\d:.]+Z /gm, '');
  const downloads = [...plain.matchAll(/^##\[group\]Run actions\/download-artifact@[^\n]+\n([\s\S]*?)^##\[endgroup\]/gm)];
  const readbacks = [...plain.matchAll(/^##\[group\]Run bundle exec ruby "\$RUNNER_TEMP\/play_track_readback\.rb"\n([\s\S]*?)^##\[endgroup\]/gm)];
  if (downloads.length !== 1 || readbacks.length !== 1) return null;
  const name = downloads[0][1].match(/^  name: (android-candidate-[a-z0-9-]+-[a-f0-9]{40})$/m)?.[1];
  const candidateRunId = Number(downloads[0][1].match(/^  run-id: (\d+)$/m)?.[1]);
  const tenant = name && candidateName.exec(name)?.[1];
  const packageName = readbacks[0][1].match(/^  PLAY_PACKAGE: ([A-Za-z][A-Za-z0-9_.]+)$/m)?.[1];
  const versionCode = Number(readbacks[0][1].match(/^  PLAY_EXPECTED_VERSION_CODE: (\d+)$/m)?.[1]);
  if (!tenant || tenant === 'festapp' || packageName === 'fstapp.fstapp' || !packageName ||
      !job.name.startsWith(`publish (${tenant}, prod/${tenant}, ${packageName}, ${versionCode}, `) ||
      !Number.isSafeInteger(candidateRunId) || candidateRunId < 1 ||
      !Number.isSafeInteger(versionCode) || versionCode < 1) return null;
  return {candidateName: name, candidateRunId, productionRunId: run.id, jobId: job.id, packageName, versionCode};
}

export function retentionPlan({artifacts, runs, publications = [], now = Date.now()}) {
  const byRun = new Map(runs.map(run => [run.id, run]));
  const owned = artifact => {
    const match = candidateName.exec(artifact.name) ?? rawName.exec(artifact.name);
    const run = byRun.get(artifact.workflow_run?.id);
    if (!match || match[1] === 'festapp' || artifact.expired || !run || run.status !== 'completed' ||
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
      const published = publications.find(p => p.candidateName === artifact.name && p.candidateRunId === run.id);
      if (published || age >= 7 * day) remove.push({...artifact,
        reason: published ? 'exact candidate published and confirmed on Google Play' : 'candidate promotion window expired',
        ...(published ? {publication: published} : {})});
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
  const ids = [...new Set(artifacts.filter(a => {
    const match = candidateName.exec(a.name) ?? rawName.exec(a.name);
    return match && match[1] !== 'festapp';
  })
    .map(a => a.workflow_run?.id).filter(Boolean))];
  // Resolve exact producer provenance before deleting anything. API failures fail closed.
  const runs = [];
  for (const id of ids) runs.push(await api.run(id));
  const publications = await api.publications(artifacts);
  const remove = retentionPlan({artifacts, runs, publications, now});
  if (apply) {
    if ((await api.activeRuns()).some(run => consumerPaths.has(run.path))) {
      throw Error('Android operation started during planning; no artifacts deleted');
    }
    for (const artifact of remove) await api.remove(artifact.id);
  }
  const removedIds = new Set(remove.map(a => a.id));
  return {apply, removed: remove.map(({id, name, size_in_bytes, reason, publication}) =>
    ({id, name, bytes: size_in_bytes, reason, ...(publication ? {publication} : {})})),
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
    publications: async artifacts => {
      const candidates = artifacts.filter(a => !a.expired && candidateName.test(a.name) &&
        candidateName.exec(a.name)[1] !== 'festapp');
      if (!candidates.length) return [];
      const tenants = new Set(candidates.map(a => candidateName.exec(a.name)[1]));
      const since = candidates.map(a => a.created_at.slice(0, 10)).sort()[0];
      const published = [];
      for (const run of list(`actions/workflows/android-production.yml/runs?status=success&created=>=${since}&per_page=100`, 'workflow_runs')) {
        if (run.head_branch !== 'main' || run.path !== '.github/workflows/android-production.yml') continue;
        for (const job of list(`actions/runs/${run.id}/jobs?per_page=100`, 'jobs')) {
          if (job.conclusion !== 'success' || ![...tenants].some(t => job.name.startsWith(`publish (${t}, prod/${t}, `))) continue;
          const receipt = publicationFromJob(run, job, readJobLog(job.id));
          if (receipt) published.push(receipt);
        }
      }
      return published;
    },
    remove: async id => { gh(['--method', 'DELETE', `repos/${repository}/actions/artifacts/${id}`]); },
  };
  console.log(JSON.stringify(await cleanArtifacts({api, apply}), null, 2));
}
