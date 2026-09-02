#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const REQUIRED_FREEZE_LANES = Object.freeze([
  'application', 'auth-refresh', 'cron', 'edge-functions', 'manual', 'storage', 'webhooks',
]);
const REQUIRED_PROBES = Object.freeze(['auth', 'rest', 'storage', 'realtime']);
const REQUIRED_INTEGRATIONS = Object.freeze([
  'auth-password', 'auth-oauth', 'auth-refresh', 'aws-sns', 'edge-functions',
  'onesignal', 'payment-callbacks', 'realtime', 'smtp', 'storage', 'sync-worker',
]);
const MAX_EVIDENCE_AGE_MS = 30 * 60 * 1000;
const MAX_CANARY_AGE_MS = 24 * 60 * 60 * 1000;
const MAX_RECOVERY_PROOF_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_CLOCK_SKEW_MS = 60 * 1000;

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function instant(value, name) {
  const parsed = Date.parse(value ?? '');
  invariant(Number.isFinite(parsed), `${name} must be an ISO timestamp`);
  return parsed;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function receipt(value, name) {
  invariant(/^[0-9a-f]{64}$/.test(value ?? ''), `${name} evidence digest is invalid`);
}

function fresh(value, name, now, maxAge) {
  const parsed = instant(value, name);
  invariant(parsed <= now + MAX_CLOCK_SKEW_MS && now - parsed <= maxAge,
    `${name} is stale or from the future`);
  return parsed;
}

function exactNames(entries, required, name) {
  invariant(Array.isArray(entries), `${name} must be an array`);
  const names = entries.map((item) => item.name).sort();
  invariant(new Set(names).size === names.length, `${name} contains duplicates`);
  invariant(JSON.stringify(names) === JSON.stringify([...required].sort()),
    `${name} does not exactly cover the required set`);
}

export function validateOperationalReadiness(evidence, now = Date.now()) {
  invariant(evidence.version === 1, 'unsupported operational readiness evidence');
  invariant(/^festapp_rehearsal_[0-9]{14}$/.test(evidence.target_database ?? ''),
    'operational readiness must bind the exact timestamped promotion target');
  const observedAt = instant(evidence.observed_at, 'observed_at');
  invariant(observedAt <= now + MAX_CLOCK_SKEW_MS && now - observedAt <= MAX_EVIDENCE_AGE_MS,
    'operational readiness evidence is stale or from the future');

  const repository = evidence.repository;
  invariant(repository?.ready === true && repository.head === repository.origin_main &&
    /^[0-9a-f]{40}$/.test(repository.head ?? ''), 'repository is not clean and synchronized');
  receipt(repository.preflight_sha256, 'repository preflight');

  const window = evidence.maintenance_window;
  const startsAt = instant(window?.starts_at, 'maintenance_window.starts_at');
  invariant(Number.isSafeInteger(window?.duration_minutes) &&
    window.duration_minutes >= 60, 'maintenance window is not approved or long enough');
  const endsAt = startsAt + window.duration_minutes * 60 * 1000;
  invariant(endsAt > now, 'maintenance window has already ended');
  invariant(window?.approved === true && window?.status_page_ready === true &&
    window?.customer_message_ready === true && window?.owner && window?.on_call,
  'maintenance ownership or communication is incomplete');

  const clients = evidence.clients;
  invariant(clients?.inventory_complete === true && clients?.unknown_active_versions === 0 &&
    clients?.incompatible_active_versions === 0 && Array.isArray(clients?.lanes) &&
    clients.lanes.length > 0, 'client/store adoption inventory is incomplete');
  for (const lane of clients.lanes) {
    invariant(typeof lane.name === 'string' && lane.name.length > 0,
      'client lane name is missing');
    invariant(['adopted', 'technically-read-only', 'retired'].includes(lane.disposition),
      `${lane.name} has no closed cutover disposition`);
    receipt(lane.evidence_sha256, `${lane.name} client lane`);
    fresh(lane.tested_at, `${lane.name}.tested_at`, now, MAX_CANARY_AGE_MS);
  }
  invariant(new Set(clients.lanes.map((lane) => lane.name)).size === clients.lanes.length,
    'client lanes contain duplicates');

  exactNames(evidence.freeze_controls, REQUIRED_FREEZE_LANES, 'freeze_controls');
  for (const control of evidence.freeze_controls) {
    invariant(control.rehearsed === true && control.owner, `${control.name} freeze is not rehearsed`);
    receipt(control.evidence_sha256, `${control.name} freeze`);
  }

  const infrastructure = evidence.infrastructure;
  invariant(infrastructure?.hostname === 'festapp-supabase-rehearsal-01' &&
    infrastructure?.ntp_synchronized === true && infrastructure?.database_publicly_exposed === false &&
    infrastructure?.ssh_restricted === true && infrastructure?.automatic_security_updates === true,
  'host identity or security posture is not ready');
  invariant(infrastructure?.availability_mode === 'replicated' ||
    (infrastructure?.availability_mode === 'single-node-recovery' &&
      infrastructure?.single_node_risk_accepted === true),
  'single-node availability risk has not been explicitly accepted');
  invariant(Number.isSafeInteger(infrastructure?.disk_free_bytes) && infrastructure.disk_free_bytes > 0 &&
    Number.isSafeInteger(infrastructure?.required_peak_bytes) && infrastructure.required_peak_bytes > 0 &&
    infrastructure.disk_free_bytes >= Math.ceil(infrastructure.required_peak_bytes * 1.5),
  'disk capacity does not have the required 50% headroom');
  invariant(infrastructure?.runtime_tooling_matches_repository === true &&
    infrastructure?.all_required_runtime_inputs_present === true &&
    infrastructure?.target_write_barrier_rehearsed === true,
  'runtime tooling, inputs or target write barrier is not ready');

  const backup = evidence.recovery;
  invariant(backup?.encrypted_off_host_backup === true && backup?.destination_owner &&
    backup?.destination_failure_domain !== 'festapp-supabase-rehearsal-01',
  'encrypted backup is not stored in an independent failure domain');
  receipt(backup.backup_manifest_sha256, 'backup manifest');
  receipt(backup.restore_result_sha256, 'restore result');
  fresh(backup.tested_at, 'recovery.tested_at', now, MAX_RECOVERY_PROOF_AGE_MS);
  invariant(backup?.rpo_seconds === 0 && Number.isSafeInteger(backup?.rto_seconds) &&
    backup.rto_seconds > 0 && backup.rto_seconds < window.duration_minutes * 60,
  'recovery proof does not fit the maintenance window');

  const dns = evidence.dns_tls;
  const ttlLoweredAt = instant(dns?.ttl_lowered_at, 'dns_tls.ttl_lowered_at');
  const certificateNotAfter = instant(dns?.certificate_not_after, 'dns_tls.certificate_not_after');
  invariant(Number.isSafeInteger(dns?.ttl_seconds) && dns.ttl_seconds <= 300 &&
    Number.isSafeInteger(dns?.previous_ttl_seconds) &&
    observedAt - ttlLoweredAt >= dns.previous_ttl_seconds * 1000,
  'DNS TTL was not lowered for one complete previous-TTL interval');
  invariant(certificateNotAfter >= startsAt + window.duration_minutes * 60 * 1000 + 86400000 &&
    dns?.cloudflare_only_origin_ingress === true,
  'TLS lifetime or direct-origin protection is insufficient');

  const observability = evidence.observability;
  exactNames(observability?.external_probes, REQUIRED_PROBES, 'observability.external_probes');
  for (const probe of observability.external_probes) {
    invariant(probe.status === 'pass', `${probe.name} external probe is not passing`);
    fresh(probe.tested_at, `${probe.name}.tested_at`, now, MAX_CANARY_AGE_MS);
  }
  invariant(observability?.off_host_logs === true && observability?.alert_delivery_tested === true &&
    observability?.on_call, 'off-host logs or alert delivery is not ready');
  fresh(observability.alert_tested_at, 'observability.alert_tested_at', now, MAX_CANARY_AGE_MS);

  exactNames(evidence.integrations, REQUIRED_INTEGRATIONS, 'integrations');
  for (const integration of evidence.integrations) {
    invariant(integration.status === 'pass', `${integration.name} integration is not passing`);
    fresh(integration.tested_at, `${integration.name}.tested_at`, now, MAX_CANARY_AGE_MS);
    receipt(integration.evidence_sha256, `${integration.name} integration`);
  }

  const rollback = evidence.rollback;
  invariant(rollback?.cloud_sources_retained_read_only === true &&
    rollback?.before_target_writes === 'route-to-frozen-cloud' &&
    rollback?.after_target_writes === 'restore-or-forward-repair-target-only' &&
    rollback?.cloud_deletion_authorized === false && rollback?.decision_owner &&
    Number.isSafeInteger(rollback?.retention_days) && rollback.retention_days >= 7,
  'rollback boundary is incomplete or unsafe');

  return {
    decision_version: 1,
    authorized: true,
    phase: 'pre-freeze',
    target_database: evidence.target_database,
    repository_head: repository.head,
    maintenance_window_starts_at: window.starts_at,
    maintenance_window_ends_at: new Date(endsAt).toISOString(),
    expires_at: new Date(observedAt + MAX_EVIDENCE_AGE_MS).toISOString(),
    evidence_sha256: sha256(stableJson(evidence)),
    production_mutations_performed: false,
  };
}

function argument(name) {
  const prefix = `--${name}=`;
  return process.argv.find((value) => value.startsWith(prefix))?.slice(prefix.length);
}

async function main() {
  const evidencePath = argument('evidence');
  const outputPath = argument('output');
  invariant(evidencePath && path.isAbsolute(evidencePath), '--evidence must be an absolute path');
  invariant(outputPath && path.isAbsolute(outputPath), '--output must be an absolute path');
  invariant(!fs.existsSync(outputPath), 'operational readiness output already exists');
  const evidence = JSON.parse(fs.readFileSync(evidencePath, 'utf8'));
  const result = validateOperationalReadiness(evidence);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true, mode: 0o700 });
  fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write('Operational pre-freeze readiness gate passed without production mutation.\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  });
}
