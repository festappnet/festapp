import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fastfile = fs.readFileSync(
  path.join(root, 'automation/release/fastlane/Fastfile'),
  'utf8',
);

test('Android Play tooling pins Fastlane through Bundler', () => {
  const gemfile = fs.readFileSync(
    path.join(root, 'automation/release/fastlane/Gemfile'),
    'utf8',
  );
  const wrapper = fs.readFileSync(
    path.join(root, 'automation/release/android_release.ps1'),
    'utf8',
  );

  assert.match(gemfile, /gem ['"]fastlane['"], ['"]2\.238\.0['"]/);
  assert.match(wrapper, /bundle exec fastlane android play_check/);
  assert.match(wrapper, /bundle exec fastlane android play_production/);
});

test('Play track inspection always deletes its disposable edit', () => {
  const helper = fastfile.match(
    /def relevant_play_version_codes(?<body>[\s\S]*?)\nend\n\ndef assert_new_play_version!/
  )?.groups?.body;

  assert.ok(helper, 'missing relevant_play_version_codes helper');
  assert.match(helper, /service\.insert_edit\(PLAY_PACKAGE\)/);
  assert.match(helper, /\bbegin\b[\s\S]*\bensure\b/);
  assert.match(
    helper,
    /service\.delete_edit\(PLAY_PACKAGE, edit\.id\) if edit&\.id/,
  );
  assert.doesNotMatch(helper, /google_play_track_version_codes/);
  assert.deepEqual(
    [...helper.matchAll(/service\.get_edit_track\(/g)].length,
    1,
    'one guarded reader must serve every track',
  );
});

test('production upload remains a separately confirmed binary-only lane', () => {
  const lane = fastfile.match(
    /lane :play_production do(?<body>[\s\S]*?)\n  end\nend/
  )?.groups?.body;

  assert.ok(lane, 'missing play_production lane');
  assert.match(lane, /PLAY_TARGET_TRACK/);
  assert.match(lane, /PLAY_CONFIRMATION/);
  assert.match(lane, /release_status: 'completed'/);
  assert.match(lane, /skip_upload_metadata: true/);
  assert.match(lane, /skip_upload_images: true/);
  assert.match(lane, /skip_upload_screenshots: true/);
});
