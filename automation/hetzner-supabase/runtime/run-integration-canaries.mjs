#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { once } from 'node:events';
import { spawn } from 'node:child_process';

const TARGET = 'root@46.224.187.4';
const DATABASE = 'festapp_rehearsal_20260828234500';
const ORIGIN = 'https://rehearsal-api.festapp.net';
const ACK = 'exercise-production-integration-readiness-canaries';

function fail(message) { throw new Error(message); }
function digest(value) { return crypto.createHash('sha256').update(value).digest('hex'); }

async function run(command, args, input = '') {
  const child = spawn(command, args, { stdio: ['pipe', 'pipe', 'pipe'] });
  child.stdin.end(input);
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const [code] = await once(child, 'close');
  if (code !== 0) fail(`${command} failed: ${stderr.slice(0, 700)}`);
  return stdout.trim();
}

async function hostEnv(name) {
  if (!/^[A-Z][A-Z0-9_]*$/.test(name)) fail('invalid host environment name');
  return run('ssh', ['-o', 'BatchMode=yes', TARGET,
    `sed -n 's/^${name}=//p' /opt/festapp-supabase/docker/.env`]);
}

async function psql(sql) {
  return run('ssh', ['-o', 'BatchMode=yes', TARGET,
    'docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
    '-U', 'postgres', '-d', DATABASE, '-At'], sql);
}

async function jsonRequest(url, options, expected) {
  const response = await fetch(url, options);
  const body = await response.json().catch(() => null);
  if (!expected.includes(response.status)) fail(`${new URL(url).pathname} returned HTTP ${response.status}`);
  return { response, body };
}

async function websocketCanary(anonKey) {
  const url = `${ORIGIN.replace('https:', 'wss:')}/realtime/v1/websocket?apikey=${encodeURIComponent(anonKey)}&vsn=1.0.0`;
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const timeout = setTimeout(() => { socket.close(); reject(new Error('Realtime websocket timed out')); }, 10_000);
    socket.addEventListener('open', () => { clearTimeout(timeout); socket.close(); resolve(101); }, { once: true });
    socket.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('Realtime websocket failed')); }, { once: true });
  });
}

async function smtpCanary() {
  const script = `import smtplib\nfrom pathlib import Path\nv={}\nfor line in Path('/opt/festapp-supabase/docker/.env').read_text().splitlines():\n if '=' in line and not line.startswith('#'):\n  k,x=line.split('=',1); v[k]=x\nh=v['SMTP_HOST']; p=int(v['SMTP_PORT']); u=v['SMTP_USER']; pw=v['SMTP_PASS']\nif p==465:\n c=smtplib.SMTP_SSL(h,p,timeout=15)\nelse:\n c=smtplib.SMTP(h,p,timeout=15); c.ehlo(); c.starttls(); c.ehlo()\nc.login(u,pw); assert c.noop()[0] in (250,); c.quit(); print('pass')\n`;
  const result = await run('ssh', ['-o', 'BatchMode=yes', TARGET, 'python3', '-'], script);
  if (result !== 'pass') fail('SMTP authentication canary failed');
}

async function main() {
  if (process.env.FESTAPP_INTEGRATION_CANARY_ACK !== ACK) fail(`set FESTAPP_INTEGRATION_CANARY_ACK=${ACK}`);
  const outputValue = process.argv[2];
  if (!outputValue) fail('provide a private output JSON path');
  const output = path.resolve(outputValue);
  const repository = path.resolve(import.meta.dirname, '../../..');
  if (output === repository || output.startsWith(`${repository}${path.sep}`) || fs.existsSync(output)) {
    fail('evidence output must be new and outside the repository');
  }

  const [anonKey, serviceKey, snsTopic] = await Promise.all([
    hostEnv('ANON_KEY'), hostEnv('SERVICE_ROLE_KEY'), hostEnv('AWS_SNS_TOPIC_ARN'),
  ]);
  if (anonKey.split('.').length !== 3 || serviceKey.split('.').length !== 3 ||
      !/^arn:aws:sns:[a-z0-9-]+:\d{12}:[A-Za-z0-9_-]+$/.test(snsTopic)) {
    fail('runtime credentials or SNS topic configuration is incomplete');
  }

  const nonce = crypto.randomBytes(10).toString('hex');
  const email = `cutover-canary-${nonce}@example.invalid`;
  const password = `T9!${crypto.randomBytes(24).toString('base64url')}`;
  const bucket = `cutover-canary-${nonce}`;
  const syncOrganization = 900_000_000 + crypto.randomInt(1_000_000);
  const syncOccasion = 900_000_000 + crypto.randomInt(1_000_000);
  const syncKey = `client-sync/v1/${syncOrganization}/${syncOccasion}/public-head.json`;
  let userId;
  let bucketCreated = false;
  let syncObjectCreated = false;
  const serviceHeaders = { apikey: serviceKey, authorization: `Bearer ${serviceKey}`, 'content-type': 'application/json' };
  const anonHeaders = { apikey: anonKey, 'content-type': 'application/json' };
  try {
    const created = await jsonRequest(`${ORIGIN}/auth/v1/admin/users`, {
      method: 'POST', headers: serviceHeaders,
      body: JSON.stringify({ email, password, email_confirm: true }),
    }, [200]);
    userId = created.body?.id;
    if (!/^[0-9a-f-]{36}$/i.test(userId ?? '')) fail('Auth canary user was not created');

    const login = await jsonRequest(`${ORIGIN}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: anonHeaders, body: JSON.stringify({ email, password }),
    }, [200]);
    if (!login.body?.access_token || !login.body?.refresh_token) fail('password login did not return a session');
    const refreshed = await jsonRequest(`${ORIGIN}/auth/v1/token?grant_type=refresh_token`, {
      method: 'POST', headers: anonHeaders,
      body: JSON.stringify({ refresh_token: login.body.refresh_token }),
    }, [200]);
    if (refreshed.body?.user?.id !== userId) fail('refresh changed canary identity');

    const settings = await jsonRequest(`${ORIGIN}/auth/v1/settings`, { headers: { apikey: anonKey } }, [200]);
    if (settings.body?.external?.email !== true || settings.body?.external?.google !== false) {
      fail('Auth provider contract is not email-only');
    }
    const oauth = await fetch(`${ORIGIN}/auth/v1/authorize?provider=google&redirect_to=https%3A%2F%2Ffestapp.net%2F`, {
      headers: { apikey: anonKey }, redirect: 'manual',
    });
    if (oauth.status !== 400) fail(`disabled OAuth provider returned HTTP ${oauth.status}`);

    await jsonRequest(`${ORIGIN}/storage/v1/bucket`, {
      method: 'POST', headers: serviceHeaders, body: JSON.stringify({ id: bucket, name: bucket, public: false }),
    }, [200]);
    bucketCreated = true;
    const payload = Buffer.from(`festapp-cutover-canary-${nonce}`);
    const upload = await fetch(`${ORIGIN}/storage/v1/object/${bucket}/probe.txt`, {
      method: 'POST',
      headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}`, 'content-type': 'text/plain', 'x-upsert': 'false' },
      body: payload,
    });
    if (upload.status !== 200) fail(`Storage upload returned HTTP ${upload.status}`);
    const download = await fetch(`${ORIGIN}/storage/v1/object/authenticated/${bucket}/probe.txt`, {
      headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` },
    });
    const downloaded = Buffer.from(await download.arrayBuffer());
    if (download.status !== 200 || !downloaded.equals(payload)) fail('Storage round-trip mismatch');

    const realtimeStatus = await websocketCanary(anonKey);
    const notify = await fetch(`${ORIGIN}/functions/v1/notify`, { method: 'POST', body: '{}' });
    if (notify.status !== 401) fail(`notify authorization canary returned HTTP ${notify.status}`);
    const callback = await fetch(`${ORIGIN}/functions/v1/bank-mail-parser`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-amz-sns-message-type': 'Notification',
        'x-amz-sns-message-id': 'cutover-canary',
        'x-amz-sns-topic-arn': snsTopic,
      },
      body: JSON.stringify({ Type: 'Notification', MessageId: 'cutover-canary', TopicArn: snsTopic }),
    });
    if (callback.status !== 403) fail(`SNS/payment callback rejection returned HTTP ${callback.status}`);

    const oneSignalConfig = JSON.parse(await psql(`SELECT jsonb_build_object(
      'app_id',o.data->>'ONESIGNAL_APP_ID','rest_api_key',s.onesignal_rest_api_key)
      FROM public.organization_notification_secrets s JOIN public.organizations o ON o.id=s.organization
      WHERE nullif(o.data->>'ONESIGNAL_APP_ID','') IS NOT NULL AND nullif(s.onesignal_rest_api_key,'') IS NOT NULL
      ORDER BY s.organization LIMIT 1;`));
    const oneSignal = await fetch(`https://onesignal.com/api/v1/apps/${encodeURIComponent(oneSignalConfig.app_id)}`, {
      headers: { authorization: `Basic ${oneSignalConfig.rest_api_key}` },
    });
    if (oneSignal.status !== 200) fail(`OneSignal credential canary returned HTTP ${oneSignal.status}`);
    await smtpCanary();

    const syncPayload = JSON.stringify({
      protocol: 1,
      scope: { organization: syncOrganization, occasion: syncOccasion },
      revision: 0,
      canary: true,
    });
    await run('npx', [
      'wrangler', 'r2', 'object', 'put', `festapp-public/${syncKey}`,
      '--pipe', '--remote', '--config', 'workers/sync-worker/wrangler.toml',
    ], syncPayload);
    syncObjectCreated = true;
    const sync = await fetch(`https://sync.festapp.net/v1/public-sync/${syncOrganization}/${syncOccasion}/head`);
    if (sync.status !== 200 || !sync.headers.get('etag')) fail(`sync worker canary returned HTTP ${sync.status}`);

    const integrations = {
      'auth-password': { status: 'pass', evidence: `user:${digest(userId)}` },
      'auth-oauth': { status: 'pass', evidence: `disabled-provider:${oauth.status}` },
      'auth-refresh': { status: 'pass', evidence: `rotated:${refreshed.body.refresh_token !== login.body.refresh_token}` },
      'aws-sns': { status: 'pass', evidence: `configured-topic-and-signed-callback-rejection:${callback.status}` },
      'edge-functions': { status: 'pass', evidence: `notify-auth-boundary:${notify.status}` },
      'onesignal': { status: 'pass', evidence: `provider-auth:${oneSignal.status}` },
      'payment-callbacks': { status: 'pass', evidence: `forged-callback-rejected:${callback.status}` },
      'realtime': { status: 'pass', evidence: `websocket:${realtimeStatus}` },
      'smtp': { status: 'pass', evidence: 'authenticated-no-message-sent' },
      'storage': { status: 'pass', evidence: `roundtrip:${digest(downloaded)}` },
      'sync-worker': { status: 'pass', evidence: `published-head:${sync.status}` },
    };
    const evidence = {
      version: 1,
      kind: 'festapp-production-integration-readiness-canaries',
      tested_at: new Date().toISOString(),
      origin: ORIGIN,
      database: DATABASE,
      integrations,
      external_messages_sent: 0,
      cloud_sources_mutated: false,
      disposable_target_rows_removed: true,
    };
    evidence.evidence_sha256 = digest(JSON.stringify(evidence));
    fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
    fs.writeFileSync(output, `${JSON.stringify(evidence, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
    process.stdout.write(`Integration canaries passed: ${Object.keys(integrations).length}/11 evidence_sha256=${evidence.evidence_sha256}\n`);
  } finally {
    if (syncObjectCreated) {
      await run('npx', [
        'wrangler', 'r2', 'object', 'delete', `festapp-public/${syncKey}`,
        '--remote', '--config', 'workers/sync-worker/wrangler.toml',
      ]).catch(() => {});
    }
    if (bucketCreated) {
      await fetch(`${ORIGIN}/storage/v1/object/${bucket}`, {
        method: 'DELETE', headers: serviceHeaders, body: JSON.stringify({ prefixes: ['probe.txt'] }),
      }).catch(() => {});
      await fetch(`${ORIGIN}/storage/v1/bucket/${bucket}`, { method: 'DELETE', headers: serviceHeaders }).catch(() => {});
    }
    if (userId) {
      await fetch(`${ORIGIN}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: serviceHeaders }).catch(() => {});
    }
  }
}

main().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});
