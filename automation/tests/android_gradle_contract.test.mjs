import assert from 'node:assert/strict';
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
