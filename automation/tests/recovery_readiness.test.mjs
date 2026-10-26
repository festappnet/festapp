import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  buildRecoveryAuditSql,
  buildRecoveryAggregateSql,
  collectBackupInventory,
  collectRecoveryAggregates,
  composeRecoveryReadiness,
} from '../release/recovery_readiness.mjs';
import { loadCanonicalSupabaseTarget } from '../lib/supabase_management.mjs';

const target = {
  projectRef: 'lwfpdjxsdmkfyrzqbrlk',
  organization: 9,
  occasionLink: 'csmostrava2026',
  accessToken: 'not-reported',
};
const aggregate = {
  occasion: { id: 643, organization: 9, link: 'csmostrava2026' },
  schemas: { clientCommits: true, mutationReceipts: true, storageObjects: true },
  audit: { count: 5098, firstAt: '2026-08-03T10:13:26Z', lastAt: '2026-08-07T00:00:00Z' },
};
const health = { health: { ok: true, failures: [] }, revisionLag: 0, receipts: { stuck: 0 } };

test('composer exposes only sanitized read-only recovery evidence', async () => {
  const seen = [];
  const report = await composeRecoveryReadiness({
    target,
    backupInventory: async (value) => {
      seen.push(['backups', value.projectRef]);
      return { pitrEnabled: false, backups: [{ id: 'daily-1', status: 'completed' }] };
    },
    aggregateReader: async (value) => { seen.push(['aggregate', value.occasionLink]); return aggregate; },
    syncHealth: async () => health,
  });
  assert.deepEqual(seen, [['backups', target.projectRef], ['aggregate', target.occasionLink]]);
  assert.equal(report.target.occasion.id, 643);
  assert.equal(report.databaseRecovery.pitr.enabled, false);
  assert.match(report.objectRecovery.limitation, /do not include/);
  assert.doesNotMatch(JSON.stringify(report), /not-reported/);
});

test('target mismatch and missing backups fail closed', async () => {
  const base = {
    target,
    syncHealth: async () => health,
    backupInventory: async () => ({ backups: [{ status: 'completed' }] }),
  };
  await assert.rejects(
    composeRecoveryReadiness({ ...base, aggregateReader: async () => ({ ...aggregate, occasion: null }) }),
    /occasion is absent/,
  );
  await assert.rejects(
    composeRecoveryReadiness({
      ...base,
      aggregateReader: async () => aggregate,
      backupInventory: async () => ({ backups: [], pitrEnabled: true }),
    }),
    /no completed authoritative/,
  );
});

test('fixed aggregate SQL is scoped and contains no write statement', () => {
  const queries = [buildRecoveryAggregateSql(target), buildRecoveryAuditSql(643)];
  assert.match(queries[0], /organization=9/);
  assert.match(queries[0], /csmostrava2026/);
  for (const sql of queries) {
    assert.doesNotMatch(sql, /(?:^|;)\s*(?:UPDATE|DELETE|INSERT|ALTER|DROP|GRANT|REVOKE)\b/im);
  }
});

test('missing audit schema remains sanitized read-only evidence', async () => {
  const report = await composeRecoveryReadiness({
    target,
    backupInventory: async () => ({ backups: [{ status: 'completed' }] }),
    aggregateReader: async () => ({
      ...aggregate,
      schemas: { ...aggregate.schemas, clientCommits: false },
      audit: { available: false, count: null, firstAt: null, lastAt: null },
    }),
    syncHealth: async () => health,
  });
  assert.equal(report.schemas.clientCommits, false);
  assert.equal(report.audit.available, false);
});

test('canonical target comes from project config, never legacy env project ref', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'festapp-recovery-target-'));
  try {
    await mkdir(path.join(root, 'automation'));
    await writeFile(path.join(root, 'automation/project.conf'), [
      'SUPABASE_URL=https://lwfpdjxsdmkfyrzqbrlk.supabase.co',
      'ORGANIZATION_ID=9',
      'FORCE_OCCASION_LINK=csmostrava2026',
    ].join('\n'));
    await writeFile(path.join(root, '.env.local'), [
      'SUPABASE_ACCESS_TOKEN=test-token',
      'FESTAPP_SUPABASE_PROJECT_REF=legacywrongref',
    ].join('\n'));
    const loaded = loadCanonicalSupabaseTarget(root);
    assert.equal(loaded.projectRef, 'lwfpdjxsdmkfyrzqbrlk');
    assert.equal(loaded.occasionLink, 'csmostrava2026');
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('backup adapter uses one bounded GET and sanitizes provider rows', async () => {
  const calls = [];
  const inventory = await collectBackupInventory(target, {
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return new Response(JSON.stringify({
        pitr_enabled: true,
        pitr_retention_days: 7,
        backups: [{
          id: 'daily-1', status: 'completed', type: 'daily',
          started_at: '2026-08-07T00:00:00Z', private_payload: { secret: true },
        }],
      }));
    },
  });
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/projects\/lwfpdjxsdmkfyrzqbrlk\/database\/backups$/);
  assert.equal(calls[0].options.method, undefined);
  assert.equal(calls[0].options.body, undefined);
  assert.equal(inventory.pitrEnabled, true);
  assert.doesNotMatch(JSON.stringify(inventory), /private_payload|secret/);

  await assert.rejects(
    collectBackupInventory(target, {
      fetchImpl: async () => new Response('', { status: 503 }),
    }),
    /HTTP 503/,
  );
});

test('aggregate adapter issues only fixed SELECTs and skips audit when unavailable', async () => {
  const queries = [];
  const reader = async ({ query }) => {
    queries.push(query);
    return queries.length === 1
      ? [{ result: { occasion: aggregate.occasion, schemas: aggregate.schemas } }]
      : [{ result: aggregate.audit }];
  };
  const result = await collectRecoveryAggregates(target, { query: reader });
  assert.deepEqual(result.audit, aggregate.audit);
  assert.equal(queries.length, 2);
  assert.ok(queries.every((sql) => /^\s*(?:WITH|SELECT)\b/i.test(sql)));
  assert.ok(queries.every((sql) =>
    !/(?:UPDATE|DELETE|INSERT|ALTER|DROP|GRANT|REVOKE)\b/i.test(sql)));

  const missingQueries = [];
  const missing = await collectRecoveryAggregates(target, {
    query: async ({ query }) => {
      missingQueries.push(query);
      return [{ result: {
        occasion: aggregate.occasion,
        schemas: { ...aggregate.schemas, clientCommits: false },
      } }];
    },
  });
  assert.equal(missingQueries.length, 1);
  assert.equal(missing.audit.available, false);
});

test('PITR enabled produces no RPO warning', async () => {
  const report = await composeRecoveryReadiness({
    target,
    backupInventory: async () => ({
      pitrEnabled: true,
      pitrRetentionDays: 7,
      backups: [{ status: 'completed' }],
    }),
    aggregateReader: async () => aggregate,
    syncHealth: async () => health,
  });
  assert.equal(report.databaseRecovery.pitr.warning, null);
});
