// Canonical RPCs, real parallel pg clients; only an explicitly disposable loopback DB.
import pg from 'pg';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
const url = process.env.DATABASE_URL;
if (!url || !['127.0.0.1', 'localhost'].includes(new URL(url).hostname) || process.env.FESTAPP_DISPOSABLE_ORDER_DB !== 'yes') throw new Error('Disposable loopback database required');
const root = new URL('../../', import.meta.url);
const source = p => fs.readFileSync(new URL(p, root), 'utf8').replace(/^BEGIN;\n|^COMMIT;$/gm, '');
const clients = Array.from({length: 17}, () => new pg.Client({connectionString: url}));
await Promise.all(clients.map(c => c.connect()));
const [db,a,b] = clients;
const one = async (sql, params=[]) => (await db.query(sql,params)).rows[0];
const expand = source('supabase/migrations/20261006140000_order_sequence_expand.sql');
const contract = source('supabase/migrations/20261006141000_order_sequence_contract.sql');
let occasion, otherOccasion, input, alternateForm;
const command = async (c, payload=input, id=crypto.randomUUID(), clientId=crypto.randomUUID()) => {
 const r=(await c.query('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) r',[payload,id,clientId])).rows[0].r;
 assert.equal(r.code,200,JSON.stringify(r));
 return r.data.order;
};
const fixture = async () => {
 const org = (await one("INSERT INTO public.organizations(title) VALUES('Sequence command fixture') RETURNING id")).id;
 const unit = (await one("INSERT INTO public.units(title,organization) VALUES('Unit',$1) RETURNING id", [org])).id;
 occasion = (await one("INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time) VALUES('Occasion',$1,$2,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id", [unit, org])).id;
 otherOccasion = (await one("INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time) VALUES('Other',$1,$2,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id", [unit, org])).id;
 const secret = (await one("INSERT INTO eshop.secrets(secret) VALUES(gen_random_uuid()::text) RETURNING id")).id;
 const account = (await one("INSERT INTO eshop.bank_accounts(title,supported_currencies,secret,type) VALUES('Account',ARRAY['CZK'],$1,'FIO') RETURNING id", [secret])).id;
 await db.query('INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES($1,$2,1)', [unit, account]);
 const form = await one("INSERT INTO public.forms(title,occasion,is_open) VALUES('Form',$1,true) RETURNING id,key", [occasion]);
 const type = (await one("INSERT INTO eshop.product_types(title,occasion,type) VALUES('Ticket',$1,'spot') RETURNING id", [occasion])).id;
 const product = (await one("INSERT INTO eshop.products(title,occasion,product_type,price,currency_code,is_hidden) VALUES('Product',$1,$2,100,'CZK',false) RETURNING id", [occasion, type])).id;
 await db.query('INSERT INTO public.form_fields(form,product_type) VALUES($1,$2)', [form.id, type]);
 alternateForm = await one("INSERT INTO public.forms(title,occasion,is_open) VALUES('Other form',$1,true) RETURNING id,key",[occasion]);
 await db.query('INSERT INTO public.form_fields(form,product_type) VALUES($1,$2)',[alternateForm.id,type]);
 input={form:form.key,email:'fixture@example.invalid',ticket:[{fields:[{product_type:product}]}]};
};
const waitBlocked = async pid => {
 for (let i=0;i<300;i++) {
  if ((await one("SELECT wait_event_type='Lock' blocked FROM pg_stat_activity WHERE pid=$1",[pid])).blocked) return;
  await new Promise(r=>setTimeout(r,10));
 }
 throw new Error('Expected real lock wait not observed');
};
try {
 await Promise.all(clients.map(c=>c.query("SET lock_timeout='30s'; SET statement_timeout='60s'")));
 assert.equal((await one('SHOW transaction_isolation')).transaction_isolation,'read committed');
 await fixture();
 // Historical migration: tied timestamps, storno, multiple forms, fields/snapshots unchanged.
 await db.query('BEGIN');
 await db.query('ALTER TABLE eshop.orders DROP COLUMN order_sequence');
 const old=(await db.query(`INSERT INTO eshop.orders(order_symbol,occasion,state,data,price,created_at)
 SELECT public.generate_order_symbol(),$1,state,'{"retained":"snapshot"}',10,'2020-01-01' FROM (VALUES('paid'),('storno'),(NULL)) s(state)
 RETURNING id,to_jsonb(orders) original`,[occasion])).rows;
 await db.query('INSERT INTO eshop.orders_history("order",data,state,price) SELECT id,data,state,price FROM eshop.orders WHERE id=ANY($1::bigint[])',[old.map(r=>r.id)]);
 const snapshots=(await db.query('SELECT to_jsonb(h) data FROM eshop.orders_history h WHERE "order"=ANY($1::bigint[]) ORDER BY id',[old.map(r=>r.id)])).rows;
 await db.query(expand); await db.query(expand);
 assert.deepEqual((await db.query('SELECT to_jsonb(h) data FROM eshop.orders_history h WHERE "order"=ANY($1::bigint[]) ORDER BY id',[old.map(r=>r.id)])).rows,snapshots);
 for (const [i,row] of old.entries()) {
  const actual=await one("SELECT order_sequence,to_jsonb(o)-'order_sequence' actual FROM eshop.orders o WHERE id=$1",[row.id]);
  assert.equal(Number(actual.order_sequence),i+1); assert.deepEqual(actual.actual,row.original);
 }
 await db.query('SAVEPOINT before_contract');
 await db.query("INSERT INTO eshop.orders(order_symbol,occasion,state) VALUES(public.generate_order_symbol(),$1,'storno')",[occasion]);
 await assert.rejects(db.query(contract),/residual backfill required/);
 await db.query('ROLLBACK TO SAVEPOINT before_contract');
 await db.query("INSERT INTO eshop.orders(order_symbol,occasion,state) VALUES(public.generate_order_symbol(),$1,'storno')",[occasion]);
 assert.equal(Number((await one('SELECT public.backfill_order_sequences($1) n',[occasion])).n),1);
 assert.equal(Number((await one('SELECT public.backfill_order_sequences($1) n',[occasion])).n),0);
 await db.query(contract); await db.query(contract);
 assert.equal((await one("SELECT to_regprocedure('public.backfill_order_sequences(bigint)') gone")).gone,null);
 await db.query('ROLLBACK');
 // Idempotent replay does not allocate; cancelled maximum counts; deletion permits reuse.
 const id=crypto.randomUUID(),client=crypto.randomUUID();
 const first=await command(db,input,id,client);
 assert.deepEqual(await command(db,input,id,client),first);
 assert.equal(Number((await one('SELECT order_sequence n FROM eshop.orders WHERE id=$1',[first.id])).n),1);
 await db.query("UPDATE eshop.orders SET state='storno' WHERE id=$1",[first.id]);
 const second=await command(db,{...input,form:alternateForm.key});assert.equal(Number((await one('SELECT order_sequence n FROM eshop.orders WHERE id=$1',[second.id])).n),2);
 // A bare owner row can be fully deleted without disturbing command snapshots or FKs.
 const bare=await one('INSERT INTO eshop.orders(order_symbol,occasion,order_sequence) VALUES(public.generate_order_symbol(),$1,public.next_order_sequence($1)) RETURNING id,order_sequence',[occasion]);
 await db.query('DELETE FROM eshop.orders WHERE id=$1',[bare.id]);
 assert.equal(Number((await one('SELECT public.next_order_sequence($1) n',[occasion])).n),Number(bare.order_sequence));
 for (const spoof of [{...input,order_sequence:99},{...input,orderSequence:99},{...input,data:{order_sequence:99}},{...input,data:{orderSequence:99}}]) {
  assert.equal((await one('SELECT public.create_ticket_order_internal_v1($1) r',[spoof])).r.code,1001);
 }
 // B actually waits before MAX, sees A's commit; rollback releases unused allocation.
 for (const commit of [true,false]) {
  await a.query('BEGIN');await b.query('BEGIN');
  const held=await command(a);
  const number=Number((await a.query('SELECT order_sequence n FROM eshop.orders WHERE id=$1',[held.id])).rows[0].n);
  const pid=(await b.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const pending=command(b);
  await waitBlocked(pid);
  // Independent occasion finishes while A still owns its lock.
  const independent=await clients[3].query('SELECT public.next_order_sequence($1) n',[otherOccasion]);
  assert.equal(Number(independent.rows[0].n),1);
  await a.query(commit?'COMMIT':'ROLLBACK');
  const result=await pending;
  assert.equal(Number((await b.query('SELECT order_sequence n FROM eshop.orders WHERE id=$1',[result.id])).rows[0].n),number+(commit?1:0));
  await b.query('COMMIT');
 }
 // Force symbol collision and exhaustion through the real internal writer.
 await db.query('BEGIN');
 const saved=(await one("SELECT pg_get_functiondef('public.generate_order_symbol()'::regprocedure) def")).def;
 await db.query(saved.replace('public.generate_order_symbol()', 'pg_temp.real_symbol()'));
 await db.query('CREATE TEMP SEQUENCE attempts');
 const existing=(await one('SELECT order_symbol s FROM eshop.orders WHERE id=$1',[first.id])).s;
 await db.query(`CREATE OR REPLACE FUNCTION public.generate_order_symbol() RETURNS text LANGUAGE sql VOLATILE SET search_path=public,extensions AS $$ SELECT CASE WHEN nextval('pg_temp.attempts')=1 THEN '${existing}' ELSE pg_temp.real_symbol() END $$`);
 const expected=Number((await one('SELECT MAX(order_sequence)+1 n FROM eshop.orders WHERE occasion=$1',[occasion])).n);
 const retried=await command(db);
 assert.equal(Number((await one('SELECT order_sequence n FROM eshop.orders WHERE id=$1',[retried.id])).n),expected);
 assert.equal(Number((await one('SELECT last_value FROM pg_temp.attempts')).last_value),2);
 const before=await one('SELECT (SELECT count(*) FROM eshop.orders) o,(SELECT count(*) FROM eshop.tickets) t,(SELECT count(*) FROM eshop.payment_info) p,(SELECT count(*) FROM public.email_messages) e');
 await db.query(`CREATE OR REPLACE FUNCTION public.generate_order_symbol() RETURNS text LANGUAGE sql VOLATILE SET search_path=public,extensions AS $$ SELECT '${existing}'::text $$`);
 const failed=(await one('SELECT public.create_ticket_order_internal_v1($1) r',[input])).r;
 assert.equal(failed.code,1013);
 assert.deepEqual(await one('SELECT (SELECT count(*) FROM eshop.orders) o,(SELECT count(*) FROM eshop.tickets) t,(SELECT count(*) FROM eshop.payment_info) p,(SELECT count(*) FROM public.email_messages) e'),before);
 await db.query('ROLLBACK');
 // 100 real commands, 16 parallel clients, exactly one ticket/payment/intent per order.
 const baseline=await one('SELECT count(*)::int n FROM eshop.orders WHERE occasion=$1',[occasion]);
 const times=[],start=performance.now();let next=0;
 await Promise.all(clients.slice(1).map(async c=>{
  while(next<100){next++;const at=performance.now();await command(c);times.push(performance.now()-at);}
 }));
 const elapsed=performance.now()-start;times.sort((a,b)=>a-b);
 const counts=await one(`SELECT count(*)::int orders,count(DISTINCT order_sequence)::int sequences,
 (SELECT count(*)::int FROM eshop.tickets t WHERE t.occasion=$1) tickets,
 count(payment_info)::int payments,
 (SELECT count(DISTINCT order_id)::int FROM public.email_messages WHERE order_id IN(SELECT id FROM eshop.orders WHERE occasion=$1)) intents FROM eshop.orders WHERE occasion=$1`,[occasion]);
 assert.equal(counts.orders,baseline.n+100);assert.equal(counts.sequences,counts.orders);
 assert.equal(counts.tickets,counts.orders);assert.equal(counts.payments,counts.orders);assert.equal(counts.intents,counts.orders);
 // Residual repair follows the same lock order while a real writer is in flight.
 await db.query('ALTER TABLE eshop.orders ALTER COLUMN order_sequence DROP NOT NULL');
 await db.query(source('automation/order-sequence/residual-function.sql'));
 const residual=await one("INSERT INTO eshop.orders(order_symbol,occasion) VALUES(public.generate_order_symbol(),$1) RETURNING id,to_jsonb(orders)-'order_sequence' original",[occasion]);
 await a.query('BEGIN');
 const held=await command(a);
 const heldNumber=Number((await a.query('SELECT order_sequence n FROM eshop.orders WHERE id=$1',[held.id])).rows[0].n);
 await b.query('BEGIN');
 const pid=(await b.query('SELECT pg_backend_pid() pid')).rows[0].pid;
 const repair=b.query('SELECT public.backfill_order_sequences($1) n',[occasion]);
 await waitBlocked(pid);
 await a.query('COMMIT');
 assert.equal(Number((await repair).rows[0].n),1);
 await b.query('COMMIT');
 const repaired=await one("SELECT order_sequence,to_jsonb(o)-'order_sequence' actual FROM eshop.orders o WHERE id=$1",[residual.id]);
 assert.equal(Number(repaired.order_sequence),heldNumber+1);
 assert.deepEqual(repaired.actual,residual.original);
 await db.query(contract);
 // Index MAX access on an occasion larger than current production.
 await db.query('BEGIN');
 await db.query('INSERT INTO eshop.orders(order_symbol,occasion,order_sequence) SELECT public.generate_order_symbol(),$1,n FROM generate_series(1,10000) n',[otherOccasion]);
 await db.query('ANALYZE eshop.orders');
 const explain=(await db.query('EXPLAIN SELECT COALESCE(MAX(order_sequence),0)+1 FROM eshop.orders WHERE occasion=$1',[otherOccasion])).rows.map(r=>r['QUERY PLAN']).join('\n');
 assert.match(explain,/Index Only Scan.*orders_order_sequence_key/);
 await db.query('ROLLBACK');
 console.log(JSON.stringify({pass:true,commands:100,clients:16,throughputPerSecond:+(100000/elapsed).toFixed(1),p50Ms:+times[50].toFixed(1),p95Ms:+times[95].toFixed(1),counts,checks:'migration/rerun/retained fields/residual/contract/replay/spoofing/commit/rollback/independent scopes/collision/exhaustion/index MAX'}));
} finally {
 await Promise.allSettled(clients.map(c=>c.query('ROLLBACK')));
 await Promise.all(clients.map(c=>c.end()));
}
