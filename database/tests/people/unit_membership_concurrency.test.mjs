import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import test from 'node:test';
import { assertDisposableDatabase, assertLocalDatabaseUrl } from '../../../web_client/tests/database/disposable_database.js';
const require = createRequire(new URL('../../../web_client/package.json', import.meta.url));
const { Client } = require('pg');

test('two DB connections serialize unit membership retries and deletion versus replay', { skip: !process.env.DATABASE_URL }, async () => {
  assertLocalDatabaseUrl(process.env.DATABASE_URL);
  const clients = [new Client({ connectionString: process.env.DATABASE_URL, statement_timeout: 10000 }),
    new Client({ connectionString: process.env.DATABASE_URL, statement_timeout: 10000 })];
  const [first, second] = clients;
  let org, unit;
  const users = [];
  try {
    await Promise.all(clients.map(c => c.connect()));
    await assertDisposableDatabase(first);
    ({ rows: [{ id: org }] } = await first.query("INSERT INTO public.organizations(title) VALUES('Concurrent membership fixture') RETURNING id"));
    ({ rows: [{ id: unit }] } = await first.query("INSERT INTO public.units(organization,title) VALUES($1,'Concurrent membership fixture') RETURNING id", [org]));
    for (const alias of ['actor', 'recipient']) {
      const { rows: [{ id }] } = await first.query('SELECT public.create_user_in_organization_with_data_pure($1,$2,$3,$4) id', [org, `${alias}-${randomUUID()}@example.invalid`, randomUUID(), '{}']);
      users.push(id);
    }
    const [actor, recipient] = users;
    await first.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)', [unit, actor]);
    for (const connection of clients) {
      await connection.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)", [actor]);
      await connection.query('SET ROLE authenticated');
    }
    const command = randomUUID();
    const add = (connection, id) => connection.query('SELECT public.add_user_to_unit_client_sync_v1($1,$2,$3) result', [unit, recipient, id]);
    const results = await Promise.all(clients.map(c => add(c, command)));
    assert.deepEqual(results[0].rows[0].result, results[1].rows[0].result);
    assert.equal(results[0].rows[0].result.status, 'applied');
    await first.query('BEGIN');
    await first.query('SELECT public.delete_unit_user_client_sync_v1($1,$2,$3)', [recipient, unit, randomUUID()]);
    const replay = add(second, command);
    // Confirm the second physical connection is waiting on the transaction lock.
    // This avoids claiming concurrency from two operations that ran sequentially.
    await first.query('RESET ROLE');
    let blocked = false;
    for (let attempt = 0; attempt < 50; attempt++) {
      const { rows: [{ blockers }] } = await first.query('SELECT pg_blocking_pids($1) blockers', [second.processID]);
      if (blockers.includes(first.processID)) { blocked = true; break; }
      await first.query('SELECT pg_sleep(0.02)');
    }
    assert.ok(blocked, 'second physical connection must block on the removal transaction');
    await first.query('COMMIT');
    assert.deepEqual((await replay).rows[0].result, results[0].rows[0].result);
    const { rows: [{ count }] } = await first.query('SELECT count(*) FROM public.unit_users WHERE unit=$1 AND "user"=$2', [unit, recipient]);
    assert.equal(count, '0', 'receipt replay after removal must not recreate membership');
  } finally {
    await Promise.all(clients.map(c => c.query('ROLLBACK').catch(() => {})));
    try {
    await first.query('RESET ROLE');
    if (unit) {
      await first.query('DELETE FROM public.client_mutation_receipts WHERE unit=$1', [unit]);
      await first.query('DELETE FROM public.client_commit_components WHERE commit_id IN (SELECT commit_id FROM public.client_commits WHERE unit=$1)', [unit]);
      await first.query('DELETE FROM public.client_commit_items WHERE commit_id IN (SELECT commit_id FROM public.client_commits WHERE unit=$1)', [unit]);
      await first.query('DELETE FROM public.client_commits WHERE unit=$1', [unit]);
      await first.query('DELETE FROM public.unit_users WHERE unit=$1', [unit]);
      await first.query('DELETE FROM public.units WHERE id=$1', [unit]);
      await first.query('DELETE FROM public.user_info WHERE id=ANY($1::uuid[])', [users]);
      await first.query('DELETE FROM auth.users WHERE id=ANY($1::uuid[])', [users]);
      await first.query('DELETE FROM public.organizations WHERE id=$1', [org]);
    }
    } finally { await Promise.all(clients.map(c => c.end())); }
  }
});
