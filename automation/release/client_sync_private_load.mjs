#!/usr/bin/env node

import path from 'node:path';
import { performance } from 'node:perf_hooks';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import https from 'node:https';
import {
  managementQuery,
  parseKeyValueFile,
} from '../lib/supabase_management.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, '../..');
const config = parseKeyValueFile(path.join(projectRoot, 'automation/project.conf'));
const localEnvironment = parseKeyValueFile(path.join(projectRoot, '.env.local'));

const supabaseUrl = config.get('SUPABASE_URL');
const projectRef = supabaseUrl?.match(
  /^https:\/\/([a-z0-9]+)\.supabase\.co$/,
)?.[1];
const anonKey = config.get('SUPABASE_ANON_KEY');
const organization = Number(config.get('ORGANIZATION_ID'));
const occasionId = Number(process.argv[2]);
const clients = Number(process.argv[3] ?? 5000);
const windowMs = Number(process.argv[4] ?? 60000);
const accessToken = process.env.FESTAPP_TEST_ACCESS_TOKEN;
const managementToken =
  process.env.SUPABASE_ACCESS_TOKEN ||
  localEnvironment.get('SUPABASE_ACCESS_TOKEN');
const timeoutMs = 10000;
const maxSockets = Math.min(clients, 256);

if (
  !supabaseUrl ||
  !projectRef ||
  !anonKey ||
  !Number.isSafeInteger(organization) ||
  !Number.isSafeInteger(occasionId) ||
  occasionId <= 0 ||
  !Number.isSafeInteger(clients) ||
  clients <= 0 ||
  !Number.isFinite(windowMs) ||
  windowMs <= 0 ||
  !accessToken ||
  !managementToken
) {
  throw new Error(
    'usage: FESTAPP_TEST_ACCESS_TOKEN=<jwt> client_sync_private_load.mjs <occasion_id> [clients] [window_ms]',
  );
}

function decodeJwtSubject(token) {
  try {
    const payload = JSON.parse(
      Buffer.from(token.split('.')[1], 'base64url').toString('utf8'),
    );
    if (typeof payload.sub !== 'string' || !/^[0-9a-f-]{36}$/i.test(payload.sub)) {
      throw new Error('missing subject');
    }
    return payload.sub;
  } catch {
    throw new Error('FESTAPP_TEST_ACCESS_TOKEN is not a valid user JWT');
  }
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function percentile(values, fraction) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(
    sorted.length - 1,
    Math.ceil(sorted.length * fraction) - 1,
  );
  return Number(sorted[index].toFixed(1));
}

function increment(target, value) {
  target.set(value, (target.get(value) ?? 0) + 1);
}

const userId = decodeJwtSubject(accessToken);
const endpoint = `${supabaseUrl}/rest/v1/rpc/get_private_client_sync_v1`;
const context = { organizationId: organization, occasionId };
const httpsAgent = new https.Agent({
  keepAlive: true,
  maxSockets,
  maxFreeSockets: Math.min(maxSockets, 64),
  scheduling: 'fifo',
});

async function stateFingerprint() {
  const rows = await managementQuery({
    projectRef,
    accessToken: managementToken,
    query: `
      SELECT jsonb_build_object(
        'commits', (SELECT count(*) FROM public.client_commits WHERE actor_id=${sqlLiteral(userId)}::uuid),
        'receipts', (SELECT count(*) FROM public.client_mutation_receipts WHERE actor_id=${sqlLiteral(userId)}::uuid),
        'privateScopes', COALESCE((
          SELECT md5(string_agg(component||':'||source_revision||':'||updated_at, ',' ORDER BY component))
          FROM public.client_sync_private_scopes
          WHERE occasion=${occasionId} AND user_id=${sqlLiteral(userId)}::uuid
        ), '')
      ) AS result;
    `,
  });
  return rows[0]?.result;
}

async function handshake(knownVector) {
  const body = JSON.stringify({
    p_context: context,
    p_known_private_vector: knownVector,
  });
  const started = performance.now();
  return new Promise((resolve, reject) => {
    const request = https.request(endpoint, {
      method: 'POST',
      agent: httpsAgent,
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: timeoutMs,
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => {
        const latency = performance.now() - started;
        let payload = null;
        try {
          payload = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        } catch {
          // The caller reports only the HTTP status, never a private body.
        }
        resolve({
          response: { status: response.statusCode ?? 0 },
          latency,
          payload,
        });
      });
    });
    request.on('timeout', () => request.destroy(new Error('request timeout')));
    request.on('error', reject);
    request.end(body);
  });
}

const beforeState = await stateFingerprint();
const initial = await handshake({});
if (initial.response.status !== 200 || initial.payload?.code !== 200) {
  throw new Error(`initial private handshake failed: HTTP ${initial.response.status}`);
}
const vector = initial.payload.data?.vector;
if (!vector || typeof vector !== 'object' || Array.isArray(vector)) {
  throw new Error('initial private handshake omitted the revision vector');
}

const latencies = [];
const statuses = new Map();
const errors = [];

async function client(index) {
  await new Promise((resolve) =>
    setTimeout(resolve, Math.floor((index * windowMs) / clients)),
  );
  try {
    const result = await handshake(vector);
    latencies.push(result.latency);
    increment(statuses, result.response.status);
    if (
      result.response.status !== 200 ||
      result.payload?.code !== 200 ||
      !Array.isArray(result.payload?.data?.components) ||
      result.payload.data.components.length !== 0
    ) {
      throw new Error(`unexpected unchanged response: HTTP ${result.response.status}`);
    }
  } catch (error) {
    errors.push(error instanceof Error ? error.message : String(error));
  }
}

const started = performance.now();
await Promise.all(Array.from({ length: clients }, (_, index) => client(index)));
const durationMs = performance.now() - started;
const afterState = await stateFingerprint();
const stateUnchanged = JSON.stringify(beforeState) === JSON.stringify(afterState);

const result = {
  occasionId,
  clients,
  max_sockets: maxSockets,
  duration_ms: Number(durationMs.toFixed(1)),
  average_rps: Number((latencies.length / (durationMs / 1000)).toFixed(1)),
  initial: {
    status: initial.response.status,
    latency_ms: Number(initial.latency.toFixed(1)),
    component_count: initial.payload.data?.components?.length ?? 0,
  },
  unchanged: {
    statuses: Object.fromEntries(statuses),
    p50_ms: percentile(latencies, 0.5),
    p95_ms: percentile(latencies, 0.95),
    p99_ms: percentile(latencies, 0.99),
  },
  database_state_unchanged: stateUnchanged,
  errors: errors.length,
  sample_errors: [...new Set(errors)].slice(0, 5),
};

console.log(JSON.stringify(result, null, 2));
httpsAgent.destroy();
if (errors.length || statuses.get(200) !== clients || !stateUnchanged) {
  process.exitCode = 1;
}
