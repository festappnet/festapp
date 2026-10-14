import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import { assertLocalDatabaseUrl, assertDisposableDatabase } from './disposable_database.js';

const repositoryFile = (relativePath) => new URL(`../../../${relativePath}`, import.meta.url);

const databaseUrl = process.env.DATABASE_URL;
const enabled = Boolean(databaseUrl);
async function connect() {
  const client = new pg.Client({ connectionString: databaseUrl });
  await client.connect();
  await client.query("SET statement_timeout='20s'; SET lock_timeout='15s'; SET request.jwt.claim.role='service_role'; SET festapp.email_wake='scheduled'");
  return client;
}
const successful = (result) => Number(result.data?.code ?? result.code) === 200;

// Collect only FK descendants of the synthetic tenant and its bank account.
// Replica mode is local to the cleanup transaction and permits deleting cycles
// (orders/tickets) without altering constraints or touching baseline rows.
async function cleanup(client, fixture) {
  await client.query('BEGIN');
  try {
    await client.query('CREATE TEMP TABLE cleanup_rows(rel oid, row_tid tid, PRIMARY KEY(rel,row_tid)) ON COMMIT DROP');
    await client.query("INSERT INTO cleanup_rows SELECT 'public.organizations'::regclass,ctid FROM public.organizations WHERE id=$1", [fixture.organization]);
    await client.query(`INSERT INTO cleanup_rows SELECT 'eshop.bank_accounts'::regclass, b.ctid FROM eshop.bank_accounts b
      JOIN eshop.unit_bank_accounts ub ON ub.bank_account=b.id WHERE ub.unit=$1 ON CONFLICT DO NOTHING`, [fixture.unit]);
    await client.query(`DO $$ DECLARE edge record; n integer; changed integer; join_clause text;
      BEGIN LOOP changed:=0;
      FOR edge IN SELECT c.*, c.conrelid::regclass child, c.confrelid::regclass parent FROM pg_constraint c
        JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace ns ON ns.oid=t.relnamespace
        WHERE c.contype='f' AND ns.nspname IN ('public','eshop') LOOP
        SELECT string_agg(format('ch.%I=pa.%I',ca.attname,paa.attname),' AND ')
        INTO join_clause FROM unnest(edge.conkey,edge.confkey) keys(child_key,parent_key)
        JOIN pg_attribute ca ON ca.attrelid=edge.conrelid AND ca.attnum=keys.child_key
        JOIN pg_attribute paa ON paa.attrelid=edge.confrelid AND paa.attnum=keys.parent_key;
        EXECUTE format('INSERT INTO cleanup_rows SELECT %s,ch.ctid FROM %s ch JOIN %s pa ON %s JOIN cleanup_rows known ON known.rel=%s AND known.row_tid=pa.ctid ON CONFLICT DO NOTHING',
          edge.conrelid,edge.child,edge.parent,join_clause,edge.confrelid);
        GET DIAGNOSTICS n=ROW_COUNT; changed:=changed+n;
      END LOOP;
      EXIT WHEN changed=0;
      END LOOP;
      END $$;
      SET LOCAL session_replication_role=replica;
      DO $$ DECLARE target record; BEGIN
      FOR target IN SELECT DISTINCT rel FROM cleanup_rows LOOP
        EXECUTE format('DELETE FROM %s target USING cleanup_rows known WHERE known.rel=%s AND target.ctid=known.row_tid',target.rel::regclass,target.rel);
      END LOOP;
      END $$;`);
    await client.query('COMMIT');
    assert.equal(Number((await client.query('SELECT count(*) n FROM organizations WHERE id=$1', [fixture.organization])).rows[0].n), 0, 'tenant cleanup');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}

async function withFixture(capacity, run) {
  assertLocalDatabaseUrl(databaseUrl);
  const control = await connect();
  let fixture;
  try {
    await assertDisposableDatabase(control);
    // Reuse transaction-local helpers from the SQL behavioral suite.
    const sql = await fs.readFile(repositoryFile('database/tests/eshop_orders/waitlist_lifecycle_test.sql'), 'utf8');
    await control.query(sql.slice(0, sql.indexOf('DO $$\nDECLARE x jsonb')));
    fixture = (await control.query('SELECT pg_temp.fixture($1) fixture', [capacity])).rows[0].fixture;
    await control.query('COMMIT');
    await run(control, fixture);
  } finally {
    await control.query('ROLLBACK').catch(() => {});
    try { if (fixture) await cleanup(control, fixture); } finally { await control.end(); }
  }
}

// Each writer uses a real independent session while the accepted target remains
// durably preparing. No transaction reset or baseline row mutation is involved.
for (const scenario of ['withdraw displaced', 'withdraw unrelated', 'edit displaced']) {
  test(`Fakturoid swap abort preserves separate-session ${scenario}`, { skip: !enabled }, async () => {
    await withFixture(1, async (control, fixture) => {
      const regular = (await control.query('SELECT public.create_ticket_order_internal_v1(pg_temp.checkout($1::jsonb)) result', [fixture])).rows[0].result;
      const source = Number((await control.query('SELECT pg_temp.register($1::jsonb,3) result', [fixture])).rows[0].result.order);
      await control.query('SELECT public.update_order_and_tickets_to_storno_221($1)', [regular.order.id]);
      const offer = (await control.query('SELECT pg_temp.offer($1::jsonb,$2,1) result', [fixture, source])).rows[0].result;
      const originalSlot = (await control.query('SELECT id,ticket_id FROM eshop.waitlist_offer_slots WHERE offer_id=$1', [offer.id])).rows[0];
      const waiting = (await control.query("SELECT id FROM pg_temp.ticket_rows WHERE current_order_id=$1 AND lifecycle='waiting' ORDER BY id", [source])).rows;
      const selected = waiting[0].id;
      const remainder = waiting[1].id;
      await control.query("INSERT INTO eshop.external_services(unit,type,data) VALUES($1,'FAKTUROID','{}')", [fixture.unit]);
      const details = (await control.query('SELECT pg_temp.checkout($1::jsonb,$2::bigint[]) result', [fixture, [selected]])).rows[0].result;
      const command = randomUUID();
      const accepted = (await control.query('SELECT public.execute_waitlist_command_client_sync_v1($1,$2::jsonb,$3::uuid,$4::uuid,$5::uuid) result',
        ['accept', { offerId: offer.id, ticketIds: [selected], orderDetails: details }, command, randomUUID(), fixture.actor])).rows[0].result;
      assert.ok(successful(accepted), JSON.stringify(accepted));
      const target = accepted.data.order.id;
      assert.equal((await control.query('SELECT state FROM eshop.orders WHERE id=$1', [target])).rows[0].state, 'preparing_payment');
      const writer = await connect();
      try {
        assert.notEqual(writer.processID, control.processID, 'independent backend sessions');
        if (scenario === 'edit displaced') {
          await writer.query("UPDATE eshop.tickets SET data='{\"edited\":true}',updated_at=clock_timestamp() WHERE id=$1", [originalSlot.ticket_id]);
        } else {
          const person = scenario === 'withdraw displaced' ? originalSlot.ticket_id : remainder;
          const withdrawal = (await writer.query('SELECT public.execute_waitlist_command_client_sync_v1($1,$2::jsonb,$3::uuid,$4::uuid,$5::uuid) result',
            ['withdraw', { orderId: source, ticketIds: [person] }, randomUUID(), randomUUID(), fixture.actor])).rows[0].result;
          assert.ok(successful(withdrawal), JSON.stringify(withdrawal));
        }
      } finally { await writer.end(); }
      await control.query('SELECT public.abort_fakturoid_ticket_order_v1($1,$2::uuid)', [target, command]);
      const slot = (await control.query('SELECT ticket_id,outcome FROM eshop.waitlist_offer_slots WHERE id=$1', [originalSlot.id])).rows[0];
      assert.equal(slot.ticket_id, originalSlot.ticket_id, 'original binding restored');
      assert.equal(slot.outcome, scenario === 'withdraw displaced' ? 'cancelled' : 'pending');
      assert.equal((await control.query('SELECT public.get_effective_waitlist_ticket_lifecycle_internal($1) lifecycle', [selected])).rows[0].lifecycle, 'waiting');
      if (scenario === 'edit displaced') {
        assert.deepEqual((await control.query('SELECT data answers FROM eshop.tickets WHERE id=$1', [originalSlot.ticket_id])).rows[0].answers, { edited: true });
      } else {
        const person = scenario === 'withdraw displaced' ? originalSlot.ticket_id : remainder;
        assert.equal((await control.query('SELECT public.get_effective_waitlist_ticket_lifecycle_internal($1) lifecycle', [person])).rows[0].lifecycle, 'withdrawn');
      }
    });
  });
}
