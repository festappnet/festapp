// Execute after the SQL lane; two real writer sessions race against committed
// disposable fixtures. The observer proves PostgreSQL blocking, never sleeps as
// a substitute for the required lock boundary. No provider or bank API is called.
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {setTimeout as delay} from 'node:timers/promises';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
assertLocalDatabaseUrl(connectionString);
const assertions=await readFile(new URL('../helpers/assertions.sql',import.meta.url),'utf8');
const fixtureSQL=await readFile(new URL('../helpers/payment_lifecycle_fixture.sql',import.meta.url),'utf8');
const recipient='CZ6508000000192000145399';
async function connect(){
 const c=new Client({connectionString});await c.connect();
 try{await assertDisposableDatabase(c);await c.query("set statement_timeout='12s';set lock_timeout='8s';select set_config('festapp.email_wake','scheduled',false)");return c;}
 catch(e){await c.end();throw e;}
}
async function fixture(c){
 await c.query('begin');await c.query(assertions);await c.query(fixtureSQL);
 const x=(await c.query('select pg_temp.payment_fixture() x')).rows[0].x;
 const account=(await c.query("select public.canonical_payment_reference_account_internal($1||'/2010') account",[x.bank])).rows[0].account;
 await c.query("update eshop.bank_accounts set account_number=$2,type='FIO',supported_currencies=array['CZK'] where id=$1",[x.bank,account]);
 await c.query('insert into eshop.bank_account_users(bank_account,"user",is_admin) values($1,$2,true)',[x.bank,x.actor]);
 const ns=(await c.query("select encode(extensions.digest($1,'sha256'),'hex') ns",[account])).rows[0].ns;
 await c.query("insert into eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) values($1,'active',repeat('a',64))",[x.organization]);
 await c.query("insert into eshop.payment_reference_namespaces(id,canonical_account,allocation_enabled) values($1,$2,true)",[ns,account]);
 await c.query('insert into eshop.payment_reference_accounts(bank_account_id,namespace_id,account_number_snapshot) values($1,$2,$3)',[x.bank,ns,account]);
 await c.query(`insert into eshop.payment_reference_reservations(namespace_id,variable_symbol,source_ref,policy,payload_sha256,payment_info_id,original_payment_info_id,form_id)
  select $1,variable_symbol,'refund-fixture:'||id,'{}',repeat('a',64),id,id,$3 from eshop.payment_info where id=$2`,[ns,x.payment,x.form]);
 x.instance='refund-'+randomUUID();x.pairing=randomUUID().replaceAll('-','').slice(0,10);x.remote=String(x.bank);
 x.connection=(await c.query(`insert into eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,
  physical_account,provider,mode,state,pairing_code,manifest_sha256,legacy_blocked_at,bank_pull_at)
  values($1,'festapp',$2,$3,$4,'FIO','api','connected',$5,repeat('a',64),now(),now()) returning id`,[x.instance,x.remote,x.bank,account,x.pairing])).rows[0].id;
 x.vs=(await c.query('select variable_symbol::text vs from eshop.payment_info where id=$1',[x.payment])).rows[0].vs;
 await c.query("select pg_temp.payment_pair($1,1000)",[x]);
 await c.query('commit');return x;
}
async function begin(c,x,role='authenticated'){
 await c.query('begin');await c.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)",[x.actor,role]);
}
function payload(x,method,amount,operation='prepare_refund'){
 return {operation,orderId:x.order,method,amount:String(amount),receivedAt:'2026-11-10T12:00:00Z',note:'Concurrent refund fixture',
  ...(method==='bank'?{recipientIban:recipient,recipientName:'Refund recipient'}:{}),...(operation==='correct_record'?{reason:'Receipt correction'}:{})};
}
async function command(c,data,id=randomUUID()){
 await c.query('set local role authenticated');
 try{return (await c.query('select public.command_payment_operation($1,$2) r',[data,id])).rows[0].r;}
 finally{await c.query('reset role').catch(()=>{});}
}
function pending(p){return p.then(value=>({value}),error=>({error}));}
async function outcome(p){const r=await p;if(r.error)throw r.error;return r.value;}
function pid(c){return c.processID;}
async function blocked(observer,waiter,holder,operation){
 const deadline=Date.now()+5000;
 while(Date.now()<deadline){
  if((await observer.query('select pg_blocking_pids($1) blockers',[waiter])).rows[0].blockers.includes(holder))return;
  if(operation){
   const early=await Promise.race([operation,delay(0).then(()=>null)]);
   if(early)throw new Error('Writer completed before expected lock: '+(early.error?.message??JSON.stringify(early.value)));
  }
  await delay(10);
 }
 throw new Error('Expected real writer lock blocking');
}
async function close(...clients){await Promise.allSettled(clients.map(async c=>{await c.query('rollback');await c.end();}));}
async function totals(c,x){return (await c.query('select * from public.payment_financial_totals_internal($1)',[x.payment])).rows[0];}
async function ingest(c,x,amount=300){
 const movement=String(1_000_000+Number(x.bank));
 const event={event:'transaction.received',event_version:'2',delivery_id:'01K'+String(x.bank).padStart(23,'0'),pairing_code:x.pairing,data:{
  id:Number(x.bank),bank_account_id:Number(x.remote),amount_cents:-amount*100,currency:'CZK',date:new Date().toISOString(),direction:'outgoing',
  identity_kind:'movement',identity_provenance:'fio_api_column22',source:'fio_api',transaction_id:movement,raw_vs:x.vs,
  counter_account:recipient,transaction_type:'Bank debit'}};
 return (await c.query("select public.ingest_bank_sync_transaction($1,'festapp',repeat('a',64),$2) r",[x.instance,event])).rows[0].r;
}
for(const [firstMethod,secondMethod] of [['bank','bank'],['cash','bank'],['bank','cash']]){
 test(`${firstMethod} refund versus ${secondMethod}: order lock prevents spending the same 700 twice`,async()=>{
  const observer=await connect(),first=await connect(),second=await connect();
  try{
   const x=await fixture(observer);await begin(first,x);await begin(second,x);
   await command(first,payload(x,firstMethod,700));
   const waiting=pending(command(second,payload(x,secondMethod,700)));
   await blocked(observer,await pid(second),await pid(first));await first.query('commit');
   await assert.rejects(outcome(waiting),e=>e.message==='REFUND_AVAILABLE_EXCEEDED');await second.query('rollback');
   const f=await totals(observer,x);assert.equal(Number(f.refunded),firstMethod==='cash'?700:0);
   assert.equal((await observer.query('select count(*)::int n from eshop.refund_requests where payment_info=$1',[x.payment])).rows[0].n,1);
  }finally{await close(second,first,observer);}
 });
}
test('issued reservation blocks a concurrent negative receipt correction',async()=>{
 const observer=await connect(),first=await connect(),second=await connect();
 try{
  const x=await fixture(observer);await begin(first,x);await begin(second,x);
  await command(first,payload(x,'bank',700));
  const waiting=pending(command(second,payload(x,'cash',-400,'correct_record')));
  await blocked(observer,await pid(second),await pid(first));await first.query('commit');
  await assert.rejects(outcome(waiting),e=>e.message==='PAYMENT_REFUND_RESERVATION_CONFLICT');await second.query('rollback');
  assert.equal(Number((await totals(observer,x)).gross_received),1000);
 }finally{await close(second,first,observer);}
});
test('late verified debit settles after concurrent explicit cancellation without hiding money',async()=>{
 const observer=await connect(),cancelling=await connect(),bank=await connect();
 try{
  const x=await fixture(observer),request=randomUUID();await begin(observer,x);await command(observer,payload(x,'bank',300),request);await observer.query('commit');
  await begin(cancelling,x);await command(cancelling,{operation:'cancel_pending',orderId:x.order,requestId:request,transferNotSubmitted:true});
  await begin(bank,x,'service_role');const waiting=pending(ingest(bank,x));
  await blocked(observer,await pid(bank),await pid(cancelling),waiting);await cancelling.query('commit');
  await outcome(waiting);await bank.query('commit');
  assert.equal(Number((await totals(observer,x)).refunded),300);
  const r=(await observer.query('select status,result from eshop.refund_requests where id=$1',[request])).rows[0];
  assert.equal(r.status,'succeeded');assert.equal(r.result.deviation,true);
 }finally{await close(bank,cancelling,observer);}
});
test('verified ingest waits for concurrently prepared instruction and settles exactly once',async()=>{
 const observer=await connect(),preparing=await connect(),bank=await connect();
 try{
  const x=await fixture(observer);await begin(preparing,x);await command(preparing,payload(x,'bank',300));
  await begin(bank,x,'service_role');const waiting=pending(ingest(bank,x));
  await blocked(observer,await pid(bank),await pid(preparing),waiting);await preparing.query('commit');
  await outcome(waiting);await bank.query('commit');
  const f=await totals(observer,x);assert.equal(Number(f.gross_received),1000);assert.equal(Number(f.refunded),300);assert.equal(Number(f.net_received),700);
  assert.equal((await observer.query(`select count(*)::int n from eshop.refund_settlements s join eshop.transactions t on t.id=s.transaction_id where t.payment_info=$1`,[x.payment])).rows[0].n,1);
 }finally{await close(bank,preparing,observer);}
});
for(const action of ['delete','unlink','suspend']){
 test(`refund preparation fences concurrent source/order ${action}`,async()=>{
  const observer=await connect(),preparing=await connect(),other=await connect();
  try{
   const x=await fixture(observer);await begin(preparing,x);await command(preparing,payload(x,'bank',300));await begin(other,x);
   const waiting=pending((async()=>{
    await other.query('set local role authenticated');
    if(action==='delete')return other.query('select public.delete_order_client_sync_v1($1,$2)',[x.order,randomUUID()]);
    if(action==='unlink')return other.query('select public.link_bank_account_to_unit($1,(select unit from public.occasions where id=$2),null,true)',[x.bank,x.occasion]);
    return other.query("select public.begin_bank_sync_operation($1,$2,'suspend',repeat('a',64))",[randomUUID(),x.bank]);
   })());
   await blocked(observer,await pid(other),await pid(preparing));await preparing.query('commit');
   await assert.rejects(outcome(waiting),e=>e.message===(action==='delete'?'ORDER_HAS_REFUND_HISTORY':'BANK_ACCOUNT_HAS_PENDING_REFUND'));await other.query('rollback');
   assert.equal((await observer.query('select count(*)::int n from eshop.orders where id=$1',[x.order])).rows[0].n,1);
  }finally{await close(other,preparing,observer);}
 });
}
