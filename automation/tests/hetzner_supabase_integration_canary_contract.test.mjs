import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const source = fs.readFileSync(new URL('../hetzner-supabase/runtime/run-integration-canaries.mjs', import.meta.url), 'utf8');

test('integration canary covers every operational-readiness integration and cleans disposable state', () => {
  for (const name of [
    'auth-password', 'auth-oauth', 'auth-refresh', 'aws-sns', 'edge-functions',
    'onesignal', 'payment-callbacks', 'realtime', 'smtp', 'storage', 'sync-worker',
  ]) assert.match(source, new RegExp(`'${name}'`));
  assert.match(source, /finally \{/);
  assert.match(source, /external_messages_sent: 0/);
  assert.match(source, /authenticated-no-message-sent/);
  assert.doesNotMatch(source, /console\.log\([^)]*(?:password|serviceKey|anonKey|rest_api_key)/);
});
