import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import fs from 'node:fs';
import pg from 'pg';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from './disposable_database.js';

test('Barion recovery claims serialize and stale ingest cannot replay financial effects',async()=>{
 assert(process.env.DATABASE_URL);assertLocalDatabaseUrl(process.env.DATABASE_URL);
 const a=new pg.Client({connectionString:process.env.DATABASE_URL}),b=new pg.Client({connectionString:process.env.DATABASE_URL});
 await a.connect();await b.connect();
 const attempt=randomUUID(),connection=randomUUID(),remote=randomUUID().replaceAll('-',''),account=randomUUID().replaceAll('-','');
 try {
  await assertDisposableDatabase(a);
  await a.query("BEGIN;SET LOCAL request.jwt.claim.role='service_role';SET LOCAL festapp.email_wake='scheduled'");
  await a.query(fs.readFileSync(new URL('../../../database/tests/scanning/fixture.sql',import.meta.url),'utf8'));
  const fx=(await a.query('SELECT public.scanner_test_fixture(1) fx')).rows[0].fx;
  const ticket=Number(fx.tickets[0]);
  const scope=(await a.query('SELECT o.id,oc.organization,oc.unit FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.order_product_ticket x ON x."order"=o.id WHERE x.ticket=$1',[ticket])).rows[0];
  await a.query('INSERT INTO eshop.barion_connections(id,organization_id,unit_id,account_id,business_name) VALUES($1,$2,$3,$4,$5)',[connection,scope.organization,scope.unit,account,'Souběžný sandbox test']);
  const pi=(await a.query("INSERT INTO eshop.payment_info(amount,currency_code,payment_method,barion_connection_id) VALUES(1,'CZK','barion',$1) RETURNING id",[connection])).rows[0].id;
  await a.query("UPDATE eshop.orders SET payment_info=$1,price=1,currency_code='CZK',state='ordered' WHERE id=$2",[pi,scope.id]);
  await a.query("UPDATE eshop.tickets SET state='ordered' WHERE id=$1",[ticket]);
  await a.query("INSERT INTO eshop.barion_attempts(id,order_id,payment_info_id,organization_id,unit_id,connection_id,amount_minor,currency,created_at,reservation_expires_at,return_base_url,remote_id) VALUES($1,$2,$3,$4,$5,$6,100,'CZK',clock_timestamp()-interval '1 minute',clock_timestamp()+interval '20 minutes','https://tickets.example.test/payments/barion/return',$7)",[attempt,scope.id,pi,scope.organization,scope.unit,connection,remote]);
  await a.query('COMMIT');
  const pid=(await b.query('SELECT pg_backend_pid() id')).rows[0].id;
  const rpc=(db,operation,args)=>db.query('SELECT public.barion_runtime_internal($1,$2::jsonb) result',[operation,JSON.stringify(args)]).then(r=>r.rows[0].result);
  await a.query("BEGIN;SET LOCAL request.jwt.claim.role='service_role'");
  const first=await rpc(a,'claim_sync',{attemptId:attempt,accountId:account});assert.equal(first.disposition,'dispatch');
  await b.query("BEGIN;SET LOCAL request.jwt.claim.role='service_role'");
  const waiting=rpc(b,'claim_sync',{attemptId:attempt,accountId:account});
  let overlap=false;
  const limit=Date.now()+3000;
  while(Date.now()<limit){
   if((await a.query('SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid=$1 AND NOT granted) blocked',[pid])).rows[0].blocked){overlap=true;break;}
   await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert(overlap,'second connection must actually overlap on the stored lock');
  await a.query('COMMIT');assert.equal((await waiting).disposition,'busy');await b.query('COMMIT');
  await a.query("BEGIN;SET LOCAL request.jwt.claim.role='service_role';SET LOCAL festapp.email_wake='scheduled'");
  const facts={checkoutId:remote,paymentId:remote,checkoutStatus:'complete',movements:[{providerId:randomUUID().replaceAll('-',''),kind:'payment',amountMinor:100,currency:'CZK',occurredAt:Math.floor(Date.now()/1000)}],disputes:[]};
  assert.equal((await rpc(a,'ingest',{attemptId:attempt,lease:first.lease,facts})).payment.status,'paid');await a.query('COMMIT');
  await b.query("SET request.jwt.claim.role='service_role'");
  await assert.rejects(()=>rpc(b,'ingest',{attemptId:attempt,lease:first.lease,facts}),/BARION_LEASE_LOST/);
  for(let i=0;i<2;i++)await rpc(b,'callback_schedule',{paymentId:remote});
  assert.equal(Number((await a.query('SELECT count(*) n FROM eshop.barion_movements WHERE attempt_id=$1',[attempt])).rows[0].n),1);
  assert.equal(Number((await a.query('SELECT paid FROM eshop.payment_info WHERE id=$1',[pi])).rows[0].paid),1);
  // Synthetic committed rows remain only in this disposable project, which the
  // operator stops without backup after the validation batch. No workers run.
 }finally{await a.query('ROLLBACK').catch(()=>{});await b.query('ROLLBACK').catch(()=>{});await a.end();await b.end();}
});
