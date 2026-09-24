import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../..');
const maplibreBuild = fs.readFileSync(
  path.join(root, 'packages/maplibre_android/android/build.gradle.kts'),
  'utf8',
);

test('vendored MapLibre pins its external ktlint Gradle plugin', () => {
  assert.match(
    maplibreBuild,
    /id\("org\.jlleitschuh\.gradle\.ktlint"\)\s+version\s+"\d+\.\d+\.\d+"/,
    'Flutter evaluates the vendored module under the app build, so the external plugin must declare a resolvable version',
  );
});

test('Android CI tracks and pins the Windows-authoritative Gradle 8.14 wrapper', () => {
  const wrapperProperties = fs.readFileSync(
    path.join(root, 'android/gradle/wrapper/gradle-wrapper.properties'),
    'utf8',
  );
  const wrapperJar = fs.readFileSync(
    path.join(root, 'android/gradle/wrapper/gradle-wrapper.jar'),
  );
  assert.match(wrapperProperties, /gradle-8\.14-all\.zip/);
  assert.match(
    wrapperProperties,
    /distributionSha256Sum=efe9a3d147d948d7528a9887fa35abcf24ca1a43ad06439996490f77569b02d1/,
  );
  assert.equal(
    crypto.createHash('sha256').update(wrapperJar).digest('hex'),
    '7d3a4ac4de1c32b59bc6a4eb8ecb8e612ccd0cf1ae1e99f66902da64df296172',
  );
});

test('Android plugin and Kotlin versions match the Windows release toolchain', () => {
  const settings = fs.readFileSync(path.join(root, 'android/settings.gradle'), 'utf8');
  assert.match(settings, /com\.android\.application" version "8\.11\.1"/);
  assert.match(settings, /org\.jetbrains\.kotlin\.android" version "2\.2\.20"/);
});
