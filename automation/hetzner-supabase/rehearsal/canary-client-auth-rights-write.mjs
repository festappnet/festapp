#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { once } from 'node:events';
import { spawn } from 'node:child_process';

const TARGET = 'root@46.224.187.4';
const DATABASE = 'festapp_rehearsal_20260828234500';
const ORIGIN = 'https://rehearsal-api.festapp.net';
const WEB_ORIGIN = 'https://festapp-rehearsal-client.pages.dev';
const ACK = 'exercise-isolated-client-auth-rights-idempotent-write';

function fail(message) { throw new Error(message); }
function sha256(value) { return crypto.createHash('sha256').update(value).digest('hex'); }

async function run(command, args, input = '') {
  const child = spawn(command, args, { stdio: ['pipe', 'pipe', 'pipe'] });
  child.stdin.end(input);
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const [code] = await once(child, 'close');
  if (code !== 0) fail(`${command} failed: ${stderr.slice(0, 800)}`);
  return stdout.trim();
}

async function psql(query) {
  return run('ssh', [
    '-o', 'BatchMode=yes', TARGET,
    'docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
    '-U', 'postgres', '-d', DATABASE, '-At',
  ], query);
}

async function main() {
  if (process.env.FESTAPP_REHEARSAL_ACK !== ACK) fail(`set FESTAPP_REHEARSAL_ACK=${ACK}`);
  const [manifestValue, outputValue] = process.argv.slice(2);
  if (!manifestValue || !outputValue) fail('provide a private store manifest and output path');
  const output = path.resolve(outputValue);
  const repo = path.resolve(import.meta.dirname, '../../..');
  if (output === repo || output.startsWith(`${repo}${path.sep}`)) {
    fail('evidence must remain outside the repository');
  }
  const manifest = JSON.parse(fs.readFileSync(path.resolve(manifestValue), 'utf8'));
  const email = manifest.review?.demoAccount?.authEmail;
  const keychainService = manifest.review?.demoAccount?.passwordKeychainService;
  if (!email || !keychainService) fail('review account contract is incomplete');

  const [password, anonKey] = await Promise.all([
    run('security', ['find-generic-password', '-s', keychainService, '-a', email, '-w']),
    run('ssh', ['-o', 'BatchMode=yes', TARGET,
      "sed -n 's/^ANON_KEY=//p' /opt/festapp-supabase/docker/.env"]),
  ]);
  if (!password || anonKey.split('.').length !== 3) fail('private credential or target anon key is unavailable');

  const login = await fetch(`${ORIGIN}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: anonKey, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const loginBody = await login.json();
  if (!login.ok || !loginBody.access_token || !loginBody.user?.id) {
    fail(`password canary failed with HTTP ${login.status}`);
  }
  const userId = loginBody.user.id;
  if (!/^[0-9a-f-]{36}$/i.test(userId)) fail('password canary returned an invalid user UUID');
  const authHeaders = {
    apikey: anonKey,
    authorization: `Bearer ${loginBody.access_token}`,
    'content-type': 'application/json',
  };
  const userResponse = await fetch(`${ORIGIN}/auth/v1/user`, { headers: authHeaders });
  const user = await userResponse.json();
  if (!userResponse.ok || user.id !== userId) fail('password access token failed /auth/v1/user');

  const scope = JSON.parse(await psql(`
    SELECT jsonb_build_object(
      'occasion',o.id,
      'saved_event',(SELECT min(saved.event) FROM public.event_users_saved saved
        JOIN public.events e ON e.id=saved.event
        WHERE saved."user"='${userId}'::uuid AND e.occasion=o.id),
      'saved_digest',(SELECT encode(extensions.digest(coalesce(jsonb_agg(saved.event ORDER BY saved.event)::text,'[]'),'sha256'),'hex')
        FROM public.event_users_saved saved JOIN public.events e ON e.id=saved.event
        WHERE saved."user"='${userId}'::uuid AND e.occasion=o.id)
    ) FROM public.occasions o WHERE o.link='csmostrava2026';
  `));
  if (!Number.isSafeInteger(scope.occasion)) fail('CSM rehearsal occasion is unavailable');

  const rightsResponse = await fetch(`${ORIGIN}/rest/v1/rpc/get_is_admin_on_occasion`, {
    method: 'POST', headers: authHeaders, body: JSON.stringify({ oc: scope.occasion }),
  });
  const rights = await rightsResponse.json();
  if (!rightsResponse.ok || typeof rights !== 'boolean') fail(`rights canary failed with HTTP ${rightsResponse.status}`);

  let writeCanary = 'not-run-no-existing-idempotent-row';
  if (Number.isSafeInteger(scope.saved_event)) {
    const writeResponse = await fetch(`${ORIGIN}/rest/v1/rpc/set_saved_program`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({ p_occasion: scope.occasion, p_event_ids: [scope.saved_event], p_mode: 'join' }),
    });
    const saved = await writeResponse.json();
    if (!writeResponse.ok || !Array.isArray(saved) || !saved.includes(scope.saved_event)) {
      fail(`idempotent write canary failed with HTTP ${writeResponse.status}`);
    }
    const afterDigest = await psql(`
      SELECT encode(extensions.digest(coalesce(jsonb_agg(saved.event ORDER BY saved.event)::text,'[]'),'sha256'),'hex')
      FROM public.event_users_saved saved JOIN public.events e ON e.id=saved.event
      WHERE saved."user"='${userId}'::uuid AND e.occasion=${scope.occasion};
    `);
    if (afterDigest !== scope.saved_digest) fail('idempotent write canary changed saved-program state');
    writeCanary = 'pass-unchanged';
  }

  const settingsResponse = await fetch(`${ORIGIN}/auth/v1/settings`, {
    headers: { apikey: anonKey },
  });
  const settings = await settingsResponse.json();
  if (!settingsResponse.ok || settings.external?.email !== true || settings.external?.google !== false) {
    fail('Auth provider parity is not the approved email-only contract');
  }
  const oauth = await fetch(`${ORIGIN}/auth/v1/authorize?provider=google&redirect_to=${encodeURIComponent(`${WEB_ORIGIN}/`)}`, {
    headers: { apikey: anonKey }, redirect: 'manual',
  });
  if (oauth.status !== 400) {
    fail(`disabled OAuth provider unexpectedly returned HTTP ${oauth.status}`);
  }

  const evidence = {
    version: 1,
    kind: 'festapp-isolated-client-auth-rights-write-canary',
    created_at: new Date().toISOString(),
    origin: ORIGIN,
    database: DATABASE,
    user_id_sha256: sha256(userId),
    anon_key_sha256: sha256(anonKey),
    password_login_status: login.status,
    user_endpoint_status: userResponse.status,
    auth_provider_settings_status: settingsResponse.status,
    email_provider_enabled: true,
    oauth_provider: 'google',
    oauth_provider_enabled: false,
    disabled_oauth_rejection_status: oauth.status,
    rights_status: rightsResponse.status,
    rights_boolean_returned: true,
    idempotent_write: writeCanary,
    target_rows_changed: 0,
    cloud_sources_mutated: false,
    production_dns_mutated: false,
    deleted_rows: 0,
  };
  fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
  const fd = fs.openSync(output, 'wx', 0o600);
  fs.writeFileSync(fd, `${JSON.stringify(evidence, null, 2)}\n`);
  fs.closeSync(fd);
  console.log(JSON.stringify({ status: 'pass', evidence_sha256: sha256(fs.readFileSync(output)), ...evidence }));
}

main().catch((error) => {
  console.error(`ERROR: ${error.message}`);
  process.exitCode = 1;
});
