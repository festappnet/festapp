import test from 'node:test';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {cleanArtifacts, retentionPlan, publicationFromJob} from '../release/artifact_retention.mjs';

const now = Date.parse('2026-10-28T12:00:00Z');
const sha = 'a'.repeat(40);
function fixture() {
  const run = {id: 42, head_branch: 'main', head_sha: sha, status: 'completed', conclusion: 'success',
    path: '.github/workflows/android-candidate.yml'};
  const artifact = (id, name, age) => ({id, name, size_in_bytes: 100, expired: false,
    workflow_run: {id: 42, head_sha: sha}, created_at: new Date(now - age * 86400000).toISOString()});
  const artifacts = [artifact(1, `android-candidate-one-${sha}`, 8),
    artifact(2, `android-candidate-two-${sha}`, 2),
    artifact(3, `android-raw-two-${sha}-42`, 2),
    artifact(4, `android-raw-three-${sha}-42`, 2),
    artifact(5, `android-raw-four-${sha}-42`, 4), artifact(6, 'release-evidence', 90)];
  const deleted = [];
  const api = {publications: async () => [], activeRuns: async () => [], artifacts: async () => artifacts,
    run: async () => run, remove: async id => { deleted.push(id); }};
  return {artifacts, runs: [run], now, api, deleted};
}

test('prunes historical 30-day candidates at seven days and raw duplicates, preserving recent recovery and evidence', () => {
  const f = fixture();
  assert.deepEqual(retentionPlan(f).map(a => a.id), [1, 3, 5]);
  f.runs[0].conclusion = 'failure';
  assert.deepEqual(retentionPlan(f).map(a => a.id), [1, 5]);
});

test('unknown names, mismatched run IDs, branches and workflow provenance never authorize deletion', () => {
  for (const change of [r => r.head_branch = 'prod/one', r => r.status = 'in_progress',
    r => r.path = '.github/workflows/unrelated.yml', r => r.head_sha = 'b'.repeat(40), r => r.id = 99]) {
    const f = fixture(); change(f.runs[0]);
    assert.deepEqual(retentionPlan(f), []);
  }
  const f = fixture(); f.artifacts.forEach(a => a.created_at = 'invalid');
  assert.deepEqual(retentionPlan(f), []);
});

test('dry run is read only; apply removes exactly planned IDs and reports remaining storage', async () => {
  const f = fixture();
  const plan = await cleanArtifacts(f);
  assert.deepEqual(f.deleted, []);
  const applied = await cleanArtifacts({...f, apply: true});
  assert.deepEqual(f.deleted, plan.removed.map(a => a.id));
  assert.equal(applied.bytes, 300);
  assert.equal(applied.retainedBytes, 300);
});

test('active consumers, consumers starting during planning and API errors prevent deletion', async () => {
  const f = fixture();
  const active = [{path: '.github/workflows/android-production.yml'}];
  f.api.activeRuns = async () => active;
  assert.match((await cleanArtifacts({...f, apply: true})).skipped, /active or queued/);
  assert.deepEqual(f.deleted, []);
  let reads = 0;
  f.api.activeRuns = async () => ++reads === 1 ? [] : active;
  await assert.rejects(cleanArtifacts({...f, apply: true}), /started during planning/);
  assert.deepEqual(f.deleted, []);
  f.api.activeRuns = async () => [];
  f.api.run = async () => { throw Error('HTTP 403'); };
  await assert.rejects(cleanArtifacts({...f, apply: true}), /403/);
  assert.deepEqual(f.deleted, []);
});


test('completed exact production publication retires a candidate inside its promotion window', () => {
  const f = fixture();
  f.publications = [{candidateRunId:42, candidateName:`android-candidate-two-${sha}`, productionRunId:80}];
  assert.deepEqual(retentionPlan(f).map(a=>a.id), [1,2,3,5]);
});


const publicationFixture = () => JSON.parse(readFileSync(new URL('./fixtures/android_published_candidate.json', import.meta.url)));
test('replays actual successful candidate download and completed Play readback boundaries', () => {
  const f = publicationFixture();
  assert.deepEqual(publicationFromJob(f.run,f.job,f.log), {
    candidateName:'android-candidate-cavfotofest-e2fb67b22ffad245fb65d0f121085acc74d4b463',
    candidateRunId:43695254882,productionRunId:43696918865,jobId:132759465611,
    packageName:'fstapp.cav',versionCode:1143,
  });
});

test('failed, skipped, foreign, ambiguous and incomplete publication evidence never retires candidates', () => {
  const changes = [f=>f.run.path='.github/workflows/unrelated.yml', f=>f.run.head_branch='prod/cavfotofest',
    f=>f.run.event='pull_request', f=>f.run.status='in_progress', f=>f.run.conclusion='failure',
    f=>f.job.conclusion='failure', f=>f.job.run_id=1,
    f=>f.job.steps.find(s=>s.name==='Read production state back from Google Play').conclusion='skipped',
    f=>f.job.steps.find(s=>s.name==='Verify the downloaded receipt and hash').conclusion='failure',
    f=>f.log=f.log.replace('PLAY_EXPECTED_VERSION_CODE: 1143','PLAY_EXPECTED_VERSION_CODE: 1144'),
    f=>f.log=f.log.replace('PLAY_PACKAGE: fstapp.cav','PLAY_PACKAGE: fstapp.fstapp'),
    f=>f.log=f.log.replace('run-id: 43695254882','run-id: 0'), f=>f.log+=f.log];
  for (const change of changes) {
    const f=publicationFixture();change(f);
    assert.equal(publicationFromJob(f.run,f.job,f.log),null);
  }
  for (const publication of [
    {candidateRunId:99,candidateName:`android-candidate-two-${sha}`},
    {candidateRunId:42,candidateName:`android-candidate-other-${sha}`},
  ]) assert.deepEqual(retentionPlan({...fixture(),publications:[publication]}).map(a=>a.id),[1,3,5]);
});

test('applied retirement includes the exact publication receipt and still blocks active operations', async () => {
  const f=fixture();
  const publication={candidateRunId:42,candidateName:`android-candidate-two-${sha}`,productionRunId:80};
  f.api.publications=async()=>[publication];
  const result=await cleanArtifacts({...f,apply:true});
  assert.deepEqual(f.deleted,[1,2,3,5]);
  assert.deepEqual(result.removed.find(a=>a.id===2).publication,publication);
  assert.equal(result.retainedBytes,200);
});

test('the forbidden original Android app is excluded before producer lookup and deletion', async () => {
  const f=fixture();
  f.artifacts.push({...f.artifacts[0],id:99,name:`android-candidate-festapp-${sha}`,workflow_run:{id:99,head_sha:sha}});
  f.api.run=async id=>{assert.notEqual(id,99);return f.runs[0];};
  await cleanArtifacts({...f,apply:true});
  assert.ok(!f.deleted.includes(99));
});
