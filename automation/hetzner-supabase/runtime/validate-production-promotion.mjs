#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const REQUIRED_SOURCE_ALIASES = Object.freeze(['a', 'default', 'slunovrat']);
const CALLBACK_PATHS = Object.freeze([
  '/reset-password',
  '/resetPassword',
  '/auth_bridge',
  '/auth_bridge.html',
]);

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function normalizedOrigin(value, name) {
  let parsed;
  try { parsed = new URL(value); } catch { throw new Error(`${name} must be an HTTPS origin`); }
  invariant(parsed.protocol === 'https:' && parsed.username === '' && parsed.password === '' &&
    parsed.pathname === '/' && parsed.search === '' && parsed.hash === '',
  `${name} must be an HTTPS origin`);
  return parsed.origin;
}

function exactUniqueStrings(values, name) {
  invariant(Array.isArray(values) && values.length > 0, `${name} must be a non-empty array`);
  invariant(values.every((value) => typeof value === 'string' && value.length > 0),
    `${name} contains an invalid value`);
  invariant(new Set(values).size === values.length, `${name} contains duplicates`);
  return values;
}

function validateSourceRegistry(registry) {
  invariant(registry.version === 1 && Array.isArray(registry.sources),
    'unsupported source registry');
  const aliases = registry.sources.map((source) => source.alias).sort();
  invariant(JSON.stringify(aliases) === JSON.stringify(REQUIRED_SOURCE_ALIASES),
    'production source registry must contain exactly a, default and slunovrat');
  for (const source of registry.sources) {
    invariant(/^[a-z][a-z0-9_-]*$/.test(source.alias ?? ''), 'invalid source alias');
    invariant(/^[a-z]{20}$/.test(source.project_ref ?? ''),
      `${source.alias} project ref is invalid`);
    invariant(source.role === 'canonical-base' || source.role === 'merge-source',
      `${source.alias} role is invalid`);
    exactUniqueStrings(source.tenant_ids, `${source.alias} tenant_ids`);
  }
  const tenants = registry.sources.flatMap((source) => source.tenant_ids).sort();
  invariant(new Set(tenants).size === tenants.length, 'tenant IDs overlap source projects');
  return tenants;
}

function validateRuntimeConfig(config, sourceRegistrySha256, referenceRegistrySha256, tenants) {
  invariant(config.version === 1, 'unsupported production runtime config');
  invariant(config.source_registry_sha256 === sourceRegistrySha256,
    'runtime config source registry digest mismatch');
  invariant(config.reference_registry_sha256 === referenceRegistrySha256,
    'runtime config reference registry digest mismatch');
  invariant(config.public_hostname === 'api.festapp.net',
    'production public hostname must be api.festapp.net');
  invariant(config.supabase_public_url === 'https://api.festapp.net' &&
    config.api_external_url === 'https://api.festapp.net',
  'production external URLs must be canonical and equal');
  invariant(/^arn:aws:sns:[a-z0-9-]+:\d{12}:[A-Za-z0-9_-]+$/.test(config.aws_sns_topic_arn ?? ''),
    'production AWS SNS topic ARN is invalid');
  invariant(/^[0-9a-f]{64}$/.test(config.notify_webhook_token_sha256 ?? ''),
    'notification webhook token digest is invalid');
  const siteUrl = normalizedOrigin(config.site_url, 'site_url');
  const origins = exactUniqueStrings(config.allowed_web_origins, 'allowed_web_origins')
    .map((origin, index) => normalizedOrigin(origin, `allowed_web_origins[${index}]`));
  invariant(origins.includes(siteUrl), 'site_url is not an allowed web origin');

  const expectedRedirects = origins.flatMap((origin) =>
    CALLBACK_PATHS.map((callbackPath) => `${origin}${callbackPath}`)).sort();
  const redirects = exactUniqueStrings(config.auth_redirect_urls, 'auth_redirect_urls').sort();
  invariant(expectedRedirects.every((redirect) => redirects.includes(redirect)),
    'Auth redirect URLs do not cover every allowed origin and callback path');
  for (const [index, redirect] of redirects.entries()) {
    let parsed;
    try { parsed = new URL(redirect); } catch {
      throw new Error(`auth_redirect_urls[${index}] must be an HTTPS callback URL`);
    }
    invariant(parsed.protocol === 'https:' && parsed.username === '' && parsed.password === '' &&
      parsed.search === '' && parsed.hash === '' && origins.includes(parsed.origin) &&
      parsed.pathname.startsWith('/'),
    `auth_redirect_urls[${index}] is outside the allowed origins`);
  }

  invariant(Array.isArray(config.tenant_canaries), 'tenant_canaries must be an array');
  const canaryTenants = config.tenant_canaries.map((canary) => canary.tenant_id).sort();
  invariant(JSON.stringify(canaryTenants) === JSON.stringify(tenants),
    'tenant canaries must exactly cover the source registry tenants');
  invariant(new Set(canaryTenants).size === canaryTenants.length,
    'tenant canaries contain duplicates');
  for (const canary of config.tenant_canaries) {
    invariant(Number.isSafeInteger(canary.organization_id) && canary.organization_id > 0,
      `${canary.tenant_id} canonical organization ID is invalid`);
    invariant(typeof canary.occasion_link === 'string' &&
      /^[a-zA-Z0-9][a-zA-Z0-9_-]*$/.test(canary.occasion_link),
    `${canary.tenant_id} occasion link is invalid`);
    const webOrigin = normalizedOrigin(canary.web_origin, `${canary.tenant_id} web_origin`);
    invariant(origins.includes(webOrigin), `${canary.tenant_id} web origin is not allowed`);
    invariant(canary.activation_manifest_url === `${webOrigin}/backend-activation.json`,
      `${canary.tenant_id} activation manifest URL is not canonical`);
    invariant(/^[0-9a-f]{64}$/.test(canary.legacy_activation_sha256 ?? ''),
      `${canary.tenant_id} legacy activation digest is invalid`);
  }
}

export function validatePromotionEvidence({
  targetDatabase,
  sourceRegistry,
  referenceRegistry,
  finalMarker,
  backupManifest,
  restoreResult,
  runtimeConfig,
}) {
  invariant(/^festapp_rehearsal_[0-9]{14}$/.test(targetDatabase ?? ''),
    'promotion target must be a timestamped rehearsal database');
  const tenants = validateSourceRegistry(sourceRegistry);
  const sourceRegistrySha256 = sha256(stableJson(sourceRegistry));
  const referenceRegistrySha256 = sha256(stableJson(referenceRegistry));
  validateRuntimeConfig(runtimeConfig, sourceRegistrySha256, referenceRegistrySha256, tenants);

  invariant(finalMarker.decision_version === 1 && finalMarker.authorized === true &&
    finalMarker.mode === 'full-freeze' && finalMarker.phase === 'final-marker' &&
    finalMarker.write_freeze_required_until_activation_or_rollback === true &&
    finalMarker.gate_mutations_performed === false,
  'final-marker decision does not authorize a full-freeze promotion');
  const expectedProjects = Object.fromEntries(sourceRegistry.sources.map((source) =>
    [source.alias, source.project_ref]));
  invariant(stableJson(finalMarker.source_projects) === stableJson(expectedProjects),
    'final-marker source projects do not match the installed registry');
  invariant(/^[0-9a-f]{64}$/.test(finalMarker.evidence_sha256 ?? ''),
    'final-marker evidence digest is invalid');

  invariant(backupManifest.version === 2 && backupManifest.source_database === targetDatabase &&
    backupManifest.source_host === 'festapp-supabase-rehearsal-01' &&
    backupManifest.encrypted === true && backupManifest.plaintext_artifacts_written === false &&
    backupManifest.cloud_sources_mutated === false && backupManifest.writes_frozen === true &&
    backupManifest.rpo_seconds === 0 && backupManifest.database?.validated_imports === 3,
  'backup manifest does not describe the frozen promotion target');
  invariant(backupManifest.consistency_check ===
    'runtime-stopped-zero-client-sessions-and-before-after-state-stable',
  'backup consistency contract is invalid');
  invariant(Date.parse(backupManifest.created_at) >= Date.parse(finalMarker.evidence_observed_at),
    'backup predates the authorized final marker');

  invariant(restoreResult.version === 1 && restoreResult.status === 'pass' &&
    restoreResult.run_id === backupManifest.run_id && restoreResult.production_target_mutated === false &&
    restoreResult.cloud_sources_mutated === false && restoreResult.clean_cluster_stopped === true &&
    restoreResult.globals_restored === true && restoreResult.runtime_config_validated === true &&
    restoreResult.ownership_acl_equivalence === true &&
    Array.isArray(restoreResult.deleted_paths) && restoreResult.deleted_paths.length === 0,
  'restore drill does not satisfy the isolated recovery contract');
  invariant(/^festapp_restore_[0-9]+$/.test(restoreResult.target_database ?? ''),
    'restore drill target is not isolated');
  for (const key of ['auth_users', 'storage_objects', 'public_scopes', 'validated_imports']) {
    invariant(restoreResult.database?.[key] === backupManifest.database?.[key],
      `restore database mismatch: ${key}`);
  }
  for (const key of ['files', 'bytes', 'tree_sha256']) {
    invariant(restoreResult.storage?.[key] === backupManifest.storage?.[key],
      `restore Storage mismatch: ${key}`);
  }
  invariant(restoreResult.role_security_sha256 === backupManifest.role_security_sha256 &&
    restoreResult.object_security_sha256 === backupManifest.object_security_sha256,
  'restore security inventory mismatch');

  return {
    contract_version: 1,
    target_database: targetDatabase,
    source_registry_sha256: sourceRegistrySha256,
    reference_registry_sha256: referenceRegistrySha256,
    validated_source_aliases: REQUIRED_SOURCE_ALIASES,
    reference_registry_passes_required:
      sourceRegistry.sources.filter((source) => source.role === 'merge-source').length,
    tenant_canaries_required: tenants.length,
    backup_run_id: backupManifest.run_id,
    restore_attempt_id: restoreResult.attempt_id,
    final_marker_evidence_sha256: finalMarker.evidence_sha256,
    client_activation_documents_published: false,
    external_write_authority_opened: false,
  };
}

function argument(name) {
  const prefix = `--${name}=`;
  return process.argv.find((value) => value.startsWith(prefix))?.slice(prefix.length);
}

function readJson(name) {
  const value = argument(name);
  invariant(value && path.isAbsolute(value), `--${name} must be an absolute path`);
  return JSON.parse(fs.readFileSync(value, 'utf8'));
}

async function main() {
  const digestJson = argument('digest-json');
  if (digestJson) {
    invariant(path.isAbsolute(digestJson), '--digest-json must be an absolute path');
    process.stdout.write(`${sha256(stableJson(JSON.parse(fs.readFileSync(digestJson, 'utf8'))))}\n`);
    return;
  }
  const output = argument('output');
  invariant(output && path.isAbsolute(output), '--output must be an absolute path');
  invariant(!fs.existsSync(output), 'promotion validation output already exists');
  const result = validatePromotionEvidence({
    targetDatabase: argument('target-database'),
    sourceRegistry: readJson('source-registry'),
    referenceRegistry: readJson('reference-registry'),
    finalMarker: readJson('final-marker'),
    backupManifest: readJson('backup-manifest'),
    restoreResult: readJson('restore-result'),
    runtimeConfig: readJson('runtime-config'),
  });
  fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
  fs.writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write('Production promotion evidence validated without runtime mutation.\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  });
}
