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
  assert.doesNotMatch(wrapper, /bundle exec fastlane android play_/);
  assert.doesNotMatch(wrapper, /GOOGLE_PLAY_JSON_KEY|UploadProduction|PlayCheck/);
  assert.match(fastfile, /def assert_github_play_gateway!/);
  assert.match(fastfile, /'RUNNER_ENVIRONMENT' => 'github-hosted'/);
  assert.match(fastfile, /'RUNNER_OS' => 'Linux'/);
});

test('byte-exact backend activation documents are always checked out with LF', () => {
  const attributes = fs.readFileSync(path.join(root, '.gitattributes'), 'utf8');
  assert.match(attributes, /^\/web\/backend-activation\.json text eol=lf$/m);
  assert.match(
    attributes,
    /^\/web_client\/public\/backend-activation\.json text eol=lf$/m,
  );
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

test('production workflow enforces the authorized AAB hash before Fastlane', () => {
  const workflow = fs.readFileSync(
    path.join(root, '.github/workflows/android-production.yml'),
    'utf8',
  );
  assert.match(workflow, /artifactSha256/);
  assert.match(workflow, /sha256sum --check/);
  assert.match(workflow, /verify_android_aab\.mjs/);
  assert.match(workflow, /bundle exec fastlane android play_production/);
});

test('AAB validation permits only the known self-signed jarsigner warning class', () => {
  const verifier = fs.readFileSync(
    path.join(root, 'automation/release/verify_android_aab.mjs'),
    'utf8',
  );
  assert.match(verifier, /\[0, 4\]\.includes\(verification\.status\)/);
  assert.match(verifier, /jar verified\\\./);
  assert.match(verifier, /actualFingerprint !== expectedFingerprint/);
});

test('generic Google Play operations stay behind protected GitHub environments', () => {
  const workflow = fs.readFileSync(
    path.join(root, '.github/workflows/google-play-gateway.yml'),
    'utf8',
  );
  const gateway = fs.readFileSync(
    path.join(root, 'automation/release/google_play_gateway.rb'),
    'utf8',
  );

  assert.match(workflow, /environment: android-production-/);
  assert.match(workflow, /PLAY_OPERATION_REQUEST_JSON/);
  assert.match(workflow, /requestSha256/);
  assert.match(workflow, /--symmetric --cipher-algo AES256/);
  assert.match(gateway, /PLAY_ALLOWED_REPOSITORY/);
  assert.match(gateway, /'RUNNER_ENVIRONMENT' => 'github-hosted'/);
  assert.match(gateway, /when 'listing\.update'/);
  assert.match(gateway, /when 'review\.reply'/);
  assert.match(gateway, /when 'grant\.update'/);
  assert.match(gateway, /service\.delete_edit\(package_name, edit\.id\) unless committed/);
  assert.match(gateway, /summary\[:production\]/);
  assert.doesNotMatch(gateway, /summary\[:reviews\]/);
});
