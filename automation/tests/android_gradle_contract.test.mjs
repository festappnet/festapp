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

test('vendored MapLibre explicitly applies Kotlin when built-in Kotlin is disabled', () => {
  assert.match(
    maplibreBuild,
    /id\("org\.jetbrains\.kotlin\.android"\)/,
    'The application opts out of AGP built-in Kotlin, so the Kotlin module must apply the app-owned plugin',
  );
});

test('Android CI tracks and pins the Flutter 3.50 Gradle 9.5.0 wrapper', () => {
  const wrapperProperties = fs.readFileSync(
    path.join(root, 'android/gradle/wrapper/gradle-wrapper.properties'),
    'utf8',
  );
  const wrapperJar = fs.readFileSync(
    path.join(root, 'android/gradle/wrapper/gradle-wrapper.jar'),
  );
  assert.match(wrapperProperties, /gradle-9\.5\.0-all\.zip/);
  assert.match(
    wrapperProperties,
    /distributionSha256Sum=a3c4ba4aca8f0075688b9c5b18939fd28e8cb4357c227da5c1d9f38343791439/,
  );
  assert.equal(
    crypto.createHash('sha256').update(wrapperJar).digest('hex'),
    '497c8c2a7e5031f6aa847f88104aa80a93532ec32ee17bdb8d1d2f67a194a9c7',
  );
});

test('Android plugin and Kotlin versions match the Flutter 3.50 toolchain', () => {
  const settings = fs.readFileSync(path.join(root, 'android/settings.gradle'), 'utf8');
  assert.match(settings, /com\.android\.application" version "9\.3\.1"/);
  assert.match(settings, /org\.jetbrains\.kotlin\.android" version "2\.4\.20"/);
});
