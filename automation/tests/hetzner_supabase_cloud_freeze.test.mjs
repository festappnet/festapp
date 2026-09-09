import assert from 'node:assert/strict';
import test from 'node:test';
import {
  freezeSql,
  rollbackSql,
  validateFreezeState,
} from '../hetzner-supabase/merge/manage-cloud-freeze.mjs';

test('cloud freeze SQL covers application tables plus cron', () => {
  const engage = freezeSql();
  assert.match(engage, /'public','eshop'/);
  assert.match(engage, /BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE/);
  assert.match(engage, /UPDATE cron\.job SET active=false/);
  assert.match(engage, /pg_terminate_backend/);
  assert.match(rollbackSql([2, 7]), /UPDATE cron\.job SET active=true WHERE jobid IN \(2,7\)/);
});

test('cloud freeze accepts complete guard, cron, Function and session closure', () => {
  assert.equal(validateFreezeState({
    catalogTables: 120,
    guardTriggers: 120,
    activeCronJobs: 0,
    functions: 0,
    mutatingSessions: 0,
    legacyClientStatus: 401,
    publishableKeys: 0,
    migrationKeys: 1,
  }), true);
});

for (const [field, value, message] of [
  ['guardTriggers', 119, /every source table/],
  ['activeCronJobs', 1, /cron jobs/],
  ['functions', 1, /Edge Functions/],
  ['mutatingSessions', 1, /mutating source sessions/],
  ['legacyClientStatus', 200, /legacy API keys/],
  ['publishableKeys', 1, /publishable API keys/],
  ['migrationKeys', 2, /exactly one private migration key/],
]) {
  test(`cloud freeze rejects nonzero ${field}`, () => {
    const state = {
      catalogTables: 120,
      guardTriggers: 120,
      activeCronJobs: 0,
      functions: 0,
      mutatingSessions: 0,
      legacyClientStatus: 401,
      publishableKeys: 0,
      migrationKeys: 1,
    };
    state[field] = value;
    assert.throws(() => validateFreezeState(state), message);
  });
}
