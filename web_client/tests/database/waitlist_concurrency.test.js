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

async function race(control, fixture, jobs) {
  const writers = await Promise.all(jobs.map(() => connect()));
  let pending = [];
  try {
    await control.query('BEGIN');
    await control.query('SELECT 1 FROM forms WHERE occasion=$1 ORDER BY id FOR UPDATE', [fixture.occasion]);
    pending = writers.map(async (writer, index) => {
      await writer.query('BEGIN');
      try {
        const result = (await writer.query(jobs[index].sql, jobs[index].params)).rows[0].result;
        await writer.query('COMMIT');
        return result;
      } catch (error) {
        await writer.query('ROLLBACK');
        throw error;
      }
    });
    // Prove both are actual concurrent server sessions waiting on the lock.
    const backendPids = writers.map((writer) => writer.processID);
    const deadline = Date.now() + 5000;
    let waiting = 0;
    while (Date.now() < deadline) {
      await control.query('SELECT pg_stat_clear_snapshot()');
      waiting = Number((await control.query("SELECT count(*) n FROM pg_stat_activity WHERE pid=ANY($1::int[]) AND wait_event_type='Lock'", [backendPids])).rows[0].n);
      if (waiting === 2) break;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.equal(waiting, 2, 'two concurrent connections must wait on the same fixture lock');
    await control.query('COMMIT');
    return await Promise.all(pending);
  } finally {
    await control.query('ROLLBACK').catch(() => {});
    await Promise.allSettled(pending);
    await Promise.all(writers.map((writer) => writer.end()));
  }
}
const checkoutJob = (input) => ({ sql: 'SELECT public.create_ticket_order_internal_v1($1::jsonb) result', params: [input] });
const commandJob = (operation, payload, actor) => ({
  sql: 'SELECT public.execute_waitlist_command_client_sync_v1($1,$2::jsonb,$3::uuid,$4::uuid,$5::uuid) result',
  params: [operation, payload, randomUUID(), randomUUID(), actor],
});

for (const scenario of ['last person', 'shared product across forms', 'shared inventory pool']) {
  test(`real multi-connection ${scenario}`, { skip: !enabled }, async () => {
    await withFixture(1, async (control, fixture) => {
      const first = (await control.query('SELECT pg_temp.checkout($1::jsonb) input', [fixture])).rows[0].input;
      let second = structuredClone(first);
      if (scenario !== 'last person') {
        const form = (await control.query("INSERT INTO forms(occasion,link,participant_capacity) VALUES($1,$2,1) RETURNING id,key", [fixture.occasion, randomUUID()])).rows[0];
        await control.query("INSERT INTO form_fields(form,product_type,type) VALUES($1,$2,'product_type')", [form.id, fixture.type]);
        second.form = form.key;
        if (scenario === 'shared product across forms') {
          await control.query('UPDATE eshop.products SET maximum=1 WHERE id=$1', [fixture.product]);
        } else {
          const other = (await control.query("INSERT INTO eshop.products(product_type,occasion,title,price,currency_code) VALUES($1,$2,'Other admission',100,'CZK') RETURNING id", [fixture.type, fixture.occasion])).rows[0];
          second.ticket[0].fields[0].product_type = Number(other.id);
          const pool = (await control.query("INSERT INTO inventory_pools(occasion,title,sellable_capacity) VALUES($1,'Single place pool',1) RETURNING id", [fixture.occasion])).rows[0];
          const context = (await control.query('INSERT INTO inventory_contexts(inventory_pool) VALUES($1) RETURNING id', [pool.id])).rows[0];
          await control.query('INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES($1,$3,1),($2,$3,1)', [fixture.product, other.id, context.id]);
          await control.query('INSERT INTO eshop.spots(occasion,inventory_context) VALUES($1,$2)', [fixture.occasion, context.id]);
        }
      }
      const results = await race(control, fixture, [checkoutJob(first), checkoutJob(second)]);
      assert.equal(results.filter(successful).length, 1, JSON.stringify(results));
      assert.equal(Number((await control.query("SELECT count(*) n FROM pg_temp.ticket_rows WHERE form_id IN(SELECT id FROM forms WHERE occasion=$1) AND lifecycle='admitted'", [fixture.occasion])).rows[0].n), 1);
      if (scenario === 'shared inventory pool') {
        assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.spots WHERE occasion=$1 AND order_product_ticket IS NOT NULL', [fixture.occasion])).rows[0].n), 1);
      }
    });
  });
}

for (const scenario of ['accept versus cancel', 'cancel versus accept', 'accept versus expiry']) {
  test(`real multi-connection ${scenario}`, { skip: !enabled }, async () => {
    await withFixture(1, async (control, fixture) => {
      const regular = (await control.query('SELECT public.create_ticket_order_internal_v1(pg_temp.checkout($1::jsonb)) result', [fixture])).rows[0].result;
      const source = Number((await control.query('SELECT pg_temp.register($1::jsonb,1) result', [fixture])).rows[0].result.order);
      await control.query('SELECT public.update_order_and_tickets_to_storno_221($1)', [regular.order.id]);
      const offer = (await control.query('SELECT pg_temp.offer($1::jsonb,$2,1) result', [fixture, source])).rows[0].result;
      const person = (await control.query('SELECT ticket_id FROM eshop.waitlist_offer_slots WHERE offer_id=$1', [offer.id])).rows[0].ticket_id;
      const details = (await control.query('SELECT pg_temp.checkout($1::jsonb,$2::bigint[]) result', [fixture, [person]])).rows[0].result;
      const accept = commandJob('accept', { offerId: offer.id, ticketIds: [person], orderDetails: details }, fixture.actor);
      const other = scenario !== 'accept versus expiry'
        ? commandJob('cancel', { offerId: offer.id, ticketIds: [person] }, fixture.actor)
        : { sql: 'SELECT public.expire_waitlist_offers(100) result', params: [] };
      if (scenario === 'accept versus expiry') await control.query("UPDATE eshop.waitlist_offers SET created_at=now()-interval '2 hours',expires_at=clock_timestamp()-interval '1 second' WHERE id=$1", [offer.id]);
      const results = await race(control, fixture, scenario === 'cancel versus accept' ? [other, accept] : [accept, other]);
      if (scenario !== 'accept versus expiry') assert.equal(results.filter(successful).length, 1, JSON.stringify(results));
      else assert.ok(!successful(results[0]), 'expired acceptance must fail even after waiting on lock');
      const snapshot = (await control.query('SELECT public.get_form_capacity_snapshot_internal($1) result', [fixture.form])).rows[0].result;
      assert.ok(snapshot.occupiedPeople + snapshot.offeredPlaces <= 1, JSON.stringify(snapshot));
      const slot = (await control.query('SELECT outcome FROM eshop.waitlist_offer_slots WHERE offer_id=$1', [offer.id])).rows[0];
      assert.ok(['accepted', 'cancelled', 'expired'].includes(slot.outcome), JSON.stringify(slot));
    });
  });
}

test('legacy tickets count immediately without backfill and duplicate products count once', { skip: !enabled }, async () => {
  await withFixture(null, async (control, fixture) => {
    const source = (await control.query('SELECT public.allocate_ticket_order_identity_internal($1) id', [fixture.form])).rows[0].id;
    const ticket = (await control.query("INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES($1,'ordered',$2) RETURNING id", [fixture.occasion, `LEGACY${randomUUID()}`])).rows[0].id;
    const extra = (await control.query("INSERT INTO eshop.products(product_type,occasion,title,price,currency_code) VALUES($1,$2,'Legacy second product',100,'CZK') RETURNING id", [fixture.type, fixture.occasion])).rows[0].id;
    await control.query('INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES($1,$2,$3),($1,$2,$4)', [source,ticket,fixture.product,extra]);
    const original = (await control.query('SELECT * FROM eshop.tickets WHERE id=$1', [ticket])).rows[0];
    assert.deepEqual(original.data, {}, 'preexisting ticket needs no fabricated answers');
    await control.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [fixture.actor]);
    const configured = (await control.query('SELECT public.update_form_internal_v1($1::jsonb) result', [{id:fixture.form,occasion:fixture.occasion,link:fixture.link,participant_capacity:1}])).rows[0].result;
    assert.equal(Number(configured.code),200,JSON.stringify(configured));
    const snapshot = (await control.query('SELECT public.get_form_capacity_snapshot_internal($1) result',[fixture.form])).rows[0].result;
    assert.equal(snapshot.occupiedPeople,1,'actual legacy ticket occupies one place for two product rows');
    assert.equal(snapshot.remainingPublic,0);
    assert.deepEqual((await control.query('SELECT * FROM eshop.tickets WHERE id=$1',[ticket])).rows[0],original,'capacity activation never rewrites legacy tickets');
    assert.equal((await control.query("SELECT to_regclass('eshop.order_participants') ledger,to_regclass('eshop.form_participant_backfill_issues') backfill")).rows[0].ledger,null);
    await control.query('SELECT public.update_order_and_tickets_to_storno_221($1)',[source]);
    assert.equal((await control.query('SELECT public.get_form_capacity_snapshot_internal($1) result',[fixture.form])).rows[0].result.occupiedPeople,0,'regular ticket cancellation is direct occupancy truth');
  });
});

test('canonical template seed is idempotent and preserves tenant custom content', { skip: !enabled }, async () => {
  await withFixture(null, async (control, fixture) => {
    const custom = (await control.query("INSERT INTO email_templates(code,organization,subject,html) VALUES('waitlist_offer',$1,'Custom subject','Custom body') RETURNING id", [fixture.organization])).rows[0].id;
    const seed = await fs.readFile(repositoryFile('database/functions/eshop_waitlist/email_templates.sql'), 'utf8');
    const countDefaults = async () => (await control.query("SELECT code,count(*) n FROM email_templates WHERE code IN('waitlist_confirmation','waitlist_offer') AND organization IS NULL AND unit IS NULL AND occasion IS NULL GROUP BY code ORDER BY code")).rows;
    const before = await countDefaults();
    await control.query(seed);
    await control.query(seed);
    assert.deepEqual(await countDefaults(), before, 'seed rerun does not duplicate global defaults');
    assert.deepEqual((await control.query('SELECT subject,html FROM email_templates WHERE id=$1', [custom])).rows[0], { subject: 'Custom subject', html: 'Custom body' });
    assert.equal((await control.query("SELECT public.get_email_template_and_wrapper('waitlist_offer',jsonb_build_object('occasion',$1::bigint)) result", [fixture.occasion])).rows[0].result.template.id, Number(custom));
  });
});

for (const deletionFirst of [true, false]) {
  test(`admin deletion versus partial acceptance (${deletionFirst ? 'delete' : 'accept'} queued first)`, { skip: !enabled }, async () => {
    await withFixture(1, async (control, fixture) => {
      await control.query('INSERT INTO unit_users(unit,"user",is_manager) VALUES($1,$2,true)', [fixture.unit, fixture.actor]);
      const filled = (await control.query('SELECT public.create_ticket_order_internal_v1(pg_temp.checkout($1::jsonb)) result', [fixture])).rows[0].result;
      assert.ok(successful(filled));
      const source = Number((await control.query('SELECT pg_temp.register($1::jsonb,2) result', [fixture])).rows[0].result.order);
      await control.query('SELECT public.update_order_and_tickets_to_storno_221($1)', [filled.order.id]);
      const offer = (await control.query('SELECT pg_temp.offer($1::jsonb,$2,1) result', [fixture, source])).rows[0].result;
      const tickets = (await control.query('SELECT pg_temp.ticket_ids($1) ids', [source])).rows[0].ids.map(Number);
      const checkout = (await control.query('SELECT pg_temp.checkout($1::jsonb,$2::bigint[]) input', [fixture, [tickets[1]]])).rows[0].input;
      const acceptance = commandJob('accept', { offerId: offer.id, ticketIds: [tickets[1]], orderDetails: checkout }, fixture.actor);
      const deletion = {
        sql: `WITH actor AS MATERIALIZED (SELECT set_config('request.jwt.claim.sub',$1,true))
          SELECT public.delete_order_client_sync_v1($2,$3::uuid) result FROM actor`,
        params: [fixture.actor, source, randomUUID()],
      };
      const jobs = deletionFirst ? [deletion, acceptance] : [acceptance, deletion];
      const results = await race(control, fixture, jobs);
      assert.ok(successful(results[deletionFirst ? 0 : 1]), JSON.stringify(results));
      const accepted = results[deletionFirst ? 1 : 0];
      assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.orders WHERE id=$1', [source])).rows[0].n), 0);
      assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.waitlist_offers WHERE order_id=$1', [source])).rows[0].n), 0);
      if (successful(accepted)) {
        const child = accepted.data.order.id;
        const saved = (await control.query('SELECT state,price,source_waitlist_order_id FROM eshop.orders WHERE id=$1', [child])).rows[0];
        assert.equal(saved.source_waitlist_order_id, null);
        assert.equal(Number(saved.price), 100);
        assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.order_product_ticket WHERE "order"=$1 AND ticket=$2', [child, tickets[1]])).rows[0].n), 1);
      } else {
        assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.tickets WHERE id=ANY($1::bigint[])', [tickets])).rows[0].n), 0);
      }
    });
  });
}

test('tokenless admin withdrawal updates both canonical detail and order grid reads', { skip: !enabled }, async () => {
  const actor = randomUUID();
  try {
    await withFixture(1, async (control, fixture) => {
      await control.query('INSERT INTO auth.users(id,email) VALUES($1,$2)', [actor, `${actor}@example.invalid`]);
      await control.query('INSERT INTO user_info(id,email_readonly,organization) VALUES($1,$2,$3)', [actor, `${actor}@example.invalid`, fixture.organization]);
      await control.query('INSERT INTO occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES($1,$2,true,true)', [fixture.occasion, actor]);
      fixture.actor = actor;
      const filled = (await control.query('SELECT public.create_ticket_order_internal_v1(pg_temp.checkout($1::jsonb)) result', [fixture])).rows[0].result;
      assert.ok(successful(filled));
      const source = Number((await control.query('SELECT pg_temp.register($1::jsonb,2) result', [fixture])).rows[0].result.order);
      const tickets = (await control.query('SELECT pg_temp.ticket_ids($1) ids', [source])).rows[0].ids.map(Number);
      await control.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [fixture.actor]);
      const read = async () => {
        const detail = (await control.query('SELECT public.get_waitlist_order_detail($1) result', [source])).rows[0].result;
        const bundle = (await control.query('SELECT public.get_orders($1::text,NULL::text,NULL::jsonb) result', [fixture.link])).rows[0].result;
        return [detail, bundle.data.orders.find((order) => Number(order.id) === source)];
      };
      assert.equal((await read())[0].waitlistSummary.counts.waiting, 2);
      const rejected = (await control.query('SELECT public.execute_waitlist_command_client_sync_v1($1,$2::jsonb,$3::uuid,$4::uuid,$5::uuid) result',
        ['withdraw', { orderId: source, ticketIds: [-1] }, randomUUID(), randomUUID(), fixture.actor])).rows[0].result;
      assert.equal(rejected.code, 409);
      assert.equal(rejected.status, 'rejected');
      assert.equal(rejected.data.errorCode, 'INVALID_CAPABILITY');
      assert.equal((await read())[0].waitlistSummary.counts.waiting, 2, 'Rejected command must not silently resolve tickets');
      for (const [index, id] of tickets.entries()) {
        const command = randomUUID();
        const payload = { orderId: source, ticketIds: [id] }; // No public capability token.
        const result = (await control.query('SELECT public.execute_waitlist_command_client_sync_v1($1,$2::jsonb,$3::uuid,$4::uuid,$5::uuid) result',
          ['withdraw', payload, command, randomUUID(), fixture.actor])).rows[0].result;
        assert.equal(result.code, 200);
        assert.equal(result.status, 'applied');
        assert.equal(result.data.waitlistSummary.counts.withdrawn, index + 1);
        for (const row of await read()) {
          assert.equal(row.waitlistSummary.counts.withdrawn, index + 1);
          assert.equal(row.waitlistSummary.counts.waiting ?? 0, tickets.length - index - 1);
          assert.equal(row.waitlistSummary.isActive, index + 1 < tickets.length);
        }
      }
    });
  } finally {
    const cleanupActor = await connect();
    try { await cleanupActor.query('DELETE FROM auth.users WHERE id=$1', [actor]); }
    finally { await cleanupActor.end(); }
  }
});
