// Existing pg harness pattern: synthetic fixtures in an explicitly disposable
// loopback DB. This exercises real transactions, canonical SQL and RPC replay.
import pg from 'pg';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const url = process.env.DATABASE_URL;
if (!url || !['127.0.0.1', 'localhost'].includes(new URL(url).hostname) || process.env.FESTAPP_DISPOSABLE_ORDER_DB !== 'yes') throw new Error('Disposable loopback database required');
const clients = [0, 1, 2].map(() => new pg.Client({ connectionString: url }));
const [db, a, b] = clients;
await Promise.all(clients.map(c => c.connect()));
const root = new URL('../../', import.meta.url);
const source = p => fs.readFileSync(new URL(p, root), 'utf8').replace(/^BEGIN;\n|^COMMIT;$/gm, '');
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
try {
  await Promise.all(clients.map(c => c.query("SET lock_timeout='10s'; SET statement_timeout='20s'")));
  // Backfill interrupted/rerun, all legacy shapes, collisions, metadata preserved.
  await db.query('BEGIN');
  await db.query('ALTER TABLE eshop.orders ALTER COLUMN order_symbol DROP NOT NULL');
  await db.query(source('automation/order-symbol/backfill-function.sql'));
  const saved = (await one("SELECT pg_get_functiondef('public.generate_order_symbol()'::regprocedure) def")).def;
  await db.query(saved.replace('public.generate_order_symbol()', 'pg_temp.real_order_symbol()'));
  await db.query('CREATE TEMP SEQUENCE symbol_attempt');
  await db.query('GRANT USAGE, SELECT ON SEQUENCE pg_temp.symbol_attempt TO postgres');
  await db.query("CREATE OR REPLACE FUNCTION public.generate_order_symbol() RETURNS text LANGUAGE sql VOLATILE SET search_path=public,extensions AS $$ SELECT CASE WHEN nextval('pg_temp.symbol_attempt')=1 THEN '7G4K9M2R6A' ELSE pg_temp.real_order_symbol() END $$");
  const stable = await one("INSERT INTO eshop.orders(order_sequence,order_symbol,state,data,price) VALUES(1,'7G4K9M2R6A','paid','{}',100) RETURNING id");
  const legacy = (await db.query(`INSERT INTO eshop.orders(order_sequence,state,data,price,created_at,updated_at)
    SELECT 1, state, data, price, '2020-01-01'::timestamptz, '2020-01-02'::timestamptz
    FROM (VALUES ('ordered','{}'::jsonb,10),('paid','{"tickets":[]}'::jsonb,100),('sent',null,0),('storno','{"old":true}'::jsonb,0),('ordered','{}'::jsonb,0)) x(state,data,price)
    RETURNING id,to_jsonb(orders)-'order_symbol' AS original`)).rows;
  const first = legacy.slice(0, 2).map(r => r.id);
  const batch = (await db.query('SELECT * FROM public.backfill_order_symbols($1)', [first])).rows;
  assert.equal(batch.length, 2);
  assert.equal((await db.query('SELECT * FROM public.backfill_order_symbols($1)', [first])).rowCount, 0);
  await db.query('SELECT * FROM public.backfill_order_symbols($1)', [legacy.map(r => r.id)]);
  for (const old of legacy) {
    const row = await one("SELECT order_symbol,to_jsonb(o)-'order_symbol' AS actual FROM eshop.orders o WHERE id=$1", [old.id]);
    assert.deepEqual(row.actual, old.original);
    assert.match(row.order_symbol, /^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$/);
  }
  assert.equal((await one('SELECT order_symbol FROM eshop.orders WHERE id=$1', [stable.id])).order_symbol, '7G4K9M2R6A');
  await db.query(source('supabase/migrations/20261006130000_order_symbol_expand.sql'));
  await db.query(source('supabase/migrations/20261006130000_order_symbol_expand.sql'));
  await db.query(source('supabase/migrations/20261006131000_order_symbol_contract.sql'));
  await db.query(source('supabase/migrations/20261006131000_order_symbol_contract.sql'));
  assert.equal((await one('SELECT order_symbol FROM eshop.orders WHERE id=$1', [stable.id])).order_symbol, '7G4K9M2R6A');
  await db.query('ROLLBACK');

  // The canonical writer retries only its symbol insert. Fixture has real products.
  await db.query('BEGIN');
  await db.query(source('database/tests/helpers/assertions.sql'));
  const org = (await one("INSERT INTO public.organizations(title) VALUES('Symbol command fixture') RETURNING id")).id;
  const unit = (await one("INSERT INTO public.units(title,organization) VALUES('Unit',$1) RETURNING id", [org])).id;
  const occasion = (await one("INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time) VALUES('Occasion',$1,$2,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id", [unit, org])).id;
  const secret = (await one("INSERT INTO eshop.secrets(secret) VALUES(gen_random_uuid()::text) RETURNING id")).id;
  const account = (await one("INSERT INTO eshop.bank_accounts(title,supported_currencies,secret,type) VALUES('Account',ARRAY['CZK'],$1,'FIO') RETURNING id", [secret])).id;
  await db.query('INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES($1,$2,1)', [unit, account]);
  const form = await one("INSERT INTO public.forms(title,occasion,is_open) VALUES('Form',$1,true) RETURNING id,key", [occasion]);
  const type = (await one("INSERT INTO eshop.product_types(title,occasion,type) VALUES('Ticket',$1,'spot') RETURNING id", [occasion])).id;
  const product = (await one("INSERT INTO eshop.products(title,occasion,product_type,price,currency_code,is_hidden) VALUES('Product',$1,$2,100,'CZK',false) RETURNING id", [occasion, type])).id;
  await db.query('INSERT INTO public.form_fields(form,product_type) VALUES($1,$2)', [form.id, type]);
  const input = { form: form.key, email: 'fixture@example.invalid', ticket: [{ fields: [{ product_type: product }] }] };
  const command = crypto.randomUUID(), client = crypto.randomUUID();
  const invoke = async () => (await one('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) r', [input, command, client])).r;
  const response = await invoke();
  assert.equal(response.code, 200, JSON.stringify(response));
  const order = response.data.order;
  assert.match(order.order_symbol, /^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$/);
  const counts = await one('SELECT (SELECT count(*) FROM eshop.orders WHERE occasion=$1)::int orders,(SELECT count(*) FROM public.email_messages WHERE order_id=$2)::int emails,(SELECT count(*) FROM eshop.payment_info WHERE id=$3)::int payments', [occasion, order.id, order.payment_info.id]);
  assert.deepEqual((await invoke()).data.order, order);
  assert.deepEqual(await one('SELECT (SELECT count(*) FROM eshop.orders WHERE occasion=$1)::int orders,(SELECT count(*) FROM public.email_messages WHERE order_id=$2)::int emails,(SELECT count(*) FROM eshop.payment_info WHERE id=$3)::int payments', [occasion, order.id, order.payment_info.id]), counts);
  // Retained legacy command response: only returned metadata is enriched.
  const table = (await one("SELECT table_name FROM information_schema.columns WHERE column_name='response' AND table_name LIKE '%mutation%' LIMIT 1")).table_name;
  assert.ok(table, 'mutation response table');
  await db.query(`UPDATE public.${table} SET response=response #- '{data,order,order_symbol}' WHERE command_id=$1`, [command]);
  const oldStored = await one(`SELECT response FROM public.${table} WHERE command_id=$1`, [command]);
  assert.equal((await invoke()).data.order.order_symbol, order.order_symbol);
  assert.deepEqual(await one(`SELECT response FROM public.${table} WHERE command_id=$1`, [command]), oldStored);
  for (const spoof of [{ ...input, order_symbol: '8A8C8E8F8G' }, { ...input, data: { orderSymbol: '8A8C8E8F8G' } }]) {
    const r = (await one('SELECT public.create_ticket_order_internal_v1($1) r', [spoof])).r;
    assert.equal(r.code, 1001);
  }
  await db.query(saved.replace('public.generate_order_symbol()', 'pg_temp.real_order_symbol()'));
  await db.query('CREATE TEMP SEQUENCE symbol_attempt');
  await db.query('GRANT USAGE, SELECT ON SEQUENCE pg_temp.symbol_attempt TO postgres');
  await db.query(`CREATE TEMP TABLE existing_symbol AS SELECT order_symbol FROM eshop.orders WHERE id=$1`, [order.id]);
  await db.query('GRANT SELECT ON pg_temp.existing_symbol TO postgres');
  await db.query("CREATE OR REPLACE FUNCTION public.generate_order_symbol() RETURNS text LANGUAGE sql VOLATILE SET search_path=public,extensions AS $$ SELECT CASE WHEN nextval('pg_temp.symbol_attempt')=1 THEN (SELECT order_symbol FROM pg_temp.existing_symbol) ELSE pg_temp.real_order_symbol() END $$");
  const next = (await one('SELECT public.create_ticket_order_internal_v1($1) r', [input])).r;
  assert.equal(next.code, 200, JSON.stringify(next));
  assert.notEqual(next.order.order_symbol, order.order_symbol);
  assert.equal(Number((await one('SELECT last_value FROM pg_temp.symbol_attempt')).last_value), 2);
  await db.query("CREATE OR REPLACE FUNCTION public.generate_order_symbol() RETURNS text LANGUAGE sql VOLATILE SET search_path=public,extensions AS $$ SELECT order_symbol FROM pg_temp.existing_symbol $$");
  const before = await one('SELECT (SELECT count(*) FROM eshop.orders)::int o,(SELECT count(*) FROM eshop.tickets)::int t,(SELECT count(*) FROM eshop.payment_info)::int p,(SELECT count(*) FROM public.email_messages)::int e');
  const exhausted = (await one('SELECT public.create_ticket_order_internal_v1($1) r', [input])).r;
  assert.equal(exhausted.code, 1013);
  assert.match(exhausted.message, /allocation exhausted/);
  assert.deepEqual(await one('SELECT (SELECT count(*) FROM eshop.orders)::int o,(SELECT count(*) FROM eshop.tickets)::int t,(SELECT count(*) FROM eshop.payment_info)::int p,(SELECT count(*) FROM public.email_messages)::int e'), before);
  // A different unique constraint must fail immediately, without ten retries.
  await db.query(saved);
  const ddl = await one("SELECT format('CREATE UNIQUE INDEX fixture_other_unique ON eshop.orders(form) WHERE occasion = %s AND id <> %s', $1::bigint, $2::bigint) ddl", [occasion, next.order.id]);
  await db.query(ddl.ddl);
  await db.query('ALTER SEQUENCE pg_temp.symbol_attempt RESTART');
  await db.query("CREATE OR REPLACE FUNCTION public.generate_order_symbol() RETURNS text LANGUAGE sql VOLATILE SET search_path=public,extensions AS $$ SELECT CASE WHEN nextval('pg_temp.symbol_attempt')>0 THEN pg_temp.real_order_symbol() END $$");
  const unrelated = (await one('SELECT public.create_ticket_order_internal_v1($1) r', [input])).r;
  assert.equal(unrelated.code, 1013);
  assert.match(unrelated.message, /fixture_other_unique/);
  assert.equal(Number((await one('SELECT last_value FROM pg_temp.symbol_attempt')).last_value), 1);
  await db.query('ROLLBACK');

  // Real concurrent transactions contend on the global unique index.
  const symbol = (await one('SELECT public.generate_order_symbol() s')).s;
  const replacement = (await one('SELECT public.generate_order_symbol() s')).s;
  await a.query('BEGIN'); await b.query('BEGIN');
  const idA = (await a.query('INSERT INTO eshop.orders(order_sequence,order_symbol) VALUES(1,$1) RETURNING id', [symbol])).rows[0].id;
  const pidB = (await b.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const pending = b.query('INSERT INTO eshop.orders(order_sequence,order_symbol) VALUES(1,$1) ON CONFLICT ON CONSTRAINT orders_order_symbol_key DO NOTHING RETURNING id', [symbol]);
  let blocked = false;
  for (let i = 0; i < 200; i++) {
    blocked = (await one("SELECT wait_event_type='Lock' blocked FROM pg_stat_activity WHERE pid=$1", [pidB])).blocked;
    if (blocked) break;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert.equal(blocked, true, 'second transaction actually blocked on first');
  await a.query('COMMIT');
  assert.equal((await pending).rowCount, 0, 'conflict target retries after committed concurrent collision');
  const idB = (await b.query('INSERT INTO eshop.orders(order_sequence,order_symbol) VALUES(1,$1) RETURNING id', [replacement])).rows[0].id;
  await b.query('COMMIT');
  await db.query('DELETE FROM eshop.orders WHERE id=ANY($1::bigint[])', [[idA, idB]]);
  console.log('PASS: backfill/rerun, immutable snapshots, real writer collision/retry, exhaustion/rollback, replay/spoofing and two contending transactions');
} finally {
  await Promise.allSettled(clients.map(c => c.query('ROLLBACK')));
  await Promise.all(clients.map(c => c.end()));
}
