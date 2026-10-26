// A committed waitlist ticket is a real finalization/cancellation target;
// an ordinary checkout's newly inserted ticket is invisible before commit.
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const pg=require('pg');
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {readFileSync} from 'node:fs';
const url=new URL(process.env.BLUEPRINT_DATABASE_URL??'');
assert.equal(url.hostname,'127.0.0.1');assert(['59722','59822'].includes(url.port));
const a=new pg.Client({connectionString:url.href}),b=new pg.Client({connectionString:url.href});
let checks=0;
try{
 await Promise.all([a.connect(),b.connect()]);
 const marker=(await a.query('select project from festapp_test_support.disposable_environment where singleton')).rows[0].project;
 assert.equal(marker,url.port==='59822'?'festapp-blueprint-1000-fresh-20261020':'festapp-blueprint-1000-e2e-20261020');
 for(const c of [a,b])await c.query("set statement_timeout='10s';set lock_timeout='5s'");
 await a.query(readFileSync(new URL('../blueprint/fixtures.sql',import.meta.url),'utf8'));
 const lifecycle=readFileSync(new URL('../eshop_orders/waitlist_lifecycle_test.sql',import.meta.url),'utf8').replaceAll('regression@example.invalid',`waitlist-${randomUUID()}@example.invalid`);
 await a.query(lifecycle.slice(0,lifecycle.indexOf('\nDO $$')).replace(/^BEGIN;$/m,''));
 await a.query("select set_config('request.jwt.claim.role','service_role',false)");
 const fixture=async()=>{
  const f=(await a.query('select public.blueprint_test_fixture_internal() f')).rows[0].f;
  for(const c of [a,b])await c.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','service_role',false)",[f.actor]);
  const saved=(await a.query('select public.update_blueprint_client_sync_v1($1,$2) r',[f.request,randomUUID()])).rows[0].r;assert.equal(saved.status,'applied');
  f.spot=saved.data.seatBindings[0].spotId;
  await a.query('update public.forms set participant_capacity=1,waitlist_enabled=true,waitlist_offer_duration_seconds=3600 where id=$1',[f.form]);
  const bank=(await a.query("insert into eshop.bank_accounts(title,type,supported_currencies) values('Waitlist race bank','FIO',array['CZK']) returning id")).rows[0].id;
  await a.query('insert into eshop.unit_bank_accounts(unit,bank_account) select unit,$1 from public.occasions where id=$2',[bank,f.occasion]);
  const x={...f,key:f.formKey};
  const filled=(await a.query('select public.create_ticket_order_internal_v1(pg_temp.checkout($1)) r',[x])).rows[0].r;assert.equal(filled.code,200,JSON.stringify(filled));
  const registration=(await a.query('select pg_temp.register($1,1) r',[x])).rows[0].r;
  f.order=registration.order;
  await a.query('select public.storno_order_client_sync_v1($1,$2)',[filled.order.id,randomUUID()]);
  const token=randomBytes(32).toString('hex');
  f.offer=(await a.query('select pg_temp.offer($1,$2,1,$3) r',[x,f.order,token])).rows[0].r.id;
  f.ticket=(await a.query('select ticket from eshop.order_product_ticket where "order"=$1',[f.order])).rows[0].ticket;
  f.input={offerId:f.offer,ticketIds:[f.ticket],orderDetails:{form:f.formKey,email:`waitlist-race-${f.occasion}@example.invalid`,ticket:[{ticketId:f.ticket,spot:f.spot,fields:[]}]}};
  return f;
 };
 const f=await fixture();
 await a.query('begin');
 const accepted=(await a.query("select public.execute_waitlist_command_client_sync_v1('accept',$1,$2,$3,$4) r",[f.input,randomUUID(),randomUUID(),f.actor])).rows[0].r;
 assert.equal(accepted.status,'applied',JSON.stringify(accepted));
 const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 let done=false;
 const cancellation=b.query('select public.storno_order_client_sync_v1($1,$2) r',[f.order,randomUUID()]).then(r=>{done=true;return r;});
 let waiting=false;
 for(let i=0;i<100;i++){
  const blockers=(await a.query('select pg_blocking_pids($1) blockers',[pid])).rows[0].blockers;
  if(blockers.length){waiting=true;break;}if(done)break;
  await new Promise(resolve=>setTimeout(resolve,10));
 }
 assert(waiting,'cancellation must wait on the real acceptance transaction');
 await a.query('commit');
 const cancelled=(await cancellation).rows[0].r;assert.equal(cancelled.status,'applied',JSON.stringify(cancelled));
 const state=(await b.query('select o.state order_state,t.state ticket_state,s.order_product_ticket,s.secret from eshop.orders o join eshop.tickets t on t.id=$2 join eshop.spots s on s.id=$3 where o.id=$1',[f.order,f.ticket,f.spot])).rows[0];
 assert.deepEqual(state,{order_state:'storno',ticket_state:'storno',order_product_ticket:null,secret:null});checks++;
 // Offer cancellation is the legal cancellation owner while a committed
 // ticket is waitlisted; ordinary ticket cancellation explicitly rejects it.
 {
  const pending=await fixture();await a.query('begin');
  const cancelled=(await a.query("select public.execute_waitlist_command_client_sync_v1('cancel',$1,$2,$3,$4) r",[{offerId:pending.offer,ticketIds:[pending.ticket]},randomUUID(),randomUUID(),pending.actor])).rows[0].r;
  assert.equal(cancelled.status,'applied',JSON.stringify(cancelled));
  const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
  let done=false;
  const acceptance=b.query("select public.execute_waitlist_command_client_sync_v1('accept',$1,$2,$3,$4) r",[pending.input,randomUUID(),randomUUID(),pending.actor]).then(r=>{done=true;return r;});
  let waiting=false;
  for(let i=0;i<100;i++){
   if((await a.query('select pg_blocking_pids($1) blockers',[pid])).rows[0].blockers.length){waiting=true;break;}if(done)break;
   await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert(waiting,'acceptance waits for committed offer cancellation');await a.query('commit');
  const rejected=(await acceptance).rows[0].r;assert.equal(rejected.status,'rejected',JSON.stringify(rejected));
  const state=(await b.query('select o.state order_state,t.state ticket_state,s.order_product_ticket,s.secret from eshop.orders o join eshop.tickets t on t.id=$2 join eshop.spots s on s.id=$3 where o.id=$1',[pending.order,pending.ticket,pending.spot])).rows[0];
  assert.deepEqual(state,{order_state:'waitlisted',ticket_state:'waitlisted',order_product_ticket:null,secret:null});
  assert.equal((await b.query('select count(*)::int n from eshop.payment_info p join eshop.orders o on o.payment_info=p.id where o.id=$1',[pending.order])).rows[0].n,0);checks++;
 }
 console.log(`PASS ${checks} actual waitlist finalize/cancellation barriers; database=${marker}`);
}finally{await Promise.allSettled([a,b].map(async c=>{await c.query('rollback');await c.end();}));}
