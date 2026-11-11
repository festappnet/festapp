// Compare the installed reader with a candidate inside one disposable rollback.
// DATABASE_URL=... pnpm exec node ../automation/benchmarks/order_reads.mjs
// Optional --baseline-sql restores a saved pre-change function definition file.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { assertLocalDatabaseUrl, assertDisposableDatabase } from '../../web_client/tests/database/disposable_database.js';

const require = createRequire(new URL('../../web_client/package.json', import.meta.url));
const { Client } = require('pg');
const root = new URL('../../', import.meta.url);
const read = path => fs.readFileSync(new URL(path, root), 'utf8');
const databaseUrl = process.env.DATABASE_URL;
assert.ok(databaseUrl, 'DATABASE_URL must identify a local disposable database');
assertLocalDatabaseUrl(databaseUrl);
const client = new Client({ connectionString: databaseUrl, statement_timeout: 30000 });
const baselineIndex = process.argv.indexOf('--baseline-sql');
const candidate = read('supabase/migrations/20261111120000_order_read_performance.sql');
const minimumSpeedup = Number(process.env.FESTAPP_ORDER_READ_MIN_SPEEDUP ?? 0);
assert.ok(Number.isFinite(minimumSpeedup) && minimumSpeedup >= 0 && minimumSpeedup < 1);

// Capacity snapshots deliberately use clock_timestamp(), even in one transaction.
function comparable(value) {
  if (Array.isArray(value)) return value.map(comparable);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value)
      .filter(([key]) => key !== 'serverTime')
      .map(([key, item]) => [key, comparable(item)]));
  }
  return value;
}

await client.connect();
try {
  await assertDisposableDatabase(client);
  await client.query('BEGIN');
  if (baselineIndex !== -1) {
    assert.ok(process.argv[baselineIndex + 1], '--baseline-sql requires a file');
    await client.query(fs.readFileSync(process.argv[baselineIndex + 1], 'utf8'));
  }
  for (const file of [
    'database/tests/helpers/assertions.sql', 'database/tests/scanning/fixture.sql',
    'database/tests/helpers/payment_lifecycle_fixture.sql',
    'database/tests/helpers/refund_operation_fixture.sql',
    'database/tests/helpers/high_volume_email_fixture.sql',
  ]) await client.query(read(file));
  const { rows: [{ x }] } = await client.query('SELECT pg_temp.refund_fixture() x');
  await client.query('INSERT INTO public.occasion_link_reservations(slug,occasion) VALUES($1,$2)', [x.link, x.occasion]);
  // Same event scale: 113 orders with actual ticket links and email history.
  // Unrelated ledger rows
  // expose repeated full-ledger scans rather than benchmarking an empty table.
  await client.query(`DO $fixture$
    DECLARE i int; pi bigint; oid bigint; tid bigint; message jsonb;
    BEGIN
      FOR i IN 2..113 LOOP
        INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,paid,currency_code,payment_method)
        VALUES(${Number(x.bank)},900000000+i,1000,0,'CZK','bank') RETURNING id INTO pi;
        INSERT INTO eshop.orders(occasion,form,price,state,currency_code,payment_info,order_symbol,order_sequence,data)
        SELECT occasion,form,price,state,currency_code,pi,public.generate_order_symbol(),i,
          data||jsonb_build_object('email','benchmark-'||i||'@example.invalid')
        FROM eshop.orders WHERE id=${Number(x.order)} RETURNING id INTO oid;
        INSERT INTO eshop.tickets(occasion,state) VALUES(${Number(x.occasion)},'ordered') RETURNING id INTO tid;
        INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES(oid,${Number(x.product)},tid);
        UPDATE eshop.orders SET data=jsonb_set(data,'{tickets,0,id}',to_jsonb(tid)) WHERE id=oid;
        message:=public.enqueue_email('order_confirmation',
          jsonb_build_object('organization',${Number(x.organization)},'occasion',${Number(x.occasion)},'unit',${Number(x.unit)}),
          'benchmark-'||i||'@example.invalid','{}','order-read-benchmark-'||oid);
        UPDATE public.email_messages SET order_id=oid,source_version=(SELECT email_payment_version FROM eshop.orders WHERE id=oid),
          workflow_state='accepted',created_at=now()-interval '2 days',
          delivered_at=CASE WHEN i%5<>0 THEN now()-interval '1 day' END,
          bounced_at=CASE WHEN i%5=0 THEN now()-interval '1 day' END
        WHERE message_id=(message->>'message_id')::uuid;
      END LOOP;
    END $fixture$;`);
  await client.query(`INSERT INTO eshop.transactions(date,amount,currency,bank_account_id)
    SELECT now(),100,'CZK',$1 FROM generate_series(1,4284)`, [x.bank]);
  // A larger hall has many saved layout nodes even when only some seats have
  // been ordered. Every ticket here has a real current seat binding.
  await client.query(`DO $seating$
    DECLARE bp bigint; group_node uuid:=gen_random_uuid(); seat_node uuid; spot bigint; item record;
      nodes jsonb:=jsonb_build_array(jsonb_build_object('id',group_node,'kind','group','label','12',
        'width',1,'height',1,'transform',jsonb_build_object('x',0,'y',0,'rotation',0)));
    BEGIN
      INSERT INTO eshop.blueprints(organization,occasion,title)
      VALUES(${Number(x.organization)},${Number(x.occasion)},'Velký sál') RETURNING id INTO bp;
      FOR item IN SELECT opt.id,row_number() OVER(ORDER BY opt.id) ordinal FROM eshop.order_product_ticket opt
        JOIN eshop.orders o ON o.id=opt."order" WHERE o.occasion=${Number(x.occasion)} LOOP
        seat_node:=gen_random_uuid();
        INSERT INTO eshop.spots(occasion,title,blueprint,order_product_ticket)
        VALUES(${Number(x.occasion)},item.ordinal::text,bp,item.id) RETURNING id INTO spot;
        INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,group_node) VALUES(bp,seat_node,spot,group_node);
        nodes:=nodes||jsonb_build_array(jsonb_build_object('id',seat_node,'kind','seat','parentId',group_node,
          'width',40,'height',40,'transform',jsonb_build_object('x',60,'y',60,'rotation',0)));
      END LOOP;
      SELECT nodes||jsonb_agg(jsonb_build_object('id',gen_random_uuid(),'kind','seat','parentId',group_node,
        'width',40,'height',40,'transform',jsonb_build_object('x',100,'y',100,'rotation',0)))
      INTO nodes FROM generate_series(1,886);
      UPDATE eshop.blueprints SET layout=jsonb_set(layout,'{nodes}',nodes) WHERE id=bp;
    END $seating$;`);
  // Histories promise ordering by creation time, with no tie-break contract.
  // Make synthetic same-transaction creation times distinct for exact parity.
  await client.query("UPDATE public.email_messages SET created_at=created_at+id*interval '1 microsecond' WHERE occasion=$1", [x.occasion]);
  const { rows: [workload] } = await client.query(`SELECT
    (SELECT count(*)::int FROM eshop.orders WHERE occasion=$1) orders,
    (SELECT count(*)::int FROM eshop.tickets WHERE occasion=$1) tickets,
    (SELECT count(*)::int FROM public.email_messages WHERE occasion=$1 AND order_id IS NOT NULL) messages,
    (SELECT count(*)::int FROM eshop.spots WHERE occasion=$1 AND order_product_ticket IS NOT NULL) seats,
    (SELECT jsonb_array_length(layout->'nodes') FROM eshop.blueprints WHERE occasion=$1) nodes`, [x.occasion]);
  assert.equal(workload.orders, 113);
  assert.equal(workload.tickets, 113);
  assert.ok(workload.messages >= 113, 'Every order needs email history in this workload');
  assert.equal(workload.seats, 113);
  assert.equal(workload.nodes, 1000);
  console.log('workload:', JSON.stringify(workload));
  await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)", [x.actor]);
  const readers = [
    ['orders', 'SELECT public.get_orders_tab_data($1,NULL) r'],
    ['tickets', `SELECT public.get_orders($1,NULL,'{"include_full_order_data":true,"include_spots":true}') r`],
    ['history', `SELECT public.get_orders($1,NULL,'{"include_full_order_data":true,"include_orders_history":true}') r`],
  ];
  async function measure() {
    const results = {};
    for (const [name, sql] of readers) {
      const samples = [];
      let result;
      for (let i = 0; i < 6; i++) {
        const started = performance.now();
        const { rows: [{ r }] } = await client.query(sql, [x.link]);
        if (i > 0) samples.push(performance.now() - started);
        result = comparable(r);
      }
      samples.sort((a, b) => a - b);
      results[name] = { result, ms: samples[2] };
    }
    return results;
  }
  const before = await measure();
  await client.query(candidate);
  const after = await measure();
  for (const [name] of readers) {
    assert.deepEqual(after[name].result, before[name].result, `${name}: response contract changed`);
    console.log(`${name}: median ${before[name].ms.toFixed(1)} -> ${after[name].ms.toFixed(1)} ms; ` +
      `${Math.round((1 - after[name].ms / before[name].ms) * 100)}% faster; JSON equal`);
    if (minimumSpeedup > 0) assert.ok(1 - after[name].ms / before[name].ms >= minimumSpeedup,
      `${name}: measured gain below required ${Math.round(minimumSpeedup * 100)}%`);
  }
} finally {
  await client.query('ROLLBACK');
  await client.end();
}
