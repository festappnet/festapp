import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildApplySql,
  buildDisableSql,
  buildScheduleCommand,
  buildStatusSql,
  endpointSecretName,
  scheduleName,
  tokenSecretName,
} from '../release/configure_client_sync_publisher_schedule.mjs';

test('five-second command calls HTTP only behind an indexed dirty-key EXISTS', () => {
  const sql = buildScheduleCommand([643]);
  assert.match(sql, /WHERE EXISTS[\s\S]*client_projection_dirty_keys/);
  assert.match(sql, /scope_id=ANY\(ARRAY\[643\]/);
  assert.match(sql, /claimed_at IS NULL/);
  assert.match(sql, /net\.http_post/);
  assert.ok(sql.indexOf('net.http_post') < sql.indexOf('WHERE EXISTS'));
  assert.match(sql, new RegExp(endpointSecretName));
  assert.match(sql, new RegExp(tokenSecretName));
  assert.doesNotMatch(sql, /wake-secret|service_role/i);
});

test('apply replaces only the exact named job with a five-second schedule', () => {
  const sql = buildApplySql([643]);
  assert.match(sql, new RegExp(scheduleName));
  assert.match(sql, /cron\.unschedule/);
  assert.match(sql, /cron\.schedule/);
  assert.match(sql, /'5 seconds'/);
});

test('disable and status are exact and status remains read-only', () => {
  const disabled = buildDisableSql();
  assert.match(disabled, new RegExp(scheduleName));
  assert.doesNotMatch(disabled, /DELETE|UPDATE|TRUNCATE/i);
  const status = buildStatusSql({ organization: 9, occasionLink: 'csmostrava2026', scopeIds: [643] });
  assert.match(status, /scopeMatch/);
  assert.match(status, /pg_cron/);
  assert.doesNotMatch(status, /(?:^|;)\s*(?:UPDATE|DELETE|INSERT|REVOKE)/im);
});
