import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  normalizeCandidateTargets,
  normalizeProductionTargets,
} from '../release/android_ci_plan.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

test('candidate batches accept at most 30 unique production tenants', () => {
  assert.deepEqual(normalizeCandidateTargets(['one', 'two']), [
    { tenant: 'one', branch: 'prod/one' },
    { tenant: 'two', branch: 'prod/two' },
  ]);
  assert.throws(() => normalizeCandidateTargets(Array.from({ length: 31 }, (_, i) => `tenant-${i}`)));
  assert.throws(() => normalizeCandidateTargets(['one', 'one']));
  assert.throws(() => normalizeCandidateTargets(['../main']));
});

test('production targets require immutable artifact identity and explicit completed action', () => {
  const sourceSha = 'a'.repeat(40);
  const toolingSha = 'c'.repeat(40);
  const artifactSha256 = 'b'.repeat(64);
  assert.equal(normalizeProductionTargets([{
    tenant: 'one', packageName: 'net.festapp.one', versionCode: 501,
    sourceSha, toolingSha, artifactSha256, candidateRunId: 123, action: 'production-completed',
  }])[0].branch, 'prod/one');
  assert.throws(() => normalizeProductionTargets([{
    tenant: 'one', packageName: 'net.festapp.one', versionCode: 501,
    sourceSha, toolingSha, artifactSha256, candidateRunId: 123, action: 'draft',
  }]));
});

test('GitHub release workflows use Linux, bounded matrices, shared cache and immutable artifacts', () => {
  const candidate = fs.readFileSync(path.join(root, '.github/workflows/android-candidate.yml'), 'utf8');
  const production = fs.readFileSync(path.join(root, '.github/workflows/android-production.yml'), 'utf8');
  assert.match(candidate, /runs-on: ubuntu-latest/);
  assert.match(candidate, /max-parallel: 5/);
  assert.match(candidate, /fail-fast: false/);
  assert.match(candidate, /gradle\/actions\/setup-gradle@v6/);
  assert.match(candidate, /cache-provider: basic/);
  assert.match(candidate, /cache-read-only: true/);
  assert.match(candidate, /actions\/upload-artifact@v6/);
  assert.match(candidate, /retention-days: 30/);
  assert.doesNotMatch(candidate, /macos-latest|windows-latest/);
  assert.match(production, /max-parallel: 3/);
  assert.match(production, /artifactSha256/);
  assert.match(production, /candidateRunId/);
  assert.match(production, /toolingSha/);
  assert.match(production, /actions\/download-artifact@v7/);
  assert.match(candidate, /gpg[\s\S]*--symmetric --cipher-algo AES256/);
  assert.match(production, /gpg[\s\S]*--decrypt/);
  assert.match(production, /play_track_readback\.rb/);
});
