import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../..');
const fastfile = fs.readFileSync(
  path.join(root, 'automation/release/fastlane/Fastfile'), 'utf8');

test('internal TestFlight upload is artifact-gated and cannot distribute or submit', () => {
  const start = fastfile.indexOf('lane :upload_testflight_build do');
  const finish = fastfile.indexOf("desc 'Read-only editable-version inventory", start);
  assert.ok(start >= 0 && finish > start, 'missing upload_testflight_build lane');
  const lane = fastfile.slice(start, finish);
  assert.match(lane, /Digest::SHA256\.file\(ipa\)\.hexdigest/);
  assert.match(lane, /TARGET_VERSION.*TARGET_BUILD.*digest.*UPLOAD_TESTFLIGHT_BUILD/);
  assert.match(lane, /skip_waiting_for_build_processing: true/);
  assert.match(lane, /distribute_external: false/);
  assert.match(lane, /notify_external_testers: false/);
  assert.doesNotMatch(lane, /submit_for_review|automatic_release|select_build/);
});

test('release status lane is read-only across editable, review and live states', () => {
  const start = fastfile.indexOf('lane :release_status do');
  const finish = fastfile.indexOf("desc 'Cancel only the in-progress review submission", start);
  assert.ok(start >= 0 && finish > start, 'missing release_status lane');
  const lane = fastfile.slice(start, finish);
  assert.match(lane, /READ_ONLY_TARGET_VERSION/);
  assert.match(lane, /get_app_store_versions/);
  assert.match(lane, /Spaceship::ConnectAPI::Build\.all/);
  assert.doesNotMatch(
    lane,
    /\.update\(|select_build|submit_for_review|deliver\(|upload_to_app_store|upload_to_testflight/,
  );
});
