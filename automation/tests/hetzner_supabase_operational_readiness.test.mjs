import assert from 'node:assert/strict';
import test from 'node:test';
import { validateOperationalReadiness } from
  '../hetzner-supabase/runtime/validate-operational-readiness.mjs';

const now = Date.parse('2026-09-02T18:00:00Z');
const digest = 'a'.repeat(64);
const testedAt = '2026-09-02T17:55:00Z';

function fixture() {
  const named = (names, extra) => names.map((name) => ({ name, ...extra }));
  return {
    version: 1,
    target_database: 'festapp_rehearsal_20260902175500',
    observed_at: testedAt,
    repository: { ready: true, head: 'b'.repeat(40), origin_main: 'b'.repeat(40), preflight_sha256: digest },
    maintenance_window: {
      approved: true, starts_at: '2026-09-03T18:00:00Z', duration_minutes: 120,
      owner: 'operator', on_call: 'operator', status_page_ready: true, customer_message_ready: true,
    },
    clients: {
      inventory_complete: true, unknown_active_versions: 0, incompatible_active_versions: 0,
      lanes: [{ name: 'festapp-web', disposition: 'adopted', evidence_sha256: digest, tested_at: testedAt }],
    },
    freeze_controls: named(
      ['application', 'auth-refresh', 'cron', 'edge-functions', 'manual', 'storage', 'webhooks'],
      { rehearsed: true, owner: 'operator', evidence_sha256: digest },
    ),
    infrastructure: {
      hostname: 'festapp-supabase-rehearsal-01', ntp_synchronized: true,
      database_publicly_exposed: false, ssh_restricted: true, automatic_security_updates: true,
      availability_mode: 'single-node-recovery', single_node_risk_accepted: true,
      disk_free_bytes: 30_000, required_peak_bytes: 20_000,
      runtime_tooling_matches_repository: true, all_required_runtime_inputs_present: true,
      target_write_barrier_rehearsed: true,
    },
    recovery: {
      encrypted_off_host_backup: true, destination_owner: 'backup-owner',
      destination_failure_domain: 'independent-object-storage', backup_manifest_sha256: digest,
      restore_result_sha256: digest, tested_at: testedAt, rpo_seconds: 0, rto_seconds: 790,
    },
    dns_tls: {
      ttl_seconds: 300, previous_ttl_seconds: 3600, ttl_lowered_at: '2026-09-02T16:00:00Z',
      certificate_not_after: '2026-11-13T01:18:23Z', cloudflare_only_origin_ingress: true,
    },
    observability: {
      external_probes: named(['auth', 'rest', 'storage', 'realtime'], { status: 'pass', tested_at: testedAt }),
      off_host_logs: true, alert_delivery_tested: true, alert_tested_at: testedAt, on_call: 'operator',
    },
    integrations: named([
      'auth-password', 'auth-oauth', 'auth-refresh', 'aws-sns', 'edge-functions',
      'onesignal', 'payment-callbacks', 'realtime', 'smtp', 'storage', 'sync-worker',
    ], { status: 'pass', tested_at: testedAt, evidence_sha256: digest }),
    rollback: {
      cloud_sources_retained_read_only: true, before_target_writes: 'route-to-frozen-cloud',
      after_target_writes: 'restore-or-forward-repair-target-only', cloud_deletion_authorized: false,
      decision_owner: 'operator', retention_days: 14,
    },
  };
}

test('operational readiness accepts a complete, fresh, recoverable cutover contract', () => {
  const result = validateOperationalReadiness(fixture(), now);
  assert.equal(result.authorized, true);
  assert.equal(result.target_database, 'festapp_rehearsal_20260902175500');
  assert.equal(result.maintenance_window_ends_at, '2026-09-03T20:00:00.000Z');
  assert.equal(result.expires_at, '2026-09-02T18:25:00.000Z');
  assert.equal(result.production_mutations_performed, false);
});

test('operational readiness can be refreshed during but never after the approved window', () => {
  const during = fixture();
  during.observed_at = '2026-09-03T18:10:00Z';
  for (const lane of during.clients.lanes) lane.tested_at = during.observed_at;
  during.recovery.tested_at = during.observed_at;
  for (const probe of during.observability.external_probes) probe.tested_at = during.observed_at;
  during.observability.alert_tested_at = during.observed_at;
  for (const integration of during.integrations) integration.tested_at = during.observed_at;
  assert.equal(validateOperationalReadiness(
    during, Date.parse('2026-09-03T18:15:00Z'),
  ).authorized, true);

  const ended = fixture();
  ended.observed_at = '2026-09-03T19:55:00Z';
  for (const lane of ended.clients.lanes) lane.tested_at = ended.observed_at;
  ended.recovery.tested_at = ended.observed_at;
  for (const probe of ended.observability.external_probes) probe.tested_at = ended.observed_at;
  ended.observability.alert_tested_at = ended.observed_at;
  for (const integration of ended.integrations) integration.tested_at = ended.observed_at;
  assert.throws(() => validateOperationalReadiness(
    ended, Date.parse('2026-09-03T20:00:00Z'),
  ), /maintenance window has already ended/);
});

test('operational readiness rejects missing monitoring, backup independence and DNS settling', () => {
  const missingProbe = fixture();
  missingProbe.observability.external_probes.pop();
  assert.throws(() => validateOperationalReadiness(missingProbe, now), /external_probes/);

  const sameHostBackup = fixture();
  sameHostBackup.recovery.destination_failure_domain = 'festapp-supabase-rehearsal-01';
  assert.throws(() => validateOperationalReadiness(sameHostBackup, now), /independent failure domain/);

  const unsettledDns = fixture();
  unsettledDns.dns_tls.ttl_lowered_at = '2026-09-02T17:59:00Z';
  assert.throws(() => validateOperationalReadiness(unsettledDns, now), /complete previous-TTL/);
});

test('operational readiness rejects incomplete clients, stale integrations and unsafe rollback', () => {
  const client = fixture();
  client.clients.incompatible_active_versions = 1;
  assert.throws(() => validateOperationalReadiness(client, now), /client\/store/);

  const integration = fixture();
  integration.integrations[0].tested_at = '2026-08-30T00:00:00Z';
  assert.throws(() => validateOperationalReadiness(integration, now), /tested_at is stale/);

  const rollback = fixture();
  rollback.rollback.after_target_writes = 'reopen-cloud';
  assert.throws(() => validateOperationalReadiness(rollback, now), /rollback boundary/);
});
