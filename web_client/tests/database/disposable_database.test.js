import test from 'node:test';
import assert from 'node:assert/strict';
import { assertLocalDatabaseUrl, assertDisposableDatabase } from './disposable_database.js';

test('mutation tests reject remote hosts and require the bootstrap marker', async () => {
  assert.throws(() => assertLocalDatabaseUrl('postgresql://localhost.example.invalid:55432/postgres'));
  assert.throws(() => assertLocalDatabaseUrl('postgresql://db.festapp.net/postgres'));
  assertLocalDatabaseUrl('postgresql://127.0.0.1:55446/postgres');
  assertLocalDatabaseUrl('postgresql://[::1]:55446/postgres');
  for (const rows of [[], [{ project: 'production' }], [{ project: 'festapp-tests' }, { project: 'festapp-other' }]]) {
    await assert.rejects(assertDisposableDatabase({ query: async () => ({ rows }) }));
  }
  await assertDisposableDatabase({ query: async () => ({ rows: [{ project: 'festapp-db-tests-pg15' }] }) });
});
