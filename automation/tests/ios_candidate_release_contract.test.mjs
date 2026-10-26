#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const candidate = fs.readFileSync(path.join(root, 'automation/release/ios_build_candidate.sh'), 'utf8');
const keychain = fs.readFileSync(path.join(root, 'automation/release/prepare_signing_keychain.sh'), 'utf8');

test('iOS cutover candidate is build-only and fail-closed', () => {
  assert.match(candidate, /client_cutover_preflight\.mjs --require-canonical-cutover/);
  assert.match(candidate, /git status --porcelain=v1/);
  assert.match(candidate, /flutter build ipa --release/);
  assert.match(candidate, /PRODUCT_BUNDLE_IDENTIFIER/);
  assert.match(candidate, /Signing certificate SHA-256/);
  assert.match(candidate, /App Store Connect mutated: false/);
  assert.doesNotMatch(candidate, /fastlane|upload_build|pilot|deliver|transporter/i);
});

test('signing material may be referenced from one explicit external directory', () => {
  assert.match(keychain, /FESTAPP_IOS_SIGNING_DIR/);
  assert.match(keychain, /must be an absolute path/);
  assert.doesNotMatch(keychain, /openssl\s+(?:genrsa|genpkey|req)/);
});
