import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import pg from 'pg';
import { randomUUID } from 'node:crypto';

const repositoryFile = (relativePath) => new URL(`../../../${relativePath}`, import.meta.url);

const databaseUrl = process.env.DATABASE_URL;
const enabled = Boolean(databaseUrl);
function assertDisposable() {
  const url = new URL(databaseUrl);
  assert.ok(['127.0.0.1', 'localhost'].includes(url.hostname) && url.port === '56922',
    'Concurrency tests require the dedicated disposable database on localhost:56922');
}
async function connect() {
  const client = new pg.Client({ connectionString: databaseUrl });
  await client.connect();
  await client.query("SET statement_timeout='20s'; SET lock_timeout='15s'; SET request.jwt.claim.role='service_role'; SET festapp.email_wake='scheduled'");
  return client;
}
const successful = (result) => Number(result.data?.code ?? result.code) === 200;

// Collect only FK descendants of the synthetic tenant and its bank account.
// Replica mode is local to the cleanup transaction and permits deleting cycles
// (orders/participants/tickets) without altering constraints or touching baseline rows.
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
  assertDisposable();
  const control = await connect();
  let fixture;
  try {
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
      assert.equal(Number((await control.query("SELECT count(*) n FROM eshop.order_participants WHERE form_id IN(SELECT id FROM forms WHERE occasion=$1) AND lifecycle='admitted'", [fixture.occasion])).rows[0].n), 1);
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
      const person = (await control.query('SELECT participant_id FROM eshop.waitlist_offer_slots WHERE offer_id=$1', [offer.id])).rows[0].participant_id;
      const details = (await control.query('SELECT pg_temp.checkout($1::jsonb,$2::uuid[]) result', [fixture, [person]])).rows[0].result;
      const accept = commandJob('accept', { offerId: offer.id, personIds: [person], orderDetails: details }, fixture.actor);
      const other = scenario !== 'accept versus expiry'
        ? commandJob('cancel', { offerId: offer.id, personIds: [person] }, fixture.actor)
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

test('canonical migration backfill counts distinct people and blocks ambiguous activation', { skip: !enabled }, async () => {
  await withFixture(null, async (control, fixture) => {
    await withFixture(null, async (_otherControl, otherFixture) => {
    const result = (await control.query('SELECT public.create_ticket_order_internal_v1(pg_temp.checkout($1::jsonb)) result', [fixture])).rows[0].result;
    assert.ok(successful(result));
    const original = (await control.query('SELECT order_symbol,order_sequence,price,data FROM eshop.orders WHERE id=$1', [result.order.id])).rows[0];
    const ticket = (await control.query('SELECT ticket FROM eshop.order_product_ticket WHERE "order"=$1 LIMIT 1', [result.order.id])).rows[0].ticket;
    const extra = (await control.query("INSERT INTO eshop.products(product_type,occasion,title,price,currency_code) VALUES($1,$2,'Legacy second product',100,'CZK') RETURNING id", [fixture.type, fixture.occasion])).rows[0].id;
    await control.query('INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES($1,$2,$3)', [result.order.id, ticket, extra]);
    await control.query('DELETE FROM eshop.order_participants WHERE form_id=$1', [fixture.form]);
    const schema = await fs.readFile(repositoryFile('database/functions/eshop_waitlist/schema.sql'), 'utf8');
    const statements = schema.slice(schema.indexOf('INSERT INTO eshop.order_participants'), schema.indexOf('DO $$ DECLARE n text;')).split(';').map((sql) => sql.trim()).filter(Boolean);
    // Make every operational backfill INSERT eligible in another tenant: one
    // clear ticket, one ticket shared by two orders, and an orphan order.
    const otherRegular = (await control.query('SELECT public.create_ticket_order_internal_v1(pg_temp.checkout($1::jsonb)) result', [otherFixture])).rows[0].result;
    assert.ok(successful(otherRegular));
    const otherClear = (await control.query('SELECT public.create_ticket_order_internal_v1(pg_temp.checkout($1::jsonb)) result', [otherFixture])).rows[0].result;
    assert.ok(successful(otherClear));
    const otherTicket = (await control.query('SELECT ticket FROM eshop.order_product_ticket WHERE "order"=$1 LIMIT 1', [otherRegular.order.id])).rows[0].ticket;
    const otherDuplicate = (await control.query('SELECT public.allocate_ticket_order_identity_internal($1) id', [otherFixture.form])).rows[0].id;
    await control.query('INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES($1,$2,$3)', [otherDuplicate, otherTicket, otherFixture.product]);
    await control.query('SELECT public.allocate_ticket_order_identity_internal($1)', [otherFixture.form]);
    await control.query('DELETE FROM eshop.order_participants WHERE form_id=$1', [otherFixture.form]);
    const runScopedBackfill = async (form) => {
      for (const sql of statements) await control.query(sql.replace('WHERE o.form IS NOT NULL', 'WHERE o.form=$1'), [form]);
    };
    const unchangedTenant = async (form) => {
      assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.order_participants WHERE form_id=$1', [form])).rows[0].n), 0, 'out-of-scope participant rows untouched');
      assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.form_participant_backfill_issues WHERE form_id=$1', [form])).rows[0].n), 0, 'out-of-scope ambiguity rows untouched');
    };
    await control.query("SELECT set_config('festapp.waitlist_backfill_organization','',false)");
    await runScopedBackfill(fixture.form);
    await runScopedBackfill(otherFixture.form);
    await unchangedTenant(fixture.form);
    await unchangedTenant(otherFixture.form);
    await control.query("SELECT set_config('festapp.waitlist_backfill_organization',$1,false)", [String(fixture.organization)]);
    // Even when the test's form predicate explicitly selects the other tenant,
    // the canonical organization guard must keep all three statements inert.
    await runScopedBackfill(otherFixture.form);
    await unchangedTenant(otherFixture.form);
    // Execute the canonical queries for the explicitly selected tenant.

    for (const sql of statements) await control.query(sql.replace('WHERE o.form IS NOT NULL', 'WHERE o.form=$1'), [fixture.form]);
    assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.order_participants WHERE current_order_id=$1', [result.order.id])).rows[0].n), 1, 'two product rows are one person');
    assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.form_participant_backfill_issues WHERE form_id=$1', [fixture.form])).rows[0].n), 0, 'clear linkage not quarantined');
    assert.deepEqual((await control.query('SELECT order_symbol,order_sequence,price,data FROM eshop.orders WHERE id=$1', [result.order.id])).rows[0], original, 'backfill preserves historical identity and data');
    const ambiguous = (await control.query('SELECT public.allocate_ticket_order_identity_internal($1) id', [fixture.form])).rows[0].id;
    for (const sql of statements.slice(1)) await control.query(sql.replace('WHERE o.form IS NOT NULL', 'WHERE o.form=$1'), [fixture.form]);
    assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.form_participant_backfill_issues WHERE order_id=$1', [ambiguous])).rows[0].n), 1, 'ambiguous order explicitly quarantined');
    await assert.rejects(control.query('SELECT public.check_form_capacity_settings_internal($1,$2)', [fixture.form, { participant_capacity: 2 }]), /PARTICIPANT_BACKFILL_REQUIRED/);
    });
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
