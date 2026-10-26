#!/usr/bin/env node

import path from 'node:path';
import process from 'node:process';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  loadCanonicalSupabaseTarget,
  managementQuery,
  parseKeyValueFile,
} from '../lib/supabase_management.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, '../..');

function sqlLiteral(value) { return `'${String(value).replaceAll("'", "''")}'`; }

export function loadHealthTarget(root = projectRoot) {
  const config = parseKeyValueFile(path.join(root, 'automation/project.conf'));
  const canonical = loadCanonicalSupabaseTarget(root);
  const headOrigin = config.get('SYNC_HEAD_ORIGIN');
  const wrangler=fs.readFileSync(path.join(root,'workers/sync-publisher/wrangler.toml'),'utf8');
  const artifactRetentionDays=Number(wrangler.match(/^SYNC_ARTIFACT_RETENTION_DAYS\s*=\s*"(\d+)"/m)?.[1]);
  if (!headOrigin || !Number.isSafeInteger(artifactRetentionDays) || artifactRetentionDays<7) {
    throw new Error('valid project config and SUPABASE_ACCESS_TOKEN are required');
  }
  return { ...canonical, headOrigin, artifactRetentionDays };
}

export function buildHealthSql({ organization, occasionLink, artifactRetentionDays }) {
  return `
WITH target AS (
  SELECT o.id,o.organization,o.link,o.data FROM public.occasions o
  WHERE o.organization=${organization} AND o.link=${sqlLiteral(occasionLink)}
), latest_registry AS (
  SELECT max(registry_version) version FROM public.client_sync_component_sources
), publication_lag AS (
  SELECT cc.component,
    extract(epoch FROM (p.published_at-c.occurred_at))*1000 lag_ms
  FROM public.client_commit_components cc
  JOIN public.client_commits c ON c.commit_id=cc.commit_id
  JOIN LATERAL (
    SELECT p.published_at FROM public.client_sync_publications p
    WHERE p.component=cc.component AND p.scope_type=cc.scope_type
      AND p.scope_id=cc.scope_id AND p.published_revision=cc.resulting_revision
    ORDER BY p.published_at LIMIT 1
  ) p ON true
  WHERE c.occurred_at>now()-interval '24 hours'
    AND cc.scope_type='occasion' AND cc.scope_id=(SELECT id FROM target)
), drift AS (
  SELECT count(*) count FROM public.events e
  LEFT JOIN public.event_public_state s ON s.occasion=e.occasion AND s.event=e.id
  WHERE e.occasion=(SELECT id FROM target) AND NOT e.is_hidden
    AND (s.event IS NULL
      OR s.participant_count IS DISTINCT FROM (SELECT count(DISTINCT eu."user") FROM public.event_users eu WHERE eu.event=e.id)
      OR s.saved_count IS DISTINCT FROM (SELECT count(DISTINCT saved."user") FROM public.event_users_saved saved WHERE saved.event=e.id)
      OR s.remaining_capacity IS DISTINCT FROM CASE WHEN e.max_participants IS NULL THEN NULL
        ELSE GREATEST(e.max_participants-(SELECT count(DISTINCT eu."user") FROM public.event_users eu WHERE eu.event=e.id),0) END)
), receipt_health AS (
  SELECT count(*) FILTER (WHERE status='processing' AND created_at<now()-interval '2 minutes') stuck,
    count(*) FILTER (WHERE status='completed') completed,
    count(*) FILTER (WHERE status='expired') expired,
    COALESCE(sum(octet_length(response::text)) FILTER (WHERE response IS NOT NULL),0) response_bytes
  FROM public.client_mutation_receipts WHERE occasion=(SELECT id FROM target)
)
SELECT jsonb_build_object(
  'occasion',(SELECT jsonb_build_object('id',id,'link',link,
    'enabled',COALESCE((data->>'client_sync_v1')::boolean,false)) FROM target),
  'registry',jsonb_build_object(
    'rows',(SELECT count(*) FROM public.client_sync_component_sources r WHERE r.registry_version=(SELECT version FROM latest_registry)),
    'notReady',(SELECT count(*) FROM public.client_sync_component_sources r WHERE r.registry_version=(SELECT version FROM latest_registry) AND NOT r.cutover_ready)),
  'dirty',jsonb_build_object(
    'count',(SELECT count(*) FROM public.client_projection_dirty_keys d WHERE d.scope_id=(SELECT id FROM target)),
    'unclaimedOldestSeconds',(SELECT COALESCE(max(extract(epoch FROM now()-d.dirty_since)),0) FROM public.client_projection_dirty_keys d WHERE d.scope_id=(SELECT id FROM target) AND d.claimed_at IS NULL),
    'claimedOldestSeconds',(SELECT COALESCE(max(extract(epoch FROM now()-d.claimed_at)),0) FROM public.client_projection_dirty_keys d WHERE d.scope_id=(SELECT id FROM target) AND d.claimed_at IS NOT NULL)),
  'revisionLag',(SELECT count(*) FROM public.client_sync_scopes s LEFT JOIN LATERAL (
    SELECT max(p.published_revision) revision FROM public.client_sync_publications p
    WHERE p.component=s.component AND p.scope_type=s.scope_type AND p.scope_id=s.scope_id
  ) p ON true WHERE s.scope_id=(SELECT id FROM target) AND s.source_revision>COALESCE(p.revision,-1)),
  'publication',jsonb_build_object(
    'liveP95Ms',(SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY lag_ms) FROM publication_lag WHERE component='live_public'),
    'structuralP95Ms',(SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY lag_ms) FROM publication_lag WHERE component<>'live_public'),
    'p99Ms',(SELECT percentile_cont(0.99) WITHIN GROUP (ORDER BY lag_ms) FROM publication_lag),
    'maxMs',(SELECT max(lag_ms) FROM publication_lag)),
  'projectionDrift',(SELECT count FROM drift),
  'receipts',(SELECT to_jsonb(receipt_health) FROM receipt_health),
  'retention',jsonb_build_object(
    'candidateCount',(SELECT count(*) FROM public.client_sync_publications p WHERE p.scope_id=(SELECT id FROM target) AND p.published_at<now()-make_interval(days=>${artifactRetentionDays})),
    'currentProtectedCount',(SELECT count(*) FROM public.client_sync_public_heads h WHERE h.scope_id=(SELECT id FROM target))),
  'scheduler',(SELECT jsonb_build_object('active',active,'schedule',schedule) FROM cron.job WHERE jobname='festapp_client_sync_publication_tick_v1'),
  'head',(SELECT h.head_json FROM public.client_sync_public_heads h WHERE h.scope_id=(SELECT id FROM target))
) result;`;
}

export function evaluateHealth(report) {
  const failures = [];
  if (!report.occasion) failures.push('target occasion missing');
  if (Number(report.registry?.notReady ?? 1)>0) failures.push('registry not ready');
  if (Number(report.dirty?.unclaimedOldestSeconds ?? 0)>10) failures.push('unclaimed dirty work older than two ticks');
  if (Number(report.dirty?.claimedOldestSeconds ?? 0)>120) failures.push('claim older than lease');
  if (Number(report.revisionLag ?? 0)>0) failures.push('source/publication revision lag');
  if (Number(report.publication?.liveP95Ms ?? 0)>25000) failures.push('live publication p95 exceeds 25s');
  if (Number(report.publication?.structuralP95Ms ?? 0)>45000) failures.push('structural publication p95 exceeds 45s');
  if (Number(report.projectionDrift ?? 0)>0) failures.push('event projection drift');
  if (Number(report.receipts?.stuck ?? 0)>0) failures.push('stuck processing receipts');
  if (report.head?.publicationPending === true) failures.push('public head has publicationPending');
  if (report.endpoint && report.endpoint.status !== 200) failures.push('public head endpoint unavailable');
  if (report.endpoint?.hashesValid === false) failures.push('current artifact hash mismatch');
  return { ok: failures.length===0, failures };
}

async function endpointHealth(target, occasionId) {
  const url = `${target.headOrigin}/v1/public-sync/${target.organization}/${occasionId}/head`;
  const initial = await fetch(url);
  const etag = initial.headers.get('etag');
  const head = initial.status===200 ? await initial.json() : null;
  const conditional = etag ? await fetch(url,{ headers:{ 'If-None-Match':etag } }) : null;
  let hashesValid = true;
  let networkBytes = 0;
  for (const descriptor of [head?.catalog,head?.live].filter(Boolean)) {
    const response = await fetch(descriptor.url);
    const bytes = Buffer.from(await response.arrayBuffer());
    networkBytes += bytes.length;
    hashesValid &&= response.ok && createHash('sha256').update(bytes).digest('hex')===descriptor.sha256;
  }
  return {
    status:initial.status,conditionalStatus:conditional?.status ?? null,
    cacheControl:initial.headers.get('cache-control'),cacheStatus:initial.headers.get('cf-cache-status'),
    etag,hashesValid,networkBytes,
  };
}

export async function collectClientSyncHealth(
  target = loadHealthTarget(),
  { query = managementQuery, endpoint = endpointHealth } = {},
) {
  const row=(await query({...target,query:buildHealthSql(target)}))[0]?.result;
  if (!row?.occasion) throw new Error('configured occasion is absent from the configured Supabase project');
  const endpointReport=await endpoint(target,row.occasion.id);
  const report={projectRef:target.projectRef,...row,endpoint:endpointReport,r2:{bucket:'festapp-public',prefix:'client-sync/v1/'}};
  return {...report,health:evaluateHealth(report)};
}

export async function main(args=process.argv.slice(2)) {
  const output=await collectClientSyncHealth();
  console.log(JSON.stringify(output,args.includes('--pretty')?null:undefined,args.includes('--pretty')?2:undefined));
  if (!output.health.ok) process.exitCode=1;
}

if (process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  main().catch((error)=>{console.error(error.message);process.exitCode=1;});
}
