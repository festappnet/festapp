#!/usr/bin/env node

import { pathToFileURL } from 'node:url';
import {
  collectClientSyncHealth,
  loadHealthTarget,
} from './client_sync_health.mjs';
import { managementQuery } from '../lib/supabase_management.mjs';

function sqlLiteral(value) { return `'${String(value).replaceAll("'", "''")}'`; }

export function buildRecoveryAggregateSql({ organization, occasionLink }) {
  return `
WITH target AS (
  SELECT id, organization, link FROM public.occasions
  WHERE organization=${Number(organization)} AND link=${sqlLiteral(occasionLink)}
), schemas AS (
  SELECT jsonb_build_object(
    'clientCommits',to_regclass('public.client_commits') IS NOT NULL,
    'mutationReceipts',to_regclass('public.client_mutation_receipts') IS NOT NULL,
    'storageObjects',to_regclass('storage.objects') IS NOT NULL
  ) value
)
SELECT jsonb_build_object(
  'occasion',(SELECT jsonb_build_object('id',id,'organization',organization,'link',link) FROM target),
  'schemas',(SELECT value FROM schemas)
) result;`;
}

export function buildRecoveryAuditSql(occasionId) {
  if (!Number.isSafeInteger(occasionId)) throw new Error('validated occasion id is required');
  return `SELECT jsonb_build_object(
    'available',true,
    'count',count(*),
    'firstAt',min(occurred_at),
    'lastAt',max(occurred_at)
  ) result FROM public.client_commits WHERE occasion=${occasionId};`;
}

export async function collectRecoveryAggregates(
  target,
  { query = managementQuery } = {},
) {
  const identity = (await query({
    ...target,
    query: buildRecoveryAggregateSql(target),
  }))[0]?.result;
  if (!identity?.occasion || identity.schemas?.clientCommits !== true) {
    return {
      ...identity,
      audit: { available: false, count: null, firstAt: null, lastAt: null },
    };
  }
  const audit = (await query({
    ...target,
    query: buildRecoveryAuditSql(identity.occasion.id),
  }))[0]?.result;
  return { ...identity, audit };
}

export async function collectBackupInventory(
  target,
  { fetchImpl = fetch } = {},
) {
  const response = await fetchImpl(
    `https://api.supabase.com/v1/projects/${target.projectRef}/database/backups`,
    { headers: { Authorization: `Bearer ${target.accessToken}` } },
  );
  if (!response.ok) throw new Error(`backup inventory failed: HTTP ${response.status}`);
  const body = await response.json();
  const rows = Array.isArray(body) ? body : body.backups ?? [];
  return {
    pitrEnabled: body.pitr_enabled ?? body.pitrEnabled ?? null,
    pitrRetentionDays: body.pitr_retention_days ?? body.pitrRetentionDays ?? null,
    backups: rows.map((row) => ({
      id: row.id ?? null,
      status: row.status ?? null,
      type: row.type ?? null,
      startedAt: row.started_at ?? row.inserted_at ?? null,
      completedAt: row.completed_at ?? null,
    })),
  };
}

function sanitizedSyncHealth(report) {
  return {
    health: report.health,
    registry: report.registry,
    dirty: report.dirty,
    revisionLag: report.revisionLag,
    publication: report.publication,
    projectionDrift: report.projectionDrift,
    receipts: report.receipts ? {
      stuck: report.receipts.stuck,
      completed: report.receipts.completed,
      expired: report.receipts.expired,
      responseBytes: report.receipts.response_bytes,
    } : null,
  };
}

export async function composeRecoveryReadiness({
  target = loadHealthTarget(),
  backupInventory = collectBackupInventory,
  aggregateReader = collectRecoveryAggregates,
  syncHealth = collectClientSyncHealth,
} = {}) {
  const [inventory, aggregates, health] = await Promise.all([
    backupInventory(target),
    aggregateReader(target),
    syncHealth(target),
  ]);
  if (!aggregates?.occasion ||
      aggregates.occasion.organization !== target.organization ||
      aggregates.occasion.link !== target.occasionLink) {
    throw new Error('configured occasion is absent from the configured Supabase project');
  }
  const completedBackups = (inventory.backups ?? []).filter((backup) =>
    backup.status === 'completed' || backup.status === 'COMPLETED');
  if (completedBackups.length === 0) {
    throw new Error('no completed authoritative database backup was reported');
  }
  return {
    target: {
      projectRef: target.projectRef,
      organization: target.organization,
      occasion: aggregates.occasion,
    },
    databaseRecovery: {
      backups: completedBackups,
      pitr: {
        enabled: inventory.pitrEnabled,
        retentionDays: inventory.pitrRetentionDays,
        warning: inventory.pitrEnabled === true
          ? null
          : 'PITR is not confirmed enabled; recovery is limited by completed backups.',
      },
    },
    audit: {
      ...aggregates.audit,
      limitation: 'Redacted audit is incident evidence, not an event-sourced backup.',
    },
    schemas: aggregates.schemas,
    clientSync: sanitizedSyncHealth(health),
    objectRecovery: {
      limitation: 'Database backups do not include Supabase Storage or R2 object payloads.',
    },
    decisionsRequired: [
      'PITR enablement and retention require separate production authorization.',
      'An isolated restore or clone drill requires separate authorization.',
      'Any restore, DML, compaction, or forward repair is outside this read-only command.',
    ],
  };
}

export async function main(args = process.argv.slice(2)) {
  const report = await composeRecoveryReadiness();
  console.log(JSON.stringify(report, null, args.includes('--pretty') ? 2 : undefined));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
