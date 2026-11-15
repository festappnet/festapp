import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {setTimeout as delay} from 'node:timers/promises';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;assertLocalDatabaseUrl(connectionString);
const fixtureSQL=await readFile(new URL('../helpers/form_measurement_fixture.sql',import.meta.url),'utf8');
const assertionSQL=await readFile(new URL('../helpers/assertions.sql',import.meta.url),'utf8');
async function connect(){const c=new Client({connectionString});await c.connect();await assertDisposableDatabase(c);await c.query("SET statement_timeout='10s'; SET lock_timeout='8s'; SELECT set_config('festapp.email_wake','scheduled',false)");return c;}
async function fixture(c,limit=1){
 await c.query('BEGIN');await c.query(assertionSQL);await c.query(fixtureSQL);
 const x=(await c.query('SELECT pg_temp.fixture(NULL) x')).rows[0].x;
 await c.query("UPDATE public.forms SET is_open=true WHERE id=$1",[x.form]);
 await c.query('INSERT INTO public.unit_users(unit,"user",is_editor) VALUES($1,$2,true)',[x.unit,x.actor]);
 await c.query(`UPDATE public.occasions SET features='[{"code":"discount_codes","is_enabled":true}]' WHERE id=$1`,[x.occasion]);
 x.code=(await c.query(`SELECT public.save_discount_code($1,jsonb_build_object('code','LIMIT1','kind','percent','value',1000,'isActive',true,'usageLimit',$2::int)) c`,[x.occasion,limit])).rows[0].c;
 x.payload=(await c.query(`SELECT pg_temp.checkout($1)||'{"discount":{"code":"LIMIT1"}}'::jsonb p`,[x])).rows[0].p;
 x.payload.email='discount-race-'+x.form+'@example.invalid';
 const q=(await c.query('SELECT public.quote_order_discount($1) q',[x.payload])).rows[0].q;assert.equal(q.code,200,JSON.stringify(q));
 x.payload.discount.fingerprint=q.quote.fingerprint;
 await c.query('COMMIT');return x;
}
async function actor(c,x){await c.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[x.actor]);}
async function order(c,x,command=randomUUID()){return (await c.query('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) r',[x.payload,command,randomUUID()])).rows[0].r;}
async function blocked(observer,pid){for(let n=0;n<100;n++){if((await observer.query('SELECT cardinality(pg_blocking_pids($1)) n',[pid])).rows[0].n>0)return;await delay(20);}throw Error('Expected a real database lock wait');}

test('last use is serialized, committed retry replays, failed input rolls back',async()=>{
 const a=await connect(),b=await connect(),observer=await connect();
 try {
  const x=await fixture(a);await actor(a,x);await actor(b,x);
  await a.query('BEGIN');const command=randomUUID();const first=await order(a,x,command);assert.equal(first.data.code,200,JSON.stringify(first));
  await b.query('BEGIN');const secondPending=order(b,x);await blocked(observer,b.processID);
  await a.query('COMMIT');const second=await secondPending;await b.query('COMMIT');
  assert.equal(second.status,'rejected');assert.equal(second.data.errorCode,'DISCOUNT_QUOTE_CHANGED');
  assert.equal((await observer.query('SELECT count(*) n FROM eshop.order_discounts WHERE code_id=$1',[x.code.id])).rows[0].n,'1');
  const replay=await order(a,x,command);assert.equal(replay.data.order.id,first.data.order.id);assert.equal((await a.query('SELECT count(*) n FROM public.client_mutation_receipts WHERE command_id=$1',[command])).rows[0].n,'1');
  const rollbackCode=(await a.query(`SELECT public.save_discount_code($1,'{"code":"ROLLBACK","kind":"percent","value":1000,"isActive":true,"usageLimit":1}') c`,[x.occasion])).rows[0].c;
  x.payload.discount={code:'ROLLBACK'};
  x.payload.discount.fingerprint=(await a.query('SELECT public.quote_order_discount($1) q',[x.payload])).rows[0].q.quote.fingerprint;
  await a.query('BEGIN');assert.equal((await order(a,x)).data.code,200);await a.query('ROLLBACK');
  assert.equal((await observer.query('SELECT count(*) n FROM eshop.order_discounts WHERE code_id=$1',[rollbackCode.id])).rows[0].n,'0');
  assert.equal((await order(a,x)).data.code,200,'rollback left last use available');
 } finally {await Promise.all([a,b,observer].map(async c=>{await c.query('ROLLBACK').catch(()=>{});await c.end();}));}
});

test('feature writer cannot pass a running commit, off preserves snapshot and retry',async()=>{
 const a=await connect(),b=await connect(),observer=await connect();
 try {
  const x=await fixture(a,10);await actor(a,x);await actor(b,x);
  const config=(await a.query('SELECT to_jsonb(o) config FROM public.occasions o WHERE id=$1',[x.occasion])).rows[0].config;
  config.features=[{code:'discount_codes',is_enabled:false}];
  await a.query('BEGIN');const command=randomUUID();const first=await order(a,x,command);assert.equal(first.data.code,200,JSON.stringify(first));
  await b.query('BEGIN');const disabling=b.query('SELECT public.update_occasion_internal_v1($1)',[config]);await blocked(observer,b.processID);
  await a.query('COMMIT');await disabling;await b.query('COMMIT');
  assert.equal((await order(a,x,command)).data.order.id,first.data.order.id);
  assert.equal((await a.query('SELECT public.quote_order_discount($1) q',[x.payload])).rows[0].q.errorCode,'DISCOUNT_INVALID');
  assert.equal((await order(a,x)).data.errorCode,'DISCOUNT_QUOTE_CHANGED','direct commit is denied while off');
  config.features=[{code:'discount_codes',is_enabled:true}];
  await b.query('SELECT public.update_occasion_internal_v1($1)',[config]);
  assert.equal((await order(a,x)).data.errorCode,'DISCOUNT_QUOTE_CHANGED','old quote requires confirmation after off/on');
  x.payload.discount.fingerprint=(await a.query('SELECT public.quote_order_discount($1) q',[x.payload])).rows[0].q.quote.fingerprint;
  assert.equal((await order(a,x)).data.code,200,'new confirmation after enabling can use the existing definition');
  assert.equal((await observer.query('SELECT count(*) n FROM eshop.order_discounts WHERE code_id=$1',[x.code.id])).rows[0].n,'2','off/on preserves previous uses');
  assert.equal((await a.query('SELECT net_amount FROM eshop.order_discounts WHERE order_id=$1',[first.data.order.id])).rows[0].net_amount,'90.00');
 } finally {await Promise.all([a,b,observer].map(async c=>{await c.query('ROLLBACK').catch(()=>{});await c.end();}));}
});

test('populated additive upgrade reads sold prices and preserves order/payment/history amounts',async()=>{
 const db=await connect();
 try {
  const x=await fixture(db,10);await actor(db,x);
  delete x.payload.discount;
  const first=await order(db,x);assert.equal(first.data.code,200);
  await db.query('UPDATE eshop.products SET price=200 WHERE id=$1',[x.product]);
  const second=await order(db,x);assert.equal(second.data.code,200);
  const ids=[first.data.order.id,second.data.order.id];
  const before=(await db.query('SELECT o.id,o.price,p.amount,o.data,(SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM eshop.orders_history h WHERE h."order"=o.id) history FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=ANY($1) ORDER BY o.id',[ids])).rows;
  await db.query('BEGIN');
  await db.query('UPDATE eshop.order_product_ticket SET base_price=NULL,net_price=NULL WHERE "order"=ANY($1)',[ids]);
  await db.query('UPDATE eshop.products SET price=999 WHERE id=$1',[x.product]);
  const schema=await readFile(new URL('../../functions/eshop_discounts/schema.sql',import.meta.url),'utf8');
  await db.query(schema);await db.query(schema);
  assert.deepEqual((await db.query('SELECT base_price,discount_amount,net_price FROM eshop.order_product_ticket WHERE "order"=ANY($1) ORDER BY "order"',[ids])).rows,[{base_price:'100.00',discount_amount:'0.00',net_price:'100.00'},{base_price:'200.00',discount_amount:'0.00',net_price:'200.00'}]);
  const after=(await db.query('SELECT o.id,o.price,p.amount,o.data,(SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM eshop.orders_history h WHERE h."order"=o.id) history FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=ANY($1) ORDER BY o.id',[ids])).rows;
  assert.deepEqual(after,before);
  await db.query('ROLLBACK');
 } finally {await db.query('ROLLBACK').catch(()=>{});await db.end();}
});
