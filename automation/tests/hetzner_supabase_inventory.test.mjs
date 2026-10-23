import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import {readHistoricalSql} from '../lib/historical_sql.mjs';
import test from 'node:test';
import path from 'node:path';
import {SOURCES,REPOSITORY_ROOT,assertPrivateOutput,assertNewEvidencePaths,sha256,stableJson} from '../hetzner-supabase/merge/lib.mjs';
import {buildWriteInventory,classifyWriteEntry,scanWriteSignals} from '../hetzner-supabase/merge/write-authority-inventory.mjs';
import {auditLegacyAdapters,loadWriteAuthorityPolicy} from '../hetzner-supabase/merge/client-adapter-audit.mjs';
import {evaluateRuntimeWriterPolicy,loadRuntimeWriterPolicy} from '../hetzner-supabase/merge/runtime-writer-policy.mjs';

test('every Edge Function and Worker entrypoint has a fail-closed cutover classification', () => {
  const policy = loadRuntimeWriterPolicy();
  const report = evaluateRuntimeWriterPolicy(policy);
  assert.equal(report.status, 'pass');
  assert.deepEqual(report.blockers, []);
  assert.equal(report.edge_functions, Object.keys(policy.edge_functions).length);
  assert.equal(report.worker_entrypoints, Object.keys(policy.workers).length);
  assert.equal(report.mutating_surfaces, [...Object.values(policy.edge_functions),...Object.values(policy.workers)].filter(x=>x.mutates_authority).length);
  for (const name of ['bank-sync-webhook', 'bank-sync-manage', 'bank-sync-reconcile']) {
    assert.equal(policy.edge_functions[name].mutates_authority, true);
  }
  assert.equal(policy.edge_functions['preview-ticket-layout'].mutates_authority, false);
  for (const name of ['google-auth-start', 'google-auth-callback', 'google-auth-complete', 'exchange-sign-in-code']) {
    assert.equal(policy.edge_functions[name].mutates_authority, true);
  }
  assert.equal(report.canonical_security_blockers.length, 0);
  assert.match(report.canonical_exclusions[0], /instance-install/);
  assert.equal(policy.edge_functions['instance-install'], undefined);
  assert.equal(fs.existsSync(path.join(REPOSITORY_ROOT, 'supabase/functions/instance-install/index.ts')), false);
  assert.equal(report.activation_requirements.length, 7);

  const incomplete = structuredClone(policy);
  delete incomplete.edge_functions.notify;
  assert.match(
    evaluateRuntimeWriterPolicy(incomplete).blockers.join('\n'),
    /unclassified edge function: notify/,
  );

  const missingMjsWorker = structuredClone(policy);
  delete missingMjsWorker.workers['supabase-legacy-keepalive'];
  assert.match(
    evaluateRuntimeWriterPolicy(missingMjsWorker).blockers.join('\n'),
    /unclassified worker entrypoint: workers\/supabase-legacy-keepalive\/src\/index\.mjs/,
  );
});

test('source aliases are pinned to the approved cloud projects', () => {
  assert.deepEqual(SOURCES, {
    default: 'kjdpmixlnhntmxjedpxh',
    a: 'lwfpdjxsdmkfyrzqbrlk',
    slunovrat: 'hvtsoseaywurkmhywdbd',
  });
});

test('production evidence cannot be written inside the repository', () => {
  assert.throws(() => assertPrivateOutput(path.join(REPOSITORY_ROOT, 'inventory.json')));
  assert.equal(assertPrivateOutput('/tmp/festapp-wave-0/inventory.json'), '/tmp/festapp-wave-0/inventory.json');
});

test('existing evidence is never overwritten', () => {
  assert.throws(() => assertNewEvidencePaths([new URL(import.meta.url).pathname]), /refusing to overwrite/);
});

test('stable JSON and fingerprints do not depend on object key order', () => {
  assert.equal(stableJson({ b: 2, a: 1 }), stableJson({ a: 1, b: 2 }));
  assert.equal(sha256(stableJson({ b: 2, a: 1 })), sha256(stableJson({ a: 1, b: 2 })));
});

test('write-authority scanner includes auth, operator and object-storage writers', () => {
  const signals = scanWriteSignals(`
    await supabase.from('orders').insert(payload);
    await supabase.rpc('create_order', payload);
    await supabase.storage.from('public-files').remove(['a']);
    await supabase.auth.refreshSession();
    await env.IMAGES.put(key, body);
    SELECT cron.schedule('job', '* * * * *', $$ SELECT net.http_post(url := 'x') $$);
    await managementQuery({ query: 'select 1' });
    supabase functions deploy send-email
    await deliverEmail();
    await fetch('https://fioapi.fio.cz/v1/rest/last/token/transactions.json');
    await fetch('https://app.fakturoid.cz/api/v3/oauth/token');
    await fetch('https://api.onesignal.com/apps/id/users/user');
    const SNS_TYPE_CONFIRMATION = 'SubscriptionConfirmation';
  `);
  assert.deepEqual(signals, [
    'auth-mutation',
    'bank-api-side-effect',
    'database-webhook',
    'deployment-mutation',
    'direct-dml',
    'direct-sql-client',
    'email-side-effect',
    'invoicing-side-effect',
    'object-storage-mutation',
    'provider-callback',
    'push-side-effect',
    'rpc',
    'sql-cron',
    'storage-mutation',
  ]);
});

test('write-authority classification maps entrypoints onto full-freeze controls', () => {
  assert.deepEqual(
    classifyWriteEntry('lib/data_services/auth_service.dart', ['auth-mutation', 'rpc']),
    {
      write_owner: 'flutter-client',
      freeze_lanes: ['application', 'auth-refresh'],
      required_controls: [
        'maintenance-mode-and-source-database-role-revocation',
        'source-auth-refresh-deny-and-active-session-drain',
      ],
      status: 'classified',
    },
  );
  assert.equal(
    classifyWriteEntry('unknown/runtime.js', ['direct-dml']).status,
    'unreviewed',
  );
});

test('repository writer inventory has no unclassified discovered entrypoint', () => {
  const inventory = buildWriteInventory();
  assert.ok(inventory.entries.length >= 100);
  assert.equal(inventory.validation.status, 'pass');
  assert.equal(inventory.validation.inventory_status, 'complete');
  assert.equal(inventory.validation.unknown_writers, 0);
  assert.ok(inventory.validation.direct_dml_candidates > 0);
  assert.deepEqual(Object.keys(inventory.freeze_lane_counts).sort(), [
    'application',
    'auth-refresh',
    'cron',
    'edge-functions',
    'manual',
    'storage',
    'webhooks',
  ]);
});

test('all known Flutter DML adapters have an existing typed RPC seam', () => {
  const policy = loadWriteAuthorityPolicy();
  const audit = auditLegacyAdapters(policy);
  assert.equal(audit.entries.length, 9);
  assert.equal(audit.seam_detected_adapters, 9);
  assert.equal(audit.coverage_proof, 'partial-static-evidence-not-operation-completeness');
  assert.ok(audit.rpc_names.length >= 30);
  assert.ok(audit.rpc_names.includes('save_event_client_sync_v1'));
  assert.ok(audit.rpc_names.includes('save_profile_client_sync_v1'));
});

test('historical RPC search-path hardening covers its frozen signature set and is non-destructive', () => {
  const migration = readHistoricalSql('supabase/migrations/20260827120000_harden_client_sync_rpc_search_paths.sql');
  const expected = [...migration.match(/v_names constant text\[\] := ARRAY\[([\s\S]*?)\]/)[1].matchAll(/'([a-z0-9_]+)'/g)].map(match => match[1]).sort();
  const altered = [...migration.matchAll(
    /ALTER FUNCTION public\.([a-z0-9_]+)\([^;]+?\)\s+SET search_path TO public, extensions;/g,
  )].map((match) => match[1]).sort();
  assert.deepEqual(altered, expected);
  assert.equal(altered.length, 41);
  assert.match(migration, /unexpected client_sync RPC signature count/);
  assert.match(migration, /non-canonical client_sync RPC overload remains/);
  assert.doesNotMatch(migration, /\b(?:DELETE|DROP|REVOKE|TRUNCATE)\b/i);
  assert.doesNotMatch(migration, /CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER/i);
});

test('canonical notification webhook is secret-authenticated and starts disabled', () => {
  const migration = readHistoricalSql('supabase/migrations/20260902190000_authenticate_notification_webhook.sql');
  assert.match(migration, /SECURITY DEFINER/);
  assert.match(migration, /SET search_path = ''/);
  assert.match(migration, /festapp_notify_webhook_token_v1/);
  assert.match(migration, /'Authorization', 'Bearer ' \|\| webhook_token/);
  assert.match(migration, /DROP TRIGGER IF EXISTS push_log_notifications/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.setup_triggers/);
  assert.match(migration, /deliver_log_notification_v1\(%L\)/);
  assert.doesNotMatch(migration, /supabase_functions\.http_request/);
  assert.doesNotMatch(migration, /Bearer [A-Za-z0-9_-]{32}/);
});

test('canonical-only adapter audit blocks a reintroduced direct DML fallback', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-adapter-audit-'));
  try {
    fs.mkdirSync(path.join(root, 'lib'));
    const policy = { selection_contract: 'ClientSyncRuntime.isV1Selected', legacy_adapters: [
      { path: 'lib/adapter.dart', canonical_only: true, command_modules: ['lib/commands.dart'] },
    ] };
    fs.writeFileSync(path.join(root, 'lib/adapter.dart'), 'return commands.save(value);');
    fs.writeFileSync(path.join(root, 'lib/commands.dart'), "ClientCommandTransport transport; invoke('save_profile_client_sync_v1');");
    assert.equal(auditLegacyAdapters(policy, root).seam_detected_adapters, 1);
    fs.writeFileSync(path.join(root, 'lib/adapter.dart'), "return supabase.from('users').delete();");
    assert.equal(auditLegacyAdapters(policy, root).seam_detected_adapters, 0);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
