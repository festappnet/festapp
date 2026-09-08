import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../..');
const fastfile = fs.readFileSync(
  path.join(root, 'automation/release/fastlane/Fastfile'), 'utf8');

test('release tooling pins Fastlane and invokes it through Bundler', () => {
  const gemfile = fs.readFileSync(
    path.join(root, 'automation/release/fastlane/Gemfile'), 'utf8');
  const lockfile = fs.readFileSync(
    path.join(root, 'automation/release/fastlane/Gemfile.lock'), 'utf8');
  const iosUpload = fs.readFileSync(
    path.join(root, 'automation/release/ios_build_and_upload.sh'), 'utf8');
  assert.match(gemfile, /gem ['"]fastlane['"], ['"]2\.238\.0['"]/);
  assert.match(lockfile, /fastlane \(2\.238\.0\)/);
  assert.match(iosUpload, /"\$SCRIPT_DIR\/fastlane_setup\.sh"/);
  const uploadInvocations = iosUpload.split('\n')
    .filter((line) => line.includes('fastlane upload_build'));
  assert.ok(uploadInvocations.length > 0);
  assert.ok(uploadInvocations.every((line) => line.includes('bundle exec fastlane upload_build')));
});

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
