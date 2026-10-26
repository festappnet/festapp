import assert from 'node:assert/strict';

export function assertLocalDatabaseUrl(databaseUrl) {
  const url = new URL(databaseUrl);
  assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname),
    'Mutation tests require a local disposable database');
}

export async function assertDisposableDatabase(client) {
  const { rows } = await client.query(
    'SELECT project FROM festapp_test_support.disposable_environment WHERE singleton');
  assert.ok(rows.length === 1 && /^festapp-/.test(rows[0].project),
    'Mutation tests require the bootstrap disposable database identity');
}
