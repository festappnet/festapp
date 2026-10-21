#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const source = fs.readFileSync(path.join(root,
  'automation/hetzner-supabase/rehearsal/canary-client-auth-rights-write.mjs'), 'utf8');

test('client rehearsal canary keeps credentials private and the write idempotent', () => {
  assert.match(source, /security', \['find-generic-password'/);
  assert.match(source, /get_is_admin_on_occasion/);
  assert.match(source, /settings\.external\?\.google !== false/);
  assert.match(source, /oauth\.status !== 400/);
  assert.match(source, /p_mode: 'join'/);
  assert.match(source, /afterDigest !== scope\.saved_digest/);
  assert.match(source, /target_rows_changed: 0/);
  assert.match(source, /cloud_sources_mutated: false/);
  assert.match(source, /deleted_rows: 0/);
  assert.doesNotMatch(source, /console\.(?:log|error)\([^\n]*(?:password|access_token|refresh_token|anonKey)/);
});
