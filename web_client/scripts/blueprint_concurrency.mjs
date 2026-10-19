import pg from 'pg';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
const url=new URL(process.env.BLUEPRINT_DATABASE_URL??'');
assert(['127.0.0.1','localhost'].includes(url.hostname),'task disposable localhost required');
const clients=[new pg.Client({connectionString:url.href}),new pg.Client({connectionString:url.href})];
const [a,b]=clients; let checks=0;
try {
 await Promise.all(clients.map(c=>c.connect()));
 const marker=(await a.query('select project from festapp_test_support.disposable_environment')).rows[0]?.project;
 assert(
  (marker==='festapp-blueprint-b-20261019' && url.port==='59432') ||
  (marker==='festapp-blueprint-b-e2e-20261019' && url.port==='59522'),
  'owned task database marker and port');
 await a.query(readFileSync(new URL('../../database/tests/blueprint/fixtures.sql',import.meta.url),'utf8'));
 const fixture=async()=>{
  const f=(await a.query('select public.blueprint_test_fixture_internal() f')).rows[0].f;
  for(const c of clients)await c.query("select set_config('request.jwt.claim.sub',$1,false)",[f.actor]);
  const saved=(await a.query('select public.update_blueprint_client_sync_v1($1,$2) r',[f.request,randomUUID()])).rows[0].r;
  assert.equal(saved.status,'applied'); f.bindings=saved.data.seatBindings;
  f.request.expected_layout_revision=1;
  f.request.seatChanges=f.request.seatChanges.map(c=>({...c,spotId:f.bindings.find(x=>x.nodeId===c.nodeId).spotId}));
  return f;
 };
 const ensureBank=async f=>{
  const account=(await a.query("insert into eshop.bank_accounts(title,type,supported_currencies) values('Synthetic blueprint concurrency','FIO',array['CZK']) returning id")).rows[0].id;
  await a.query('insert into eshop.unit_bank_accounts(unit,bank_account) select unit,$1 from public.occasions where id=$2',[account,f.occasion]);
 };
 const assign=async f=>{
  const order=(await a.query('select public.allocate_ticket_order_identity_internal($1) id',[f.form])).rows[0].id;
  const ticket=(await a.query("insert into eshop.tickets(occasion,state) values($1,'ordered') returning id",[f.occasion])).rows[0].id;
  const opt=(await a.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3) returning id',[order,ticket,f.product])).rows[0].id;
  await a.query(`update eshop.orders set state='ordered',price=100,data=jsonb_build_object('email','blueprint@example.invalid','tickets',jsonb_build_array(jsonb_build_object('id',$2::bigint,'products',jsonb_build_array(public._swap_spots_generate_product_json($3,$4))))) where id=$1`,[order,ticket,f.product,f.bindings[0].spotId]);
  await a.query('update eshop.spots set order_product_ticket=$1 where id=$2',[opt,f.bindings[0].spotId]);
  return {order,ticket,opt};
 };
 // Observe the real PostgreSQL blocker instead of assuming timing from sleeps.
 async function blockedThenCommit(start,verify){
  const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
  let done=false; const pending=start().then(r=>{done=true;return r;});
  let observed=false;
  for(let i=0;i<100;i++){
   const blocked=(await a.query('select pg_blocking_pids($1) blockers',[pid])).rows[0].blockers;
   if(blocked.length){observed=true;break;}
   if(done)break;
   await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert(observed,'second connection must visibly wait on first connection');
  await a.query('commit'); const result=await pending; await verify(result);checks++;
 }
 // Distinct commands with the same revision are serialized and second rejected.
 {
  const f=await fixture(); await a.query('begin');
  const first=(await a.query('select public.update_blueprint_client_sync_v1($1,$2) r',[f.request,randomUUID()])).rows[0].r;
  assert.equal(first.status,'applied');
  await blockedThenCommit(()=>b.query('select public.update_blueprint_client_sync_v1($1,$2) r',[f.request,randomUUID()]),r=>assert.equal(r.rows[0].r.data.reason,'BLUEPRINT_REVISION_CONFLICT'));
 }
 // A hold won before the editor's save: protected metadata cannot be overwritten.
 {
  const f=await fixture();await a.query('begin');
  const r=(await a.query('select public.select_spot($1,$2,$3,true) r',[f.formKey,randomUUID(),f.bindings[0].spotId])).rows[0].r;assert.equal(r.code,200);
  f.request.seatChanges.find(c=>c.spotId===f.bindings[0].spotId).title='race edit';
  await blockedThenCommit(()=>b.query('select public.update_blueprint_client_sync_v1($1,$2) r',[f.request,randomUUID()]),r=>assert.equal(r.rows[0].r.data.reason,'BLUEPRINT_SEAT_PROTECTED'));
 }
 // A save marking blocked won: the waiting buyer cannot hold it afterward.
 {
  const f=await fixture();await a.query('begin');
  f.request.seatChanges.find(c=>c.spotId===f.bindings[0].spotId).blocked=true;
  await a.query('select public.update_blueprint_client_sync_v1($1,$2)',[f.request,randomUUID()]);
  await blockedThenCommit(()=>b.query('select public.select_spot($1,$2,$3,true) r',[f.formKey,randomUUID(),f.bindings[0].spotId]),r=>assert.equal(r.rows[0].r.reason,'BLUEPRINT_SEAT_UNAVAILABLE'));
 }
 // Reverse swaps use the same scope and deterministic row lock ordering.
 {
  const f=await fixture();await a.query('begin');
  await a.query('select public.swap_spot_tickets_internal_v1($1,$2)',[f.bindings[0].spotId,f.bindings[1].spotId]);
  await blockedThenCommit(()=>b.query('select public.swap_spot_tickets_internal_v1($1,$2)',[f.bindings[1].spotId,f.bindings[0].spotId]),()=>{});
 }
 // Hold versus swap: swap rechecks the committed hold under the shared lock.
 {
  const f=await fixture();await a.query('begin');
  await a.query('select public.select_spot($1,$2,$3,true)',[f.formKey,randomUUID(),f.bindings[0].spotId]);
  await blockedThenCommit(()=>b.query('select public.preview_blueprint_swap($1,$2) r',[f.bindings[0].spotId,f.bindings[1].spotId]),r=>assert.equal(r.rows[0].r.reason,'BLUEPRINT_SEAT_PROTECTED'));
 }
 // Geometry save versus real finalization keeps the held physical identity.
 {
  const f=await fixture();await ensureBank(f);const secret=randomUUID();
  await a.query('select public.select_spot($1,$2,$3,true)',[f.formKey,secret,f.bindings[0].spotId]);
  const target=(await a.query('select public.allocate_ticket_order_identity_internal($1) id',[f.form])).rows[0].id;
  await a.query('begin');f.request.layout.canvas.width+=1;
  await a.query('select public.update_blueprint_client_sync_v1($1,$2)',[f.request,randomUUID()]);
  const input={form:f.formKey,email:'blueprint@example.invalid',secret,ticket:[{spot:f.bindings[0].spotId,fields:[]}]};
  await blockedThenCommit(()=>b.query('select public.finalize_ticket_order_internal_v1($1,$2,false) r',[target,input]),r=>assert.equal(r.rows[0].r.code,200,JSON.stringify(r.rows[0].r)));
 }
 // Geometry save versus the existing cancellation owner releases the same spot.
 {
  const f=await fixture();const assigned=await assign(f);await a.query('begin');f.request.layout.canvas.width+=1;
  await a.query('select public.update_blueprint_client_sync_v1($1,$2)',[f.request,randomUUID()]);
  await blockedThenCommit(()=>b.query('select public.internal_storno_tickets_221($1)',[[assigned.ticket]]),async()=>{
   assert.equal((await b.query('select state from eshop.tickets where id=$1',[assigned.ticket])).rows[0].state,'storno');
   assert.equal((await b.query('select order_product_ticket from eshop.spots where id=$1',[f.bindings[0].spotId])).rows[0].order_product_ticket,null);
  });
 }
 // A replacement failure after cancellation restores the complete old order.
 {
  const f=await fixture();const assigned=await assign(f);await a.query('begin');f.request.layout.canvas.width+=1;
  await a.query('select public.update_blueprint_client_sync_v1($1,$2)',[f.request,randomUUID()]);
  // No bank account exists, so the existing finalizer rejects after preparation.
  await blockedThenCommit(()=>b.query('select public.replace_blueprint_order_client_sync_v1($1,$2,$3) r',[[f.bindings[0].spotId],{email:'blueprint@example.invalid'},randomUUID()]),async r=>{
   assert.equal(r.rows[0].r.status,'rejected');
   assert.equal((await b.query('select state from eshop.tickets where id=$1',[assigned.ticket])).rows[0].state,'ordered');
   assert.equal((await b.query('select order_product_ticket from eshop.spots where id=$1',[f.bindings[0].spotId])).rows[0].order_product_ticket,assigned.opt);
  });
 }
 // Distinct buyers cannot both consume the last product maximum while waiting
 // on the existing occasion/hold authority. The rejected spot remains untouched.
 {
  const f=await fixture(),firstSecret=randomUUID(),secondSecret=randomUUID();
  await a.query('update eshop.products set maximum=1 where id=$1',[f.product]);
  await a.query('begin');
  const first=(await a.query('select public.select_spot($1,$2,$3,true) r',[f.formKey,firstSecret,f.bindings[0].spotId])).rows[0].r;
  assert.equal(first.code,200);
  await blockedThenCommit(()=>b.query('select public.select_spot($1,$2,$3,true) r',[f.formKey,secondSecret,f.bindings[1].spotId]),async r=>{
   assert.equal(r.rows[0].r.reason,'PRODUCT_CAPACITY_EXCEEDED');
   const spots=(await b.query('select id,secret from eshop.spots where id=any($1::bigint[]) order by id',[[f.bindings[0].spotId,f.bindings[1].spotId]])).rows;
   assert.equal(spots.find(s=>String(s.id)===String(f.bindings[0].spotId)).secret,firstSecret);
   assert.equal(spots.find(s=>String(s.id)===String(f.bindings[1].spotId)).secret,null);
  });
 }
 console.log(`PASS ${checks} deterministic two-connection blueprint races; database=${marker}`);
}finally{
 await Promise.allSettled(clients.map(async c=>{await c.query('rollback');await c.end();}));
}
