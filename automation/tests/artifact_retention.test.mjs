import test from 'node:test';
import assert from 'node:assert/strict';
import {cleanArtifacts, retentionPlan} from '../release/artifact_retention.mjs';

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
  const api = {activeRuns: async () => [], artifacts: async () => artifacts,
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
