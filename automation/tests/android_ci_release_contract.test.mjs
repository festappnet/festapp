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
  const artifactSha256 = 'b'.repeat(64);
  assert.equal(normalizeProductionTargets([{
    tenant: 'one', packageName: 'net.festapp.one', versionCode: 501,
    sourceSha, artifactSha256, action: 'production-completed',
  }])[0].branch, 'prod/one');
  assert.throws(() => normalizeProductionTargets([{
    tenant: 'one', packageName: 'net.festapp.one', versionCode: 501,
    sourceSha, artifactSha256, action: 'draft',
  }]));
});

test('GitHub release workflows use Linux, bounded matrices, shared Gradle cache and R2 artifacts', () => {
  const candidate = fs.readFileSync(path.join(root, '.github/workflows/android-candidate.yml'), 'utf8');
  const production = fs.readFileSync(path.join(root, '.github/workflows/android-production.yml'), 'utf8');
  assert.match(candidate, /runs-on: ubuntu-latest/);
  assert.match(candidate, /max-parallel: 5/);
  assert.match(candidate, /fail-fast: false/);
  assert.match(candidate, /gradle\/actions\/setup-gradle@v6/);
  assert.match(candidate, /cache-provider: basic/);
  assert.match(candidate, /cache-read-only: true/);
  assert.match(candidate, /accounts\/\$CLOUDFLARE_ACCOUNT_ID\/r2\/buckets/);
  assert.match(candidate, /wrangler@4\.129\.1 r2 object put/);
  assert.doesNotMatch(candidate, /macos-latest|windows-latest/);
  assert.match(production, /max-parallel: 3/);
  assert.match(production, /artifactSha256/);
  assert.match(production, /play_track_readback\.rb/);
});
