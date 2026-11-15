import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { androidBuildCacheKeys } from '../release/android_build_cache.mjs';
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
  const revalidation = fs.readFileSync(path.join(root, '.github/workflows/android-candidate-revalidate.yml'), 'utf8');
  const production = fs.readFileSync(path.join(root, '.github/workflows/android-production.yml'), 'utf8');
  assert.match(candidate, /runs-on: ubuntu-latest/);
  assert.match(candidate, /max-parallel: 5/);
  assert.match(candidate, /fail-fast: false/);
  assert.match(candidate, /gradle\/actions\/setup-gradle@v6/);
  assert.match(candidate, /cache-provider: external/);
  const tenantBuild = candidate.slice(candidate.indexOf('\n  build:'));
  assert.match(tenantBuild, /Save shared Gradle compilation state/);
  assert.match(tenantBuild, /Restore shared native compilation artifacts/);
  assert.match(candidate, /Shared build cache disabled/);
  assert.doesNotMatch(candidate, /warm-gradle-cache:\s*\n\s*needs: plan\s*\n\s*if:/);
  assert.match(tenantBuild, /cp automation\/release\/android_build_cache\.mjs/);
  assert.match(tenantBuild, /node "\$RUNNER_TEMP\/android_build_cache\.mjs"/);
  assert.match(candidate, /actions\/upload-artifact@v7/);
  assert.match(candidate, /android-raw-/);
  assert.ok(candidate.indexOf('./gradlew checkReleaseAarMetadata') > 0 &&
    candidate.indexOf('./gradlew checkReleaseAarMetadata') < candidate.indexOf('flutter build appbundle'),
    'dependency SDK requirements must fail before expensive native compilation');
  assert.match(candidate, /retention-days: 3/);
  assert.match(candidate, /retention-days: 7/);
  assert.match(revalidation, /retention-days: 7/);
  assert.match(revalidation, /actions\/download-artifact@v8/);
  assert.match(revalidation, /run-id: \$\{\{ needs\.plan\.outputs\.raw_run_id \}\}/);
  assert.match(revalidation, /android-raw-\$\{\{ matrix\.tenant \}\}/);
  assert.doesNotMatch(revalidation, /flutter build|macos-latest|windows-latest/);
  assert.doesNotMatch(candidate, /macos-latest|windows-latest/);
  assert.match(production, /max-parallel: 3/);
  assert.match(production, /artifactSha256/);
  assert.match(production, /candidateRunId/);
  assert.match(production, /toolingSha/);
  assert.match(production, /actions\/download-artifact@v8/);
  assert.match(candidate, /gpg[\s\S]*--symmetric --cipher-algo AES256/);
  assert.match(production, /gpg[\s\S]*--decrypt/);
  assert.match(production, /play_track_readback\.rb/);
});

function cacheFixture() {
  return {
    '.fvmrc': '{"flutter":"3.50.0"}',
    'android/settings.gradle': 'AGP 9.3.1; Kotlin 2.4.20',
    'android/gradle.properties': 'org.gradle.caching=true',
    'android/gradle/wrapper/gradle-wrapper.properties': 'Gradle 9.5.0',
    'android/gradle/wrapper/gradle-wrapper.jar': Buffer.from('wrapper'),
    'android/app/build.gradle': 'android {\n namespace = "net.example.one"\n applicationId = "net.example.one"\n ndkVersion = "28.2"\n minSdkVersion = 24\n}',
    'pubspec.lock': 'locked dependencies',
    'packages/super_native_extensions/rust/src/lib.rs': 'pub fn native() {}',
  };
}
const cacheRuntime = { os: 'Linux', arch: 'X64', image: 'ubuntu24:one', rustc: 'rustc 1.100' };

test('two tenant identities share native and Gradle build caches', () => {
  const one = cacheFixture();
  const two = { ...one, 'android/app/build.gradle': one['android/app/build.gradle'].replaceAll('net.example.one', 'net.example.two') };
  assert.deepEqual(androidBuildCacheKeys(one, cacheRuntime), androidBuildCacheKeys(two, cacheRuntime));
});

test('native cache changes for compiler, SDK flags, locked dependencies and native sources', () => {
  const files = cacheFixture();
  const original = androidBuildCacheKeys(files, cacheRuntime);
  for (const [name, value] of [
    ['android/app/build.gradle', files['android/app/build.gradle'].replace('minSdkVersion = 24', 'minSdkVersion = 26')],
    ['pubspec.lock', 'different dependencies'],
    ['packages/super_native_extensions/rust/Cargo.lock', 'different native dependencies'],
    ['packages/super_native_extensions/rust/src/lib.rs', 'pub fn changed() {}'],
  ]) assert.notEqual(androidBuildCacheKeys({ ...files, [name]: value }, cacheRuntime).native, original.native, name);
  assert.notEqual(androidBuildCacheKeys(files, { ...cacheRuntime, rustc: 'rustc 1.101' }).native, original.native);
  assert.notEqual(androidBuildCacheKeys(files, { ...cacheRuntime, image: 'ubuntu24:two' }).native, original.native);
});

test('cache inputs exclude signing material and final app artifacts', () => {
  const files = cacheFixture();
  assert.deepEqual(androidBuildCacheKeys(files, cacheRuntime), androidBuildCacheKeys({
    ...files, 'android/key.properties': 'private signing settings', 'build/app/release.aab': 'signed app',
  }, cacheRuntime));
  const candidate = fs.readFileSync(path.join(root, '.github/workflows/android-candidate.yml'), 'utf8');
  for (const step of candidate.split(/(?=      - )/).filter(value => /uses: actions\/cache\/(restore|save)@v5/.test(value))) {
    assert.match(step, /inputs\.reuse_build_cache/);
    assert.match(step, /continue-on-error: true/);
    assert.doesNotMatch(step, /build\/app|key\.properties|keystore|\.aab/);
  }
  const appBuild = fs.readFileSync(path.join(root, 'android/app/build.gradle'), 'utf8');
  assert.match(appBuild, /outputs\.doNotCacheIf\('Final application packaging must run for this tenant'\)/);
});

test('Play readback credential guards use the runner workspace after scripts are copied', () => {
  for (const name of ['play_track_readback.rb', 'play_release_readback.rb']) {
    const script = fs.readFileSync(path.join(root, 'automation/release', name), 'utf8');
    assert.match(script, /ENV\.fetch\('GITHUB_WORKSPACE'\)/);
    assert.doesNotMatch(script, /File\.expand_path\('\.\.\/\.\.', __dir__\)/);
  }
});
