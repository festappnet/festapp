#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { managementQuery, parseKeyValueFile } from '../lib/supabase_management.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, '../..');
export const scheduleName = 'festapp_client_sync_publication_tick_v1';
export const endpointSecretName = 'client_sync_publisher_wake_url_v1';
export const tokenSecretName = 'client_sync_publisher_wake_token_v1';

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

export function loadScheduleTarget(root = projectRoot) {
  const config = parseKeyValueFile(path.join(root, 'automation/project.conf'));
  const localEnvironment = parseKeyValueFile(path.join(root, '.env.local'));
  const supabaseUrl = config.get('SUPABASE_URL');
  const projectRef = supabaseUrl?.match(/^https:\/\/([a-z0-9]+)\.supabase\.co$/)?.[1];
  const organization = Number(config.get('ORGANIZATION_ID'));
  const occasionLink = config.get('FORCE_OCCASION_LINK');
  const wrangler = fs.readFileSync(path.join(root, 'workers/sync-publisher/wrangler.toml'), 'utf8');
  const scopeIds = wrangler.match(/^SYNC_SCOPE_IDS\s*=\s*"([^"]+)"/m)?.[1]
    .split(',').map((value) => Number(value.trim()));
  const accessToken = process.env.SUPABASE_ACCESS_TOKEN || localEnvironment.get('SUPABASE_ACCESS_TOKEN');
  if (!projectRef || !Number.isSafeInteger(organization) || !occasionLink || !accessToken) {
    throw new Error('valid project config and SUPABASE_ACCESS_TOKEN are required');
  }
  if (!scopeIds?.length || scopeIds.some((id) => !Number.isSafeInteger(id) || id <= 0)) {
    throw new Error('SYNC_SCOPE_IDS must contain positive integers');
  }
  return { projectRef, organization, occasionLink, scopeIds, accessToken };
}

export function buildScheduleCommand(scopeIds) {
  return `
SELECT net.http_post(
  url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name=${sqlLiteral(endpointSecretName)}),
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name=${sqlLiteral(tokenSecretName)}),
    'Content-Type', 'application/json'
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 4000
)
WHERE EXISTS (
  SELECT 1
  FROM public.client_projection_dirty_keys d
  WHERE d.scope_type='occasion'
    AND d.scope_id=ANY(ARRAY[${scopeIds.join(',')}]::bigint[])
    AND d.claimed_at IS NULL
);`.trim();
}

export function buildApplySql(scopeIds) {
  const command = buildScheduleCommand(scopeIds);
  return `
DO $schedule$
DECLARE v_job record;
BEGIN
  FOR v_job IN SELECT jobid FROM cron.job WHERE jobname=${sqlLiteral(scheduleName)} LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
  PERFORM cron.schedule(${sqlLiteral(scheduleName)}, '5 seconds', $command$${command}$command$);
END
$schedule$;`;
}

export function buildDisableSql() {
  return `SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname=${sqlLiteral(scheduleName)};`;
}

export function buildStatusSql({ organization, occasionLink, scopeIds }) {
  return `SELECT jsonb_build_object(
    'occasion', (SELECT jsonb_build_object('id',o.id,'link',o.link) FROM public.occasions o WHERE o.organization=${organization} AND o.link=${sqlLiteral(occasionLink)}),
    'scopeMatch', (SELECT COALESCE(array_agg(o.id ORDER BY o.id),'{}')=ARRAY[${scopeIds.join(',')}]::bigint[] FROM public.occasions o WHERE o.organization=${organization} AND o.link=${sqlLiteral(occasionLink)}),
    'extensions', jsonb_build_object(
      'cron', EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron'),
      'net', EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_net'),
      'vault', EXISTS(SELECT 1 FROM pg_extension WHERE extname='supabase_vault')
    ),
    'job', (SELECT jsonb_build_object('jobid',jobid,'schedule',schedule,'active',active) FROM cron.job WHERE jobname=${sqlLiteral(scheduleName)}),
    'endpointSecretPresent', EXISTS(SELECT 1 FROM vault.decrypted_secrets WHERE name=${sqlLiteral(endpointSecretName)}),
    'tokenSecretPresent', EXISTS(SELECT 1 FROM vault.decrypted_secrets WHERE name=${sqlLiteral(tokenSecretName)})
  ) AS result;`;
}

function buildSecretSql(endpoint, token) {
  return `DO $vault$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM vault.secrets WHERE name=${sqlLiteral(endpointSecretName)};
  IF v_id IS NULL THEN PERFORM vault.create_secret(${sqlLiteral(endpoint)},${sqlLiteral(endpointSecretName)});
  ELSE PERFORM vault.update_secret(v_id,${sqlLiteral(endpoint)},${sqlLiteral(endpointSecretName)}); END IF;
  SELECT id INTO v_id FROM vault.secrets WHERE name=${sqlLiteral(tokenSecretName)};
  IF v_id IS NULL THEN PERFORM vault.create_secret(${sqlLiteral(token)},${sqlLiteral(tokenSecretName)});
  ELSE PERFORM vault.update_secret(v_id,${sqlLiteral(token)},${sqlLiteral(tokenSecretName)}); END IF;
END
$vault$;`;
}

export async function main(args = process.argv.slice(2)) {
  const target = loadScheduleTarget();
  const modes = ['--apply', '--disable', '--status'].filter((mode) => args.includes(mode));
  if (modes.length > 1) throw new Error('choose only one mode');
  const mode = modes[0] ?? '--dry-run';
  const queryTarget = { organization: target.organization, occasionLink: target.occasionLink, scopeIds: target.scopeIds };
  const before = (await managementQuery({ ...target, query: buildStatusSql(queryTarget) }))[0]?.result;
  if (!before?.occasion || before.scopeMatch !== true) throw new Error('configured occasion and SYNC_SCOPE_IDS do not match');

  if (mode === '--apply' || mode === '--disable') {
    if (!args.includes(`--confirm=${target.occasionLink}`)) throw new Error(`missing --confirm=${target.occasionLink}`);
  }
  if (mode === '--apply') {
    const endpoint = process.env.CLIENT_SYNC_PUBLISHER_WAKE_URL;
    const token = process.env.CLIENT_SYNC_PUBLISHER_WAKE_TOKEN;
    if (!endpoint || !token) throw new Error('publisher wake URL and token environment variables are required');
    await managementQuery({ ...target, query: buildSecretSql(endpoint, token) });
    await managementQuery({ ...target, query: buildApplySql(target.scopeIds) });
  } else if (mode === '--disable') {
    await managementQuery({ ...target, query: buildDisableSql() });
  }
  const result = mode === '--dry-run'
    ? before
    : (await managementQuery({ ...target, query: buildStatusSql(queryTarget) }))[0]?.result;
  console.log(JSON.stringify({ mode, projectRef: target.projectRef, scheduleName, result }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
