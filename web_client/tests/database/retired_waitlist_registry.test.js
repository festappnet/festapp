import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import pg from 'pg';
import {assertLocalDatabaseUrl, assertDisposableDatabase} from './disposable_database.js';
const source = fs.readFileSync(new URL('../../../database/functions/eshop_waitlist/retired_registry.sql', import.meta.url), 'utf8');
const migration = fs.readFileSync(new URL('../../../supabase/migrations/20261109180000_retired_waitlist_registry.sql', import.meta.url), 'utf8');
test('forward registry repair matches its canonical source', () => assert.equal(migration,source));
test('actual forward repair removes retired slot identity and preserves live and unrelated registrations', async () => {
  assert.ok(process.env.DATABASE_URL, 'A disposable SQL runtime is required');
  assertLocalDatabaseUrl(process.env.DATABASE_URL);
  const db = new pg.Client({connectionString:process.env.DATABASE_URL});
  await db.connect();
  try {
    await assertDisposableDatabase(db);
    await db.query('BEGIN');
    await db.query('CREATE TEMP TABLE retired_slots(id bigint); CREATE TEMP TABLE unrelated_slots(id bigint)');
    const old = (await db.query("SELECT 'pg_temp.retired_slots'::regclass::oid id")).rows[0].id;
    await db.query(`INSERT INTO public.client_sync_component_sources
      (registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready)
      VALUES(1,'private_inventory',$1,'form -> forms.occasion',ARRAY['offer_id','participant_id','outcome','resulting_order_id'],ARRAY['execute_waitlist_command_client_sync_v1'],ARRAY[]::text[],'migrate','waitlist_slot_factory',false),
      (1,'private_inventory','pg_temp.unrelated_slots'::regclass,'unrelated',ARRAY['participant_id'],ARRAY['execute_waitlist_command_client_sync_v1'],ARRAY[]::text[],'migrate','unrelated_factory',false)`,[old]);
    await db.query('DROP TABLE pg_temp.retired_slots');
    const before = (await db.query('SELECT to_jsonb(t) row FROM client_sync_component_sources t WHERE source_relation<>$1 ORDER BY to_jsonb(t)::text',[old])).rows;
    const live = await db.query("SELECT * FROM client_sync_component_sources WHERE source_relation='eshop.waitlist_offer_slots'::regclass");
    assert.ok(live.rowCount > 0,'a populated live ticket-based source is required');
    await db.query(migration);
    assert.equal((await db.query('SELECT 1 FROM client_sync_component_sources WHERE source_relation=$1',[old])).rowCount,0);
    assert.deepEqual((await db.query('SELECT to_jsonb(t) row FROM client_sync_component_sources t ORDER BY to_jsonb(t)::text')).rows,before);
    await db.query(migration);
    assert.deepEqual((await db.query('SELECT to_jsonb(t) row FROM client_sync_component_sources t ORDER BY to_jsonb(t)::text')).rows,before);
  } finally {await db.query('ROLLBACK');await db.end();}
});
