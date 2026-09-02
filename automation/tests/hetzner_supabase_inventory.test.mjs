import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import path from 'node:path';
import {
  SOURCES,
  REPOSITORY_ROOT,
  assertPrivateOutput,
  assertNewEvidencePaths,
  buildInventoryManifest,
  sha256,
  stableJson,
} from '../hetzner-supabase/merge/lib.mjs';
import {
  classifyAuthCollisions,
  classifyStorageCollisions,
} from '../hetzner-supabase/merge/collision-lib.mjs';
import { buildIdentityDecisions } from '../hetzner-supabase/merge/resolve-auth-collisions.mjs';
import {
  buildWriteInventory,
  classifyWriteEntry,
  scanWriteSignals,
} from '../hetzner-supabase/merge/write-authority-inventory.mjs';
import {
  auditLegacyAdapters,
  buildHybridReadiness,
  loadWriteAuthorityPolicy,
} from '../hetzner-supabase/merge/hybrid-readiness.mjs';
import {
  buildTenantConfigInventory,
  loadTenantCutoverPolicy,
  parseTenantConfig,
} from '../hetzner-supabase/merge/tenant-config-inventory.mjs';
import {
  buildMigrationHistoryReport,
} from '../hetzner-supabase/merge/migration-history-inventory.mjs';
import { buildCanonicalDriftReport } from '../hetzner-supabase/merge/canonical-drift.mjs';
import { buildTableImportReadiness } from '../hetzner-supabase/merge/table-import-readiness.mjs';
import {
  parseApprovedConnection,
  pgDumpArgs,
  validateRecipient,
} from '../hetzner-supabase/merge/export-source.mjs';
import { buildPageQuery } from '../hetzner-supabase/merge/export-managed-schemas.mjs';
import { csvField } from '../hetzner-supabase/merge/stage-managed-export.mjs';
import {
  evaluateRepositoryCutoverReadiness,
} from '../hetzner-supabase/merge/repository-cutover-preflight.mjs';
import {
  evaluateRuntimeWriterPolicy,
  loadRuntimeWriterPolicy,
} from '../hetzner-supabase/merge/runtime-writer-policy.mjs';

test('every Edge Function and Worker entrypoint has a fail-closed cutover classification', () => {
  const policy = loadRuntimeWriterPolicy();
  const report = evaluateRuntimeWriterPolicy(policy);
  assert.equal(report.status, 'pass');
  assert.deepEqual(report.blockers, []);
  assert.equal(report.edge_functions, 20);
  assert.equal(report.worker_entrypoints, 3);
  assert.equal(report.mutating_surfaces, 18);
  assert.equal(report.canonical_security_blockers.length, 0);
  assert.match(report.canonical_exclusions[0], /instance-install/);
  assert.equal(report.activation_requirements.length, 3);

  const incomplete = structuredClone(policy);
  delete incomplete.edge_functions.notify;
  assert.match(
    evaluateRuntimeWriterPolicy(incomplete).blockers.join('\n'),
    /unclassified edge function: notify/,
  );
});

test('source aliases are pinned to the approved cloud projects', () => {
  assert.deepEqual(SOURCES, {
    default: 'kjdpmixlnhntmxjedpxh',
    a: 'lwfpdjxsdmkfyrzqbrlk',
    slunovrat: 'hvtsoseaywurkmhywdbd',
  });
});

test('migration history comparison blocks drift and identifies expansion prerequisites', () => {
  const repository = [
    { version: '20260801000000', name: 'base', file: '20260801000000_base.sql', sha256: 'a'.repeat(64) },
    { version: '20260802234000', name: 'client_sync_v1_expansion', file: '20260802234000_client_sync_v1_expansion.sql', sha256: 'b'.repeat(64) },
    { version: '20260827120000', name: 'harden_client_sync_rpc_search_paths', file: '20260827120000_harden_client_sync_rpc_search_paths.sql', sha256: 'c'.repeat(64) },
  ];
  const report = buildMigrationHistoryReport({
    repository,
    sources: {
      default: [{ version: '20260801000000', name: 'base' }],
      a: repository.slice(0, 2).map(({ version, name }) => ({ version, name })),
      slunovrat: [],
    },
  });
  assert.equal(report.validation.status, 'blocked');
  assert.deepEqual(report.sources.default.repository_versions_not_recorded, [
    '20260802234000',
    '20260827120000',
  ]);
  assert.equal(report.sources.a.client_sync_expansion_recorded, true);
  assert.equal(report.sources.default.client_sync_expansion_recorded, false);
  assert.equal(report.sources.slunovrat.client_sync_expansion_recorded, false);
  assert.equal(report.validation.production_mutations_performed, false);
  assert.match(report.validation.blockers.join('\n'), /default.*client-sync expansion/i);
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

test('canonical drift compares both pinned sources to an isolated PG17 target', () => {
  const catalog = (relationName) => ({
    postgres_version: '17.6',
    postgres_version_num: '170006',
    relations: [{ schema_name: 'public', table_name: relationName, relkind: 'r', total_bytes: 1, estimated_rows: 2 }],
    columns: [], constraints: [], routines: [], policies: [], grants: [],
    extensions: [], publications: [], roles: [], collations: [],
  });
  const report = buildCanonicalDriftReport({
    defaultInventory: { source: { alias: 'default', project_ref: SOURCES.default }, schema_fingerprint_sha256: 'd'.repeat(64), catalog: catalog('same') },
    aInventory: { source: { alias: 'a', project_ref: SOURCES.a }, schema_fingerprint_sha256: 'a'.repeat(64), catalog: catalog('legacy') },
    targetCatalog: catalog('same'),
  });
  assert.equal(report.comparisons.default.unresolved_catalog_differences, 0);
  assert.equal(report.comparisons.a.unresolved_catalog_differences, 2);
  assert.deepEqual(report.comparisons.a.scope_counts, { application: 2, platform: 0 });
  assert.deepEqual(report.comparisons.a.classification_counts.application, {
    source_only: 1,
    target_only: 1,
    changed: 0,
  });
  assert.equal(report.validation.status, 'blocked');
  assert.equal(report.validation.production_mutations_performed, false);
});

test('table import readiness blocks incompatible and required target columns', () => {
  const relation = { schema_name: 'public', table_name: 'items', relkind: 'r' };
  const column = (column_name, overrides = {}) => ({
    ...relation, column_name, data_type: 'bigint', udt_schema: 'pg_catalog', udt_name: 'int8',
    is_nullable: 'NO', column_default: null, is_identity: 'NO', identity_generation: null,
    is_generated: 'NEVER', ...overrides,
  });
  const inventory = {
    source: { alias: 'default', project_ref: SOURCES.default },
    catalog: { relations: [relation], columns: [column('id'), column('legacy')] },
    exact_row_counts: { 'public.items': 4 },
  };
  const report = buildTableImportReadiness({
    inventory,
    targetCatalog: {
      postgres_version: '17.6', relations: [relation],
      columns: [column('id', { data_type: 'text', udt_name: 'text' }), column('required')],
    },
  });
  assert.equal(report.summary.blocked_tables, 1);
  assert.deepEqual(report.tables[0].source_only_columns, ['legacy']);
  assert.deepEqual(report.tables[0].incompatible_columns, ['id']);
  assert.deepEqual(report.tables[0].required_target_values, ['required']);
  assert.equal(report.validation.production_mutations_performed, false);
});

test('default transform policy fails closed on ambiguous companion history', () => {
  const policy = JSON.parse(fs.readFileSync(
    path.join(REPOSITORY_ROOT, 'automation/hetzner-supabase/merge/default-transform-policy.json'),
    'utf8',
  ));
  assert.equal(policy.source.projectRef, SOURCES.default);
  assert.equal(policy.status, 'blocked-pending-private-companion-decisions');
  assert.equal(policy.evidence.userCompanions.unresolvedRows, 2);
  assert.deepEqual(policy.evidence.userCompanions.commonOccasionCountHistogram, { 0: 2, 1: 1 });
  assert.equal(policy.productionMutationsPerformed, false);
  assert.equal(policy.rules.find((rule) => rule.table === 'public.user_companions').onFailure, 'block');
  assert.ok(policy.rules.filter((rule) => rule.action.includes('omit')).every(
    (rule) => rule.precondition === 'source-nonnull-count-equals-zero',
  ));
});

test('encrypted source export accepts only an approved project identity', () => {
  const direct = parseApprovedConnection(
    'default',
    `postgresql://postgres:secret@db.${SOURCES.default}.supabase.co:5432/postgres`,
  );
  assert.equal(direct.projectRef, SOURCES.default);
  assert.equal(direct.connectionKind, 'direct');
  assert.equal(pgDumpArgs(direct).includes('secret'), false);

  const pooled = parseApprovedConnection(
    'a',
    `postgresql://postgres.${SOURCES.a}:secret@aws-0-eu-central-1.pooler.supabase.com:5432/postgres`,
  );
  assert.equal(pooled.projectRef, SOURCES.a);
  assert.equal(pooled.connectionKind, 'session-pooler');
  assert.throws(
    () => parseApprovedConnection('default', `postgresql://postgres:secret@db.${SOURCES.a}.supabase.co/postgres`),
    /approved source ref/,
  );
  assert.throws(
    () => parseApprovedConnection('default', `postgresql://postgres.${SOURCES.a}:secret@aws-0-eu-central-1.pooler.supabase.com/postgres`),
    /approved source ref/,
  );
  const temporary = parseApprovedConnection(
    'default',
    `postgresql://festapp_export_1787840000000.${SOURCES.default}:secret@aws-0-eu-central-1.pooler.supabase.com/postgres`,
  );
  assert.equal(temporary.username, `festapp_export_1787840000000.${SOURCES.default}`);
  assert.equal(validateRecipient('age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq'),
    'age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq');
  assert.equal(validateRecipient('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexampleexampleexampleexampleexample user@host'),
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexampleexampleexampleexampleexample user@host');
  assert.throws(() => validateRecipient('ssh-rsa unsafe'), /native age or SSH Ed25519/);
});

test('managed schema export pages only approved primary-key tables', () => {
  assert.equal(
    buildPageQuery({ schema_name: 'auth', table_name: 'users', primary_key: ['id'] }, 10_000),
    'SELECT to_jsonb(source_row) AS row FROM "auth"."users" AS source_row ORDER BY source_row."id" LIMIT 10000 OFFSET 10000',
  );
  assert.throws(
    () => buildPageQuery({ schema_name: 'public', table_name: 'users', primary_key: ['id'] }, 0),
    /unapproved managed schema/,
  );
  assert.throws(
    () => buildPageQuery({ schema_name: 'storage', table_name: 'objects', primary_key: [] }, 0),
    /no primary key/,
  );
  assert.throws(
    () => buildPageQuery({ schema_name: 'auth', table_name: 'users', primary_key: ['id'] }, 0, 10_001),
    /invalid managed export page/,
  );
});

test('managed staging CSV escapes JSON without plaintext files', () => {
  assert.equal(csvField('a"b'), '"a""b"');
  assert.equal(csvField('{"key":"value"}'), '"{""key"":""value""}"');
});

test('inventory creates a blocked evidence manifest with the required provenance', () => {
  const inventory = {
    source: { alias: 'default', project_ref: SOURCES.default },
    generated_at: '2026-08-27T12:00:00.000Z',
    schema_fingerprint_sha256: 'a'.repeat(64),
    catalog: { relations: [{}, {}] },
    exact_row_counts: { 'public.a': 2, 'public.b': 3 },
    edge_functions: { functions: [{}] },
    supplemental: {
      storage: { object_count: 7, object_bytes: 1024 },
      auth: { users: 11 },
    },
    limitations: ['collision pass incomplete'],
  };
  const manifest = buildInventoryManifest({ inventory, inventoryChecksum: 'b'.repeat(64) });
  assert.equal(manifest.phase, 'inventory');
  assert.equal(manifest.validation.status, 'blocked');
  assert.equal(manifest.validation.unresolved_conflicts, null);
  assert.equal(manifest.validation.orphan_foreign_keys, null);
  assert.equal(manifest.counts.rows, 5);
  assert.equal(manifest.counts.storage_objects, 7);
  assert.equal(manifest.counts.storage_bytes, 1024);
  assert.equal(manifest.counts.auth_users, 11);
  assert.deepEqual(manifest.sources[0], {
    alias: 'default',
    project_ref: SOURCES.default,
    schema_fingerprint: 'a'.repeat(64),
    snapshot_at: inventory.generated_at,
    journal_position: null,
  });
});

test('identity collisions block conflicting UUID and verified-email merges', () => {
  const result = classifyAuthCollisions(
    [{ id: 'd1', normalized_email: 'same@example.test', verified: true }, { id: 'same-id', normalized_email: 'old@example.test', verified: true }],
    [{ id: 'a1', normalized_email: 'same@example.test', verified: true }, { id: 'same-id', normalized_email: 'new@example.test', verified: true }],
    Buffer.alloc(32, 1),
  );
  assert.equal(result.same_email_different_uuid.length, 1);
  assert.equal(result.same_email_different_uuid[0].status, 'manual-merge-required');
  assert.equal(result.same_uuid_different_email.length, 1);
  assert.equal(result.same_email_different_uuid[0].email_hmac.length, 64);
});

test('identity inventory detects provider-key and verified-phone collisions outside e-mail matches', () => {
  const result = classifyAuthCollisions(
    [{ id: 'd1', normalized_email: 'd@example.test', verified: true, normalized_phone: '+4201', phone_verified: true, provider_links: [{ provider: 'google', provider_id: 'provider-key' }] }],
    [{ id: 'a1', normalized_email: 'a@example.test', verified: true, normalized_phone: '+4201', phone_verified: true, provider_links: [{ provider: 'google', provider_id: 'provider-key' }] }],
    Buffer.alloc(32, 3),
  );
  assert.equal(result.same_provider_identity_different_uuid.length, 1);
  assert.equal(result.same_verified_phone_different_uuid.length, 1);
  assert.equal(result.same_provider_identity_different_uuid[0].provider_id_hmac.length, 64);
  assert.equal(result.same_verified_phone_different_uuid[0].phone_hmac.length, 64);
});

test('Storage collisions never treat matching metadata as content proof', () => {
  const result = classifyStorageCollisions(
    [{ bucket_id: 'public', name: 'same.jpg', etag: 'etag', size: '12' }],
    [{ bucket_id: 'public', name: 'same.jpg', etag: 'etag', size: '12' }],
    Buffer.alloc(32, 2),
  );
  assert.equal(result.length, 1);
  assert.equal(result[0].status, 'requires-object-sha256-confirmation');
  assert.equal(result[0].object_key_hmac.length, 64);
});

test('verified e-mail collisions preserve default UUID and force source password reset', () => {
  const collisionReport = {
    report_version: 2,
    sources: SOURCES,
    auth: {
      same_uuid_different_email: [],
      same_provider_identity_different_uuid: [],
      same_verified_phone_different_uuid: [],
      same_email_different_uuid: [{
        default_user_id: 'default-user',
        a_user_id: 'a-user',
        email_hmac: 'd'.repeat(64),
        default_verified: true,
        a_verified: true,
        default_auth_state: simpleEmailAuthState(),
        a_auth_state: simpleEmailAuthState(),
        status: 'manual-merge-required',
      }],
    },
  };
  collisionReport.report_sha256 = sha256(stableJson(collisionReport));
  const result = buildIdentityDecisions(collisionReport);
  assert.equal(result.validation.unresolved, 0);
  assert.deepEqual(result.decisions[0], {
    source_project: 'a',
    source_user_id: 'a-user',
    target_user_id: 'default-user',
    email_hmac: 'd'.repeat(64),
    rule: 'verified-email-prefer-default-v1',
    canonical_password: 'preserve-default-hash',
    source_password: 'require-reset',
    memberships: 'merge-after-user-id-remap',
    providers: 'reconcile-without-duplicate-email-identity',
    provider_evidence: 'email-only-on-both-sources',
    mfa_evidence: 'none-on-both-sources',
    pending_token_evidence: 'none-on-both-sources',
    status: 'approved-by-execution-rule',
  });
});

test('identity resolver blocks unverified or UUID/e-mail ambiguity', () => {
  const report = {
    report_version: 2,
    sources: SOURCES,
    auth: {
      same_uuid_different_email: [{ id: 'blocker' }],
      same_email_different_uuid: [],
      same_provider_identity_different_uuid: [],
      same_verified_phone_different_uuid: [],
    },
  };
  report.report_sha256 = sha256(stableJson(report));
  assert.throws(() => buildIdentityDecisions(report), /same UUID/);
});

test('identity resolver verifies collision provenance and blocks nontrivial Auth state', () => {
  const report = {
    report_version: 2,
    sources: SOURCES,
    auth: {
      same_uuid_different_email: [],
      same_provider_identity_different_uuid: [],
      same_verified_phone_different_uuid: [],
      same_email_different_uuid: [{
        default_user_id: 'default-user', a_user_id: 'a-user', email_hmac: 'f'.repeat(64),
        default_verified: true, a_verified: true, status: 'manual-merge-required',
        default_auth_state: simpleEmailAuthState(),
        a_auth_state: { ...simpleEmailAuthState(), mfa: [{ factor_type: 'totp', status: 'verified' }] },
      }],
    },
  };
  report.report_sha256 = sha256(stableJson(report));
  assert.throws(() => buildIdentityDecisions(report), /provider, MFA/);
  report.report_sha256 = '0'.repeat(64);
  assert.throws(() => buildIdentityDecisions(report), /checksum mismatch/);
});

test('identity resolver rejects older reports without global provider and phone evidence', () => {
  const report = {
    report_version: 1,
    sources: SOURCES,
    auth: { same_uuid_different_email: [], same_email_different_uuid: [] },
  };
  report.report_sha256 = sha256(stableJson(report));
  assert.throws(() => buildIdentityDecisions(report), /report v2/);
});

test('later source identity resolver prefers the already merged canonical owner', () => {
  const report = {
    report_version: 3,
    source_alias: 'slunovrat',
    sources: SOURCES,
    compared_against: ['canonical'],
    comparisons: {
      canonical: {
        auth: {
          same_uuid_different_email: [],
          same_provider_identity_different_uuid: [],
          same_verified_phone_different_uuid: [],
          same_identity: [],
          same_email_different_uuid: [{
            canonical_user_id: 'canonical-user', source_user_id: 'slunovrat-user',
            email_hmac: 'e'.repeat(64), canonical_verified: true, source_verified: true,
            canonical_auth_state: simpleEmailAuthState(), source_auth_state: simpleEmailAuthState(),
            status: 'manual-merge-required',
          }],
        },
        storage: [],
      },
    },
  };
  report.report_sha256 = sha256(stableJson(report));
  const result = buildIdentityDecisions(report);
  assert.equal(result.validation.resolved, 1);
  assert.equal(result.decisions[0].source_project, 'slunovrat');
  assert.equal(result.decisions[0].canonical_source, 'canonical');
  assert.equal(result.decisions[0].target_user_id, 'canonical-user');
  assert.equal(result.decisions[0].canonical_password, 'preserve-existing-canonical-hash');
});

function simpleEmailAuthState() {
  return {
    providers: ['email'], provider_links: [{ provider: 'email', provider_id_hmac: '1'.repeat(64) }],
    mfa: [], phone_hmac: null, phone_verified: false,
    is_sso_user: false, is_anonymous: false,
    pending_tokens: { confirmation: false, recovery: false, email_change: false, phone_change: false, reauthentication: false },
  };
}

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

test('hybrid readiness blocks legacy cohorts and direct DML grants', () => {
  const policy = loadWriteAuthorityPolicy();
  const codeAudit = auditLegacyAdapters(policy);
  const functions = codeAudit.rpc_names.map((name) => ({
    name,
    identity_arguments: 'p_occasion bigint',
    security_definer: true,
    approved_search_path: true,
  }));
  const report = buildHybridReadiness({
    policy,
    codeAudit,
    live: {
      summary: {
        registry_total: 41,
        registry_ready: 41,
        occasion_total: 48,
        occasion_enabled: 1,
      },
      grants: [{ table_name: 'events', grantee: 'authenticated', privileges: ['UPDATE'] }],
      functions,
      cohorts: [],
    },
  });
  assert.equal(report.validation.status, 'blocked');
  assert.equal(report.live.occasion_disabled_or_unclassified, 47);
  assert.match(report.validation.blockers.join('\n'), /direct-DML/);
  assert.equal(report.validation.production_mutations_performed, false);
});

test('Flutter seam evidence never authorizes the global hybrid gate', () => {
  const policy = loadWriteAuthorityPolicy();
  const codeAudit = auditLegacyAdapters(policy);
  const report = buildHybridReadiness({
    policy,
    codeAudit,
    live: {
      summary: {
        registry_total: 41,
        registry_ready: 41,
        occasion_total: 48,
        occasion_enabled: 48,
      },
      grants: [],
      cohorts: [],
      functions: codeAudit.rpc_names.map((name) => ({
        name,
        identity_arguments: 'p_occasion bigint',
        security_definer: true,
        approved_search_path: true,
      })),
    },
  });
  assert.equal(report.validation.status, 'blocked');
  assert.equal(report.validation.hybrid_activation_authorized, false);
  assert.match(report.validation.blockers.at(-1), /outside this Flutter-seam report/);
});

test('every RPC overload must independently satisfy the exact security context', () => {
  const policy = loadWriteAuthorityPolicy();
  const codeAudit = auditLegacyAdapters(policy);
  const functions = codeAudit.rpc_names.map((name) => ({
    name,
    identity_arguments: 'p_occasion bigint',
    security_definer: true,
    approved_search_path: true,
  }));
  functions.push({
    name: functions[0].name,
    identity_arguments: 'p_payload jsonb',
    security_definer: true,
    approved_search_path: false,
  });
  const report = buildHybridReadiness({
    policy,
    codeAudit,
    live: {
      summary: { registry_total: 41, registry_ready: 41, occasion_total: 1, occasion_enabled: 1 },
      grants: [],
      cohorts: [],
      functions,
    },
  });
  assert.equal(report.live.rpc_functions_insecure.length, 1);
  assert.match(report.live.rpc_functions_insecure[0], /p_payload jsonb/);
});

test('tenant config inventory excludes keys and exposes broad non-default reachability', () => {
  const entry = parseTenantConfig(`
    SUPABASE_URL=https://${SOURCES.a}.supabase.co
    SUPABASE_ANON_KEY=must-not-escape
    ORGANIZATION_ID=4
    FORCE_OCCASION_LINK=
    IMAGE_PROJECT_ID=a
    DEPLOY_TARGET=netlify
    DOMAIN=example.test
  `, 'origin/prod/example');
  assert.equal(entry.source_alias, 'a');
  assert.equal(entry.reachability, 'all-visible-occasions');
  assert.equal(JSON.stringify(entry).includes('must-not-escape'), false);
  const report = buildTenantConfigInventory([{ ...entry, status: 'discovered' }]);
  assert.equal(report.counts.non_default_broad_reachability, 1);
  assert.equal(report.validation.status, 'fail');
  assert.match(report.validation.blockers[0], /no approved cutover disposition/);
});

test('tenant cutover policy classifies legacy refs and keeps external gates blocked', () => {
  const policy = loadTenantCutoverPolicy();
  const report = buildTenantConfigInventory([
    { branch: 'origin/prod/avapp', status: 'missing-project-conf' },
    { branch: 'origin/prod/ticketonline', status: 'missing-project-conf' },
    {
      ...parseTenantConfig(`
        SUPABASE_URL=https://${SOURCES.a}.supabase.co
        ORGANIZATION_ID=4
      `, 'origin/prod/hvezdamorska'),
      status: 'discovered',
    },
  ], policy);
  assert.equal(report.counts.unknown, 0);
  assert.equal(report.counts.pending_legacy_retirements, 2);
  assert.equal(report.validation.status, 'blocked');
  assert.match(report.validation.blockers.join('\n'), /avapp.*retirement evidence/);
  assert.match(report.validation.blockers.join('\n'), /hvezdamorska.*live application freeze/);
  assert.equal(
    report.entries.find((entry) => entry.branch.endsWith('ticketonline'))
      .cutover_disposition.closure,
    'closed',
  );
});

test('repository cutover preflight separates local readiness from live blockers', () => {
  const base = {
    gitState: {
      branch: 'main',
      head: 'a'.repeat(40),
      origin_main: 'a'.repeat(40),
      dirty_paths: [],
      active_branches_behind_main: [],
    },
    tenantInventory: {
      counts: {
        production_configs: 14,
        unknown: 0,
        pending_legacy_retirements: 2,
        live_freeze_required: 5,
      },
      validation: {
        status: 'blocked',
        blockers: ['origin/prod/avapp: external retirement evidence pending'],
      },
    },
    writerInventory: {
      entries: Array.from({ length: 137 }),
      validation: { status: 'pass', unknown_writers: 0, direct_dml_candidates: 12 },
    },
    runtimePins: {
      release: 'self-hosted/v0.8.0',
      offline_verifier_passed: true,
      missing_compose_images: [],
    },
    tenantPolicy: { valid: true, blockers: [] },
    runtimeWriterPolicy: {
      status: 'pass', blockers: [], edge_functions: 20,
      worker_entrypoints: 3, mutating_surfaces: 18,
      canonical_security_blockers: [], canonical_exclusions: [],
      activation_requirements: [],
    },
  };
  const ready = evaluateRepositoryCutoverReadiness(base);
  assert.equal(ready.repository_ready, true);
  assert.equal(ready.production_cutover_authorized, false);
  assert.deepEqual(ready.blockers, []);
  assert.ok(ready.operational_blockers.length > 1);
  assert.ok(ready.operational_blockers.some((item) => item.includes('operational readiness gate')));

  const dirty = evaluateRepositoryCutoverReadiness({
    ...base,
    gitState: { ...base.gitState, dirty_paths: ['lib/app_config.dart'] },
  });
  assert.equal(dirty.repository_ready, false);
  assert.match(dirty.blockers[0], /working tree/);
});

test('RPC search-path hardening is exhaustive, fail-closed and non-destructive', () => {
  const policy = loadWriteAuthorityPolicy();
  const expected = auditLegacyAdapters(policy).rpc_names;
  const migrationPath = path.join(
    REPOSITORY_ROOT,
    'supabase/migrations/20260827120000_harden_client_sync_rpc_search_paths.sql',
  );
  const migration = fs.readFileSync(migrationPath, 'utf8');
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
  const migration = fs.readFileSync(path.join(
    REPOSITORY_ROOT,
    'supabase/migrations/20260902190000_authenticate_notification_webhook.sql',
  ), 'utf8');
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
