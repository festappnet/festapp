import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { validatePromotionEvidence } from
  '../hetzner-supabase/runtime/validate-production-promotion.mjs';

const root = path.resolve(import.meta.dirname, '../..');
const runtime = path.join(root, 'automation/hetzner-supabase/runtime');

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function digest(value) {
  return crypto.createHash('sha256').update(stableJson(value)).digest('hex');
}

function fixture() {
  const sourceRegistry = {
    version: 1,
    sources: [
      { alias: 'default', project_ref: 'kjdpmixlnhntmxjedpxh', role: 'canonical-base', tenant_ids: ['festapp'] },
      { alias: 'a', project_ref: 'lwfpdjxsdmkfyrzqbrlk', role: 'merge-source', tenant_ids: ['csm'] },
      { alias: 'slunovrat', project_ref: 'hvtsoseaywurkmhywdbd', role: 'merge-source', tenant_ids: ['slunovrat'] },
    ],
  };
  const referenceRegistry = {
    version: '2026-08-28.1', status: 'rehearsal-validated-cutover-blocking',
    rules: [{ table: 'public.events', path: 'occasion', reference: 'public.occasions.id' }],
    requiredInventoryFamilies: ['scalar-references'],
    cutoverGates: ['production-hostname-and-origin-health'],
  };
  const runtimeWriterPolicy = {
    version: 1,
    edge_functions: { notify: { mutates_authority: false } },
    canonical_function_security: { excluded: {} },
  };
  const origins = ['https://live.festapp.net', 'https://csm.festapp.net', 'https://slunovrat.example'];
  const callbackPaths = ['/reset-password', '/resetPassword', '/auth_bridge', '/auth_bridge.html'];
  const runtimeConfig = {
    version: 1,
    source_registry_sha256: digest(sourceRegistry),
    reference_registry_sha256: digest(referenceRegistry),
    runtime_writer_policy_sha256: digest(runtimeWriterPolicy),
    function_bundle_sha256: '9'.repeat(64),
    public_hostname: 'api.festapp.net',
    supabase_public_url: 'https://api.festapp.net',
    api_external_url: 'https://api.festapp.net',
    aws_sns_topic_arn: 'arn:aws:sns:eu-central-1:274371802740:festapp-bank-emails',
    notify_webhook_token_sha256: 'f'.repeat(64),
    site_url: origins[0],
    allowed_web_origins: origins,
    auth_redirect_urls: origins.flatMap((origin) => callbackPaths.map((item) => `${origin}${item}`)),
    tenant_canaries: [
      ['festapp', 1, 'festapp', origins[0]],
      ['csm', 12, 'csm2026', origins[1]],
      ['slunovrat', 19, 'slunovrat2026', origins[2]],
    ].map(([tenant_id, organization_id, occasion_link, web_origin]) => ({
      tenant_id, organization_id, occasion_link, web_origin,
      activation_manifest_url: `${web_origin}/backend-activation.json`,
      legacy_activation_sha256: 'a'.repeat(64),
    })),
  };
  const database = { auth_users: 10, storage_objects: 20, public_scopes: 30, validated_imports: 3 };
  const storage = { files: 40, bytes: 50, tree_sha256: 'b'.repeat(64) };
  const targetImports = sourceRegistry.sources.map((source, index) => ({
    source_alias: source.alias,
    source_project_ref: source.project_ref,
    run_id: `${index + 1}0000000-0000-4000-8000-000000000000`,
    snapshot_at: '2026-08-30T00:59:00Z',
    source_schema_fingerprint: `${index + 1}`.repeat(64),
    transformation_version: `${source.alias}-import-v1`,
    status: 'validated',
  })).sort((a, b) => a.source_alias.localeCompare(b.source_alias));
  const sourceImports = Object.fromEntries(targetImports.map((item) => [item.source_alias, {
    final_marker: `${item.source_alias}-source-marker`,
    run_id: item.run_id,
    snapshot_at: item.snapshot_at,
    source_schema_fingerprint: item.source_schema_fingerprint,
    transformation_version: item.transformation_version,
  }]));
  const importInventorySha256 = digest(targetImports);
  return {
    targetDatabase: 'festapp_rehearsal_20260830010101', targetImports, sourceRegistry, referenceRegistry,
    runtimeWriterPolicy,
    operationalReadiness: {
      decision_version: 1, authorized: true, phase: 'pre-freeze',
      target_database: 'festapp_rehearsal_20260830010101', repository_head: '8'.repeat(40),
      maintenance_window_starts_at: '2026-08-30T01:00:00Z',
      maintenance_window_ends_at: '2026-08-30T05:00:00Z',
      expires_at: '2026-08-30T01:30:00Z', evidence_sha256: '7'.repeat(64),
      production_mutations_performed: false,
    },
    runtimeConfig,
    now: Date.parse('2026-08-30T01:10:00Z'),
    finalMarker: {
      decision_version: 1, authorized: true, mode: 'full-freeze', phase: 'final-marker',
      write_freeze_required_until_activation_or_rollback: true, gate_mutations_performed: false,
      source_projects: Object.fromEntries(sourceRegistry.sources.map((source) =>
        [source.alias, source.project_ref])),
      target_database: 'festapp_rehearsal_20260830010101',
      authorized_until: '2026-08-30T05:00:00Z',
      generated_at: '2026-08-30T01:00:05Z',
      source_imports: sourceImports,
      evidence_observed_at: '2026-08-30T01:00:00Z', evidence_sha256: 'c'.repeat(64),
    },
    backupManifest: {
      version: 3, run_id: '20260830T010100Z', created_at: '2026-08-30T01:01:00Z',
      source_host: 'festapp-supabase-rehearsal-01',
      source_database: 'festapp_rehearsal_20260830010101', encrypted: true,
      plaintext_artifacts_written: false, cloud_sources_mutated: false, writes_frozen: true,
      consistency_check: 'runtime-stopped-zero-client-sessions-and-before-after-state-stable',
      rpo_seconds: 0, role_security_sha256: 'd'.repeat(64),
      object_security_sha256: 'e'.repeat(64), database, storage,
      import_inventory: structuredClone(targetImports), import_inventory_sha256: importInventorySha256,
    },
    restoreResult: {
      version: 1, status: 'pass', run_id: '20260830T010100Z', attempt_id: 'restore-1',
      target_database: 'festapp_restore_20260830010200',
      database: structuredClone(database), storage: structuredClone(storage),
      role_security_sha256: 'd'.repeat(64),
      object_security_sha256: 'e'.repeat(64), clean_cluster_stopped: true,
      import_inventory: structuredClone(targetImports), import_inventory_sha256: importInventorySha256,
      globals_restored: true, runtime_config_validated: true, ownership_acl_equivalence: true,
      production_target_mutated: false, cloud_sources_mutated: false, deleted_paths: [],
    },
  };
}

test('production promotion accepts only the exact frozen three-source recovery contract', () => {
  const result = validatePromotionEvidence(fixture());
  assert.deepEqual(result.validated_source_aliases, ['a', 'default', 'slunovrat']);
  assert.equal(result.reference_registry_passes_required, 2);
  assert.equal(result.tenant_canaries_required, 3);
  assert.equal(result.client_activation_documents_published, false);
  assert.equal(result.external_write_authority_opened, false);
  assert.equal(result.import_inventory_sha256, digest(fixture().targetImports));
  assert.equal(result.function_bundle_sha256, '9'.repeat(64));
});

test('production promotion rejects stale markers and import inventory substitution', () => {
  const stale = fixture();
  stale.now = Date.parse('2026-08-30T06:00:00Z');
  stale.operationalReadiness.expires_at = '2026-08-30T06:30:00Z';
  stale.operationalReadiness.maintenance_window_ends_at = '2026-08-30T07:00:00Z';
  assert.throws(() => validatePromotionEvidence(stale), /authorization has expired/);

  const extended = fixture();
  extended.finalMarker.authorized_until = '2026-09-30T05:00:00Z';
  assert.throws(() => validatePromotionEvidence(extended), /authorization interval is invalid/);

  const substituted = fixture();
  substituted.targetImports[0].run_id = '90000000-0000-4000-8000-000000000000';
  assert.throws(() => validatePromotionEvidence(substituted), /does not bind target import run_id/);
});

test('production promotion requires fresh operational readiness for the exact target', () => {
  const stale = fixture();
  stale.operationalReadiness.expires_at = '2026-08-30T01:09:59Z';
  assert.throws(() => validatePromotionEvidence(stale), /operational readiness decision has expired/);

  const mismatched = fixture();
  mismatched.operationalReadiness.target_database = 'festapp_rehearsal_20260830010102';
  assert.throws(() => validatePromotionEvidence(mismatched), /operational readiness target/);
});

test('production promotion rejects an incomplete tenant canary set and mismatched restore', () => {
  const incomplete = fixture();
  incomplete.runtimeConfig.tenant_canaries.pop();
  assert.throws(() => validatePromotionEvidence(incomplete), /exactly cover/);
  const damaged = fixture();
  damaged.restoreResult.storage.bytes += 1;
  assert.throws(() => validatePromotionEvidence(damaged), /restore Storage mismatch/);
});

test('installed registries upgrade additively and rerun as a no-op', () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-runtime-registry-'));
  const candidateSource = path.join(temp, 'candidate-source.json');
  const installedSource = path.join(temp, 'installed-source.json');
  const candidateReference = path.join(temp, 'candidate-reference.json');
  const installedReference = path.join(temp, 'installed-reference.json');
  const source = fixture().sourceRegistry;
  const reference = fixture().referenceRegistry;
  fs.writeFileSync(candidateSource, JSON.stringify(source));
  fs.writeFileSync(installedSource, JSON.stringify({ ...source, sources: source.sources.slice(0, 2) }));
  fs.writeFileSync(candidateReference, JSON.stringify(reference));
  fs.writeFileSync(installedReference, JSON.stringify({ ...reference, rules: [] }));
  const args = [
    path.join(runtime, 'install-runtime-registries.mjs'),
    `--candidate-source=${candidateSource}`, `--candidate-reference=${candidateReference}`,
    `--installed-source=${installedSource}`, `--installed-reference=${installedReference}`,
  ];
  const first = spawnSync('node', args, { encoding: 'utf8' });
  assert.equal(first.status, 0, first.stderr);
  assert.deepEqual(JSON.parse(first.stdout).added_sources, ['slunovrat']);
  assert.equal(fs.statSync(installedSource).mode & 0o777, 0o444);
  const second = spawnSync('node', args, { encoding: 'utf8' });
  assert.equal(second.status, 0, second.stderr);
  assert.equal(JSON.parse(second.stdout).source_changed, false);
});

test('installed registries support explicit all-absent bootstrap and reject partial absence', () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-runtime-bootstrap-'));
  const candidateSource = path.join(temp, 'candidate-source.json');
  const candidateReference = path.join(temp, 'candidate-reference.json');
  const installedSource = path.join(temp, 'installed-source.json');
  const installedReference = path.join(temp, 'installed-reference.json');
  fs.writeFileSync(candidateSource, JSON.stringify(fixture().sourceRegistry));
  fs.writeFileSync(candidateReference, JSON.stringify(fixture().referenceRegistry));
  const baseArgs = [
    path.join(runtime, 'install-runtime-registries.mjs'),
    `--candidate-source=${candidateSource}`, `--candidate-reference=${candidateReference}`,
    `--installed-source=${installedSource}`, `--installed-reference=${installedReference}`,
  ];
  const withoutAck = spawnSync('node', baseArgs, { encoding: 'utf8' });
  assert.notEqual(withoutAck.status, 0);
  assert.match(withoutAck.stderr, /explicit bootstrap is required/);
  assert.equal(fs.existsSync(installedSource), false);
  assert.equal(fs.existsSync(installedReference), false);

  const bootstrap = spawnSync('node', [...baseArgs, '--allow-bootstrap'], { encoding: 'utf8' });
  assert.equal(bootstrap.status, 0, bootstrap.stderr);
  assert.equal(JSON.parse(bootstrap.stdout).bootstrap, true);
  assert.equal(fs.statSync(installedSource).mode & 0o777, 0o444);
  assert.equal(fs.statSync(installedReference).mode & 0o777, 0o444);

  const partialDir = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-runtime-partial-'));
  const partialSource = path.join(partialDir, 'installed-source.json');
  const partialReference = path.join(partialDir, 'installed-reference.json');
  fs.writeFileSync(partialSource, JSON.stringify(fixture().sourceRegistry));
  const partial = spawnSync('node', [
    path.join(runtime, 'install-runtime-registries.mjs'),
    `--candidate-source=${candidateSource}`, `--candidate-reference=${candidateReference}`,
    `--installed-source=${partialSource}`, `--installed-reference=${partialReference}`,
    '--allow-bootstrap',
  ], { encoding: 'utf8' });
  assert.notEqual(partial.status, 0);
  assert.match(partial.stderr, /forbidden partial state/);
});

test('promotion shell preserves rollback and excludes activation/write-authority mutations', () => {
  const promotion = fs.readFileSync(path.join(runtime, 'promote-production-runtime.sh'), 'utf8');
  const upgrade = fs.readFileSync(path.join(runtime, 'upgrade-installed-production-runtime.sh'), 'utf8');
  const barrier = fs.readFileSync(path.join(runtime, 'set-production-target-write-barrier.sh'), 'utf8');
  const bundleBuilder = fs.readFileSync(path.join(runtime, 'build-production-function-bundle.sh'), 'utf8');
  const bundleInstaller = fs.readFileSync(path.join(runtime, 'install-production-function-bundle.sh'), 'utf8');
  assert.match(promotion, /promote-validated-runtime-without-opening-write-authority/);
  assert.match(promotion, /\.env\.pre-production-promotion-/);
  assert.match(promotion, /client_activation_documents_published:false/);
  assert.match(promotion, /external_write_authority_opened:false/);
  assert.match(promotion, /target import registry mismatch/);
  assert.match(promotion, /default_transaction_read_only barrier is not closed/);
  assert.match(promotion, /select\(\.role=="merge-source"\)/);
  assert.match(promotion, /count\(DISTINCT r\.source_alias\)/);
  assert.match(promotion, /EXPECTED_REFERENCE_PASSES/);
  assert.match(promotion, /instance-install must not be present/);
  assert.match(promotion, /Edge Function directory set does not match/);
  assert.match(promotion, /Function bundle digest does not match/);
  assert.match(promotion, /tgname='push_log_notifications'/);
  assert.match(promotion, /AWS_SNS_TOPIC_ARN/);
  assert.match(promotion, /NOTIFY_WEBHOOK_TOKEN/);
  assert.match(promotion, /FESTAPP_OPERATIONAL_READINESS_DECISION/);
  assert.doesNotMatch(promotion, /BACKEND_ACTIVATION_PHASE=canonical|GRANT\s|REVOKE\s|ALTER ROLE/);
  assert.match(upgrade, /upgrade-installed-production-runtime-additively/);
  assert.match(upgrade, /bootstrap-missing-production-runtime-registries/);
  assert.match(upgrade, /forbidden partial state/);
  assert.match(upgrade, /docker-compose\.database-target\.yml/);
  assert.match(upgrade, /set-production-target-write-barrier\.sh/);
  assert.match(upgrade, /install-production-function-bundle\.sh/);
  assert.doesNotMatch(upgrade, /rm\s|DELETE FROM|DROP (?:DATABASE|SCHEMA|TABLE)/);
  assert.match(barrier, /close-target-writes-before-production-promotion/);
  assert.match(barrier, /open-canonical-writes-after-final-go-no-go/);
  assert.match(barrier, /ALTER DATABASE/);
  assert.match(barrier, /default_transaction_read_only/);
  assert.match(barrier, /pg_terminate_backend/);
  assert.match(bundleBuilder, /clean synchronized main/);
  assert.match(bundleBuilder, /instance-install/);
  assert.match(bundleInstaller, /unsafe path/);
  assert.match(bundleInstaller, /staged Function directory set is not canonical/);
  assert.match(bundleInstaller, /runtime_restarted:false/);
  assert.doesNotMatch(bundleInstaller, /docker compose (?:up|restart)/);
  for (const script of [promotion, upgrade, barrier, bundleBuilder, bundleInstaller]) {
    const syntax = spawnSync('bash', ['-n'], { input: script, encoding: 'utf8' });
    assert.equal(syntax.status, 0, syntax.stderr);
  }
});

test('host provisioning installs the runtime dependencies used by promotion tooling', () => {
  const bootstrap = fs.readFileSync(path.join(runtime, 'bootstrap-host.sh'), 'utf8');
  const deployment = fs.readFileSync(path.join(runtime, 'deploy-rehearsal.sh'), 'utf8');
  const cloudInit = fs.readFileSync(path.join(
    root, 'automation/hetzner-supabase/terraform/cloud-init.yaml.tftpl'), 'utf8');
  for (const dependency of ['jq', 'nodejs']) {
    assert.match(bootstrap, new RegExp(`apt-get install[^\\n]*\\b${dependency}\\b`));
    assert.match(cloudInit, new RegExp(`\\n  - ${dependency}\\n`));
  }
  for (const artifact of [
    'festapp-runtime-writer-policy.json', 'set-production-target-write-barrier.sh',
    'validate-operational-readiness.mjs', 'install-production-function-bundle.sh',
  ]) assert.match(deployment, new RegExp(artifact.replaceAll('.', '\\.')));
});
