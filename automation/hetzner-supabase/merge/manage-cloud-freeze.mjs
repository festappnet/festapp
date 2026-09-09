#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import {
  SOURCE_REGISTRY,
  accessToken,
  assertPrivateOutput,
  sha256,
  stableJson,
} from './lib.mjs';

const API_ROOT = 'https://api.supabase.com/v1';
const FREEZE_SCHEMAS = Object.freeze(['public', 'eshop']);
const ARCHIVE_ACK = 'archive-cloud-functions-and-freeze-state';
const ENGAGE_ACK = 'engage-full-production-cloud-freeze';
const VERIFY_ACK = 'verify-full-production-cloud-freeze';
const ROLLBACK_ACK = 'rollback-before-canonical-writes-open';

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function argument(name) {
  const prefix = `--${name}=`;
  return process.argv.find((value) => value.startsWith(prefix))?.slice(prefix.length);
}

function privateDirectory(value, { mustExist = false } = {}) {
  const directory = assertPrivateOutput(value);
  if (mustExist) {
    invariant(fs.statSync(directory).isDirectory(), `${directory} is not a directory`);
    invariant((fs.statSync(directory).mode & 0o077) === 0, `${directory} must be mode 0700`);
  } else {
    invariant(!fs.existsSync(directory), `refusing existing evidence directory: ${directory}`);
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  }
  return directory;
}

async function apiRequest({ token, projectRef, route, method = 'GET', body, expected = [200] }) {
  const response = await fetch(`${API_ROOT}/projects/${projectRef}/${route}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!expected.includes(response.status)) {
    const detail = (await response.text()).replaceAll(token, '<redacted>');
    throw new Error(`${method} ${route} failed for ${projectRef}: HTTP ${response.status}: ${detail.slice(0, 500)}`);
  }
  if (response.status === 204) return null;
  const contentType = response.headers.get('content-type') ?? '';
  return contentType.includes('json') ? response.json() : Buffer.from(await response.arrayBuffer());
}

async function query({ token, projectRef, sql }) {
  return apiRequest({
    token,
    projectRef,
    route: 'database/query',
    method: 'POST',
    body: { query: sql },
    expected: [200, 201],
  });
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'], ...options });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => code === 0
      ? resolve(stdout)
      : reject(new Error(`${command} exited ${code}: ${stderr.slice(-1000)}`)));
  });
}

function writePrivate(file, value) {
  const contents = Buffer.isBuffer(value)
    ? value
    : typeof value === 'string' ? value : `${JSON.stringify(value, null, 2)}\n`;
  fs.writeFileSync(file, contents, {
    mode: 0o600,
    flag: 'wx',
  });
}

function manifestPayload(manifest) {
  const { manifest_sha256: omitted, ...payload } = manifest;
  return payload;
}

export function freezeSql() {
  const schemas = FREEZE_SCHEMAS.map((value) => `'${value}'`).join(',');
  return `BEGIN;
CREATE SCHEMA IF NOT EXISTS festapp_cutover;
REVOKE ALL ON SCHEMA festapp_cutover FROM PUBLIC, anon, authenticated, service_role;
CREATE OR REPLACE FUNCTION festapp_cutover.reject_source_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Festapp canonical cutover maintenance freeze is active'
    USING ERRCODE = '55000';
END
$$;
DO $freeze$
DECLARE relation record;
BEGIN
  FOR relation IN
    SELECT n.nspname, c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN (${schemas}) AND c.relkind IN ('r','p')
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS festapp_cutover_freeze ON %I.%I', relation.nspname, relation.relname);
    EXECUTE format('CREATE TRIGGER festapp_cutover_freeze BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %I.%I FOR EACH STATEMENT EXECUTE FUNCTION festapp_cutover.reject_source_mutation()', relation.nspname, relation.relname);
  END LOOP;
END
$freeze$;
DO $cron$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    UPDATE cron.job SET active=false WHERE active;
  END IF;
END
$cron$;
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE pid<>pg_backend_pid()
  AND usename IN ('authenticator','supabase_auth_admin','supabase_storage_admin','supabase_functions_admin')
  AND backend_type='client backend';
COMMIT;`;
}

export function rollbackSql(activeCronJobIds) {
  const ids = activeCronJobIds.length === 0 ? 'NULL' : activeCronJobIds.join(',');
  return `BEGIN;
DO $rollback$
DECLARE relation record;
BEGIN
  FOR relation IN
    SELECT DISTINCT event_object_schema, event_object_table
    FROM information_schema.triggers
    WHERE trigger_name='festapp_cutover_freeze'
  LOOP
    EXECUTE format('DROP TRIGGER festapp_cutover_freeze ON %I.%I', relation.event_object_schema, relation.event_object_table);
  END LOOP;
END
$rollback$;
DO $cron$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    UPDATE cron.job SET active=true WHERE jobid IN (${ids});
  END IF;
END
$cron$;
DROP SCHEMA IF EXISTS festapp_cutover CASCADE;
COMMIT;`;
}

export function validateFreezeState({
  catalogTables, guardTriggers, activeCronJobs, functions, mutatingSessions,
  legacyClientStatus, publishableKeys, migrationKeys,
}) {
  invariant(Number.isSafeInteger(catalogTables) && catalogTables > 0, 'freeze catalog is empty');
  invariant(guardTriggers === catalogTables, 'not every source table has the freeze trigger');
  invariant(activeCronJobs === 0, 'source cron jobs remain active');
  invariant(functions === 0, 'source Edge Functions remain deployed');
  invariant(mutatingSessions === 0, 'active mutating source sessions remain');
  invariant([401, 403].includes(legacyClientStatus), 'legacy API keys remain accepted');
  invariant(publishableKeys === 0, 'source publishable API keys remain active');
  invariant(migrationKeys === 1, 'exactly one private migration key is required');
  return true;
}

async function sourceState({ token, source }) {
  const rows = await query({ token, projectRef: source.project_ref, sql: `SELECT
    (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p')) AS catalog_tables,
    (SELECT count(*)::int FROM pg_trigger WHERE tgname='festapp_cutover_freeze' AND NOT tgisinternal) AS guard_triggers,
    CASE WHEN to_regclass('cron.job') IS NULL THEN 0 ELSE (SELECT count(*)::int FROM cron.job WHERE active) END AS active_cron_jobs,
    (SELECT count(*)::int FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND backend_type='client backend'
      AND state='active' AND query ~* '^[[:space:]]*(insert|update|delete|merge|truncate|copy)') AS mutating_sessions` });
  invariant(rows.length === 1, `missing freeze state for ${source.alias}`);
  return rows[0];
}

async function archive({ token, root }) {
  const observedAt = new Date().toISOString();
  const manifest = { version: 1, kind: 'festapp-cloud-freeze-rollback-archive', observed_at: observedAt, sources: {} };
  for (const source of SOURCE_REGISTRY) {
    const sourceDir = path.join(root, source.alias);
    fs.mkdirSync(sourceDir, { mode: 0o700 });
    const functions = await apiRequest({ token, projectRef: source.project_ref, route: 'functions' });
    const apiKeys = await apiRequest({ token, projectRef: source.project_ref, route: 'api-keys' });
    const state = await sourceState({ token, source });
    const cron = await query({ token, projectRef: source.project_ref, sql: `SELECT jobid::int, active FROM cron.job ORDER BY jobid` })
      .catch(() => []);
    const metadata = [];
    for (const fn of functions) {
      const body = await apiRequest({ token, projectRef: source.project_ref, route: `functions/${encodeURIComponent(fn.slug)}/body` });
      const bodyFile = path.join(sourceDir, `${fn.slug}.eszip`);
      writePrivate(bodyFile, body);
      const downloadRoot = path.join(sourceDir, 'source');
      fs.mkdirSync(downloadRoot, { recursive: true, mode: 0o700 });
      await run('supabase', ['functions', 'download', fn.slug, '--project-ref', source.project_ref, '--use-api'], {
        cwd: downloadRoot,
        env: { ...process.env, SUPABASE_ACCESS_TOKEN: token },
      });
      metadata.push({
        slug: fn.slug,
        version: fn.version,
        verify_jwt: fn.verify_jwt,
        body_sha256: crypto.createHash('sha256').update(body).digest('hex'),
      });
    }
    manifest.sources[source.alias] = {
      project_ref: source.project_ref,
      state,
      active_cron_job_ids: cron.filter((job) => job.active).map((job) => job.jobid),
      api_keys: apiKeys.filter((key) => key.type !== 'legacy').map((key) => ({
        id: key.id,
        type: key.type,
        name: key.name,
        description: key.description ?? null,
        secret_jwt_template: key.secret_jwt_template ?? null,
        hash: key.hash,
      })),
      functions: metadata,
    };
  }
  manifest.manifest_sha256 = sha256(stableJson(manifestPayload(manifest)));
  writePrivate(path.join(root, 'manifest.json'), manifest);
  process.stdout.write(`Cloud freeze rollback archive complete: ${root}\n`);
}

function readManifest(root) {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
  invariant(manifest.version === 1 && manifest.kind === 'festapp-cloud-freeze-rollback-archive', 'invalid freeze archive');
  invariant(manifest.manifest_sha256 === sha256(stableJson(manifestPayload(manifest))),
    'freeze archive manifest digest mismatch');
  for (const source of SOURCE_REGISTRY) {
    const saved = manifest.sources?.[source.alias];
    invariant(saved?.project_ref === source.project_ref && Array.isArray(saved.functions) &&
      Array.isArray(saved.api_keys), `${source.alias} archive is incomplete`);
    for (const fn of saved.functions) {
      const body = fs.readFileSync(path.join(root, source.alias, `${fn.slug}.eszip`));
      invariant(crypto.createHash('sha256').update(body).digest('hex') === fn.body_sha256,
        `${source.alias}/${fn.slug} rollback body digest mismatch`);
    }
  }
  return manifest;
}

async function engage({ token, root }) {
  const manifest = readManifest(root);
  const result = { version: 1, kind: 'festapp-production-cloud-freeze', started_at: new Date().toISOString(), sources: {} };
  for (const source of SOURCE_REGISTRY) {
    const migrationKeyName = `festapp_cutover_export_${Date.now()}`;
    const migrationKey = await apiRequest({
      token,
      projectRef: source.project_ref,
      route: 'api-keys?reveal=false',
      method: 'POST',
      body: {
        type: 'secret',
        name: migrationKeyName,
        description: 'Temporary private cutover Storage export credential',
        secret_jwt_template: { role: 'service_role' },
      },
      expected: [201],
    });
    for (const key of manifest.sources[source.alias].api_keys) {
      await apiRequest({
        token,
        projectRef: source.project_ref,
        route: `api-keys/${encodeURIComponent(key.id)}`,
        method: 'DELETE',
      });
    }
    await query({ token, projectRef: source.project_ref, sql: freezeSql() });
    const removed = [];
    for (const fn of manifest.sources[source.alias].functions) {
      await apiRequest({
        token,
        projectRef: source.project_ref,
        route: `functions/${encodeURIComponent(fn.slug)}`,
        method: 'DELETE',
        expected: [200, 204],
      });
      removed.push(fn.slug);
    }
    await apiRequest({
      token,
      projectRef: source.project_ref,
      route: 'api-keys/legacy?enabled=false',
      method: 'PUT',
    });
    result.sources[source.alias] = {
      project_ref: source.project_ref,
      functions_removed: removed,
      migration_key: { id: migrationKey.id, name: migrationKeyName, hash: migrationKey.hash },
      prior_nonlegacy_keys_revoked: manifest.sources[source.alias].api_keys.map((key) => key.id),
    };
  }
  result.activated_at = new Date().toISOString();
  result.auth_refresh_activated_at = result.activated_at;
  result.blocked_lanes = ['application', 'auth-refresh', 'cron', 'edge-functions', 'manual', 'storage', 'webhooks'];
  result.archive_manifest_sha256 = manifest.manifest_sha256;
  result.result_sha256 = sha256(stableJson(result));
  writePrivate(path.join(root, 'engage-result.json'), result);
  process.stdout.write('Full production cloud freeze engaged; verification is still required\n');
}

async function verify({ token, root }) {
  const manifest = readManifest(root);
  const evidence = { version: 1, kind: 'festapp-production-cloud-freeze-verification', observed_at: new Date().toISOString(), sources: {} };
  for (const source of SOURCE_REGISTRY) {
    const [state, functions, apiKeys] = await Promise.all([
      sourceState({ token, source }),
      apiRequest({ token, projectRef: source.project_ref, route: 'functions' }),
      apiRequest({ token, projectRef: source.project_ref, route: 'api-keys' }),
    ]);
    const legacyAnon = apiKeys.find((key) => key.type === 'legacy' && key.name === 'anon')?.api_key;
    invariant(legacyAnon, `${source.alias} legacy anon key is unavailable for rejection proof`);
    const rejection = await fetch(`https://${source.project_ref}.supabase.co/rest/v1/`, {
      headers: { apikey: legacyAnon },
    });
    const normalized = {
      catalogTables: state.catalog_tables,
      guardTriggers: state.guard_triggers,
      activeCronJobs: state.active_cron_jobs,
      functions: functions.length,
      mutatingSessions: state.mutating_sessions,
      legacyClientStatus: rejection.status,
      publishableKeys: apiKeys.filter((key) => key.type === 'publishable').length,
      migrationKeys: apiKeys.filter((key) => key.type === 'secret' &&
        key.name.startsWith('festapp_cutover_export_')).length,
    };
    validateFreezeState(normalized);
    evidence.sources[source.alias] = { project_ref: source.project_ref, ...normalized, status: 'pass' };
  }
  evidence.archive_manifest_sha256 = manifest.manifest_sha256;
  evidence.blocked_lanes = ['application', 'auth-refresh', 'cron', 'edge-functions', 'manual', 'storage', 'webhooks'];
  evidence.status = 'pass';
  evidence.evidence_sha256 = sha256(stableJson(evidence));
  writePrivate(path.join(root, 'verify-result.json'), evidence);
  process.stdout.write('Full production cloud freeze verified: all seven lanes blocked\n');
}

async function rollback({ token, root }) {
  const manifest = readManifest(root);
  invariant(!fs.existsSync(path.join(root, 'canonical-writes-opened.json')),
    'rollback is forbidden after canonical writes open');
  for (const source of [...SOURCE_REGISTRY].reverse()) {
    const saved = manifest.sources[source.alias];
    await apiRequest({
      token,
      projectRef: source.project_ref,
      route: 'api-keys/legacy?enabled=true',
      method: 'PUT',
    });
    const currentKeys = await apiRequest({ token, projectRef: source.project_ref, route: 'api-keys' });
    for (const key of currentKeys.filter((item) => item.type === 'secret' &&
      item.name.startsWith('festapp_cutover_export_'))) {
      await apiRequest({
        token,
        projectRef: source.project_ref,
        route: `api-keys/${encodeURIComponent(key.id)}`,
        method: 'DELETE',
      });
    }
    for (const key of saved.api_keys) {
      await apiRequest({
        token,
        projectRef: source.project_ref,
        route: 'api-keys?reveal=false',
        method: 'POST',
        body: {
          type: key.type,
          name: key.name,
          ...(key.description ? { description: key.description } : {}),
          ...(key.secret_jwt_template ? { secret_jwt_template: key.secret_jwt_template } : {}),
        },
        expected: [201],
      });
    }
    await query({ token, projectRef: source.project_ref, sql: rollbackSql(saved.active_cron_job_ids) });
    for (const fn of saved.functions) {
      const args = ['functions', 'deploy', fn.slug, '--project-ref', source.project_ref, '--use-api'];
      if (fn.verify_jwt === false) args.push('--no-verify-jwt');
      await run('supabase', args, {
        cwd: path.join(root, source.alias, 'source'),
        env: { ...process.env, SUPABASE_ACCESS_TOKEN: token },
      });
    }
  }
  writePrivate(path.join(root, 'rollback-result.json'), {
    version: 1,
    kind: 'festapp-production-cloud-freeze-rollback',
    completed_at: new Date().toISOString(),
    archive_manifest_sha256: manifest.manifest_sha256,
    status: 'pass',
  });
  process.stdout.write('Production cloud freeze rolled back before canonical writes opened\n');
}

async function main() {
  const command = process.argv[2];
  const evidence = argument('evidence');
  const ack = argument('ack');
  invariant(command && evidence, 'usage: manage-cloud-freeze.mjs archive|engage|verify|rollback --evidence=/private/path --ack=...');
  const expectedAck = { archive: ARCHIVE_ACK, engage: ENGAGE_ACK, verify: VERIFY_ACK, rollback: ROLLBACK_ACK }[command];
  invariant(expectedAck && ack === expectedAck, `set --ack=${expectedAck ?? '<valid-command>'}`);
  const root = privateDirectory(evidence, { mustExist: command !== 'archive' });
  const token = accessToken();
  if (command === 'archive') await archive({ token, root });
  else if (command === 'engage') await engage({ token, root });
  else if (command === 'verify') await verify({ token, root });
  else await rollback({ token, root });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
