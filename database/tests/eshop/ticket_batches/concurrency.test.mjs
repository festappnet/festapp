import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
if(!connectionString||new URL(connectionString).hostname!=='127.0.0.1'||new URL(connectionString).port!=='55432')throw new Error('Use disposable DB 127.0.0.1:55432 only');
async function connect(){const c=new Client({connectionString});await c.connect();await c.query("SET statement_timeout='15s'");return c;}
const source=readFileSync(new URL('./foundation_test.sql',import.meta.url),'utf8');
const fixtureSql=source.slice(source.indexOf('CREATE FUNCTION pg_temp.fixture'),source.indexOf('DO $$'));
const layout=JSON.parse(readFileSync(new URL('../../../../test/fixtures/ticket_layout/layouts.json',import.meta.url))).valid[0];
for(const t of Object.values(layout.templates))t.elements=t.elements.filter(e=>e.binding!=='productType');
async function fixture(c,capacity=10,ready=true){
 await c.query('BEGIN');await c.query(fixtureSql);
 const {rows:[{x}]}=await c.query('SELECT pg_temp.fixture($1) x',[capacity]);
 await c.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[x.unit,x.actor]);
 await c.query('UPDATE public.occasions SET features=$1::jsonb WHERE id=$2',[JSON.stringify([{code:'ticket',is_enabled:true,ticket_type:'wide',layout}]),x.occasion]);
 const selection=Array.from({length:capacity},()=>({fields:[{product_type:x.product}]}));
 const {rows:[{r}]}=await c.query('SELECT public.create_ticket_batch_client_sync_v1($1,$2,$3::jsonb,NULL,$4) r',[x.form,'Concurrent batch',JSON.stringify(selection),randomUUID()]);
 x.batch=r.data.batchId;x.order=r.data.stockOrderId;
 const {rows}=await c.query('SELECT ticket_id FROM eshop.ticket_batch_items WHERE batch_id=$1 ORDER BY ordinal',[x.batch]);x.tickets=rows.map(r=>Number(r.ticket_id));
 if(ready){
  const {rows:[{claim}]}=await c.query('SELECT public.claim_ticket_batch_document($1) claim',[x.batch]);
  await c.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
  await c.query('SELECT public.complete_ticket_batch_resources_internal($1,$2,$3,20)',[x.batch,claim.lease,{test:'sealed'}]);
  const {rows:parts}=await c.query('SELECT id,cardinality(ticket_ids) n FROM eshop.ticket_batch_document_parts WHERE batch_id=$1',[x.batch]);
  for(const part of parts){const {rows:[{claim:p}]}=await c.query('SELECT public.claim_ticket_batch_document($1,$2) claim',[x.batch,part.id]);await c.query('SELECT public.complete_ticket_batch_document_internal($1,$2,$3,100,$4)',[part.id,p.lease,'a'.repeat(64),part.n]);}
 }
 await c.query('COMMIT');return x;
}
async function transact(c,x,query,params){
 await c.query('BEGIN');
 try{await c.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[x.actor]);const r=await c.query(query,params);await c.query('COMMIT');return {ok:true,value:r.rows[0]};}
 catch(error){await c.query('ROLLBACK');return {ok:false,error};}
}
for(const other of ['sale','void','scan'])test(`batch sale racing ${other} preserves a single atomic ticket owner/payment`,async()=>{
 const setup=await connect(),a=await connect(),b=await connect();
 try{
  const x=await fixture(setup);const tid=x.tickets[0];
  const sell='SELECT public.sell_ticket_batch_items_client_sync_v1($1,$2,$3,false,$4) r';
  const results=await Promise.all([
   transact(a,x,sell,[x.batch,[tid],{},randomUUID()]),
   other==='sale'?transact(b,x,sell,[x.batch,[tid],{},randomUUID()]):other==='void'
    ?transact(b,x,'SELECT public.void_ticket_batch_items_client_sync_v1($1,$2,$3,$4) r',[x.batch,[tid],'Concurrent void',randomUUID()])
    :transact(b,x,'SELECT public.scanner_admit_ticket_internal($1) r',[tid])
  ]);
  const {rows:[r]}=await setup.query(`SELECT t.state,i.sale_order_id,
   (SELECT count(*)::int FROM eshop.transactions tr JOIN eshop.orders o ON o.payment_info=tr.payment_info WHERE o.id=i.sale_order_id) payments,
   (SELECT count(DISTINCT "order")::int FROM eshop.order_product_ticket WHERE ticket=t.id) parents
   FROM eshop.tickets t JOIN eshop.ticket_batch_items i ON i.ticket_id=t.id WHERE t.id=$1`,[tid]);
  assert.equal(r.parents,1);assert.equal(r.payments,r.sale_order_id?1:0);
  if(other!=='scan')assert.equal(results.filter(r=>r.ok&&r.value.r?.code===200).length,1);
  else {assert.equal(results[0].ok,true);assert.ok(['paid','used'].includes(r.state));}
  for(const result of results.filter(r=>!r.ok))assert.match(result.error.message,/ITEM_NOT_IN_STOCK|ORDER_ACTION_NOT_ALLOWED|ticket_parent_changed/);
 }finally{await Promise.all([setup,a,b].map(c=>c.end()));}
});

test('Blueprint batch holds seats atomically, preserves physical assignments and rejects printed-seat replacement',async()=>{
 const c=await connect();
 try {
  await c.query('BEGIN');await c.query(fixtureSql);
  const {rows:[{x}]}=await c.query('SELECT pg_temp.fixture(NULL) x');
  await c.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[x.unit,x.actor]);
  await c.query('UPDATE public.occasions SET features=$1::jsonb WHERE id=$2',[JSON.stringify([{code:'ticket',is_enabled:true,ticket_type:'wide',layout},{code:'blueprint',is_enabled:true}]),x.occasion]);
  const {rows:[bp]}=await c.query(`INSERT INTO eshop.blueprints(occasion,organization,title,groups,objects)
   VALUES($1,$2,'Printed seats','[{"id":1,"title":"A"}]','[]') RETURNING id`,[x.occasion,x.organization]);
  await c.query('UPDATE public.forms SET blueprint=$1 WHERE id=$2',[bp.id,x.form]);
  const {rows:[pool]}=await c.query("INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES($1,'Physical seats','accommodation',2) RETURNING id",[x.occasion]);
  const {rows:[ctx]}=await c.query("INSERT INTO public.inventory_contexts(inventory_pool,title,block_date) VALUES($1,'Seat session',current_date) RETURNING id",[pool.id]);
  const {rows:[resource]}=await c.query("INSERT INTO public.resources(occasion,inventory_pool,title,capacity) VALUES($1,$2,'Physical table',2) RETURNING id",[x.occasion,pool.id]);
  const {rows:seats}=await c.query("INSERT INTO eshop.spots(occasion,blueprint,product,title,inventory_context,resource) VALUES($1,$2,$3,'A1',$4,$5),($1,$2,$3,'A2',$4,$5) RETURNING id",[x.occasion,bp.id,x.product,ctx.id,resource.id]);
  await c.query('UPDATE eshop.blueprints SET objects=$1 WHERE id=$2',[JSON.stringify(seats.map(s=>({id:Number(s.id),type:'spot',group:1}))),bp.id]);
  const {rows:[{r}]}=await c.query('SELECT public.create_ticket_batch_client_sync_v1($1,$2,$3::jsonb,$4,$5) r',[x.form,'Printed table A',JSON.stringify(seats.map(s=>({spot:Number(s.id)}))),randomUUID(),randomUUID()]);
  assert.equal(r.code,200);x.batch=r.data.batchId;
  const {rows:before}=await c.query('SELECT id,order_product_ticket,resource,resource_slot,inventory_context FROM eshop.spots WHERE id=ANY($1) ORDER BY id',[seats.map(s=>s.id)]);
  assert.ok(before.every(s=>s.order_product_ticket&&s.resource===resource.id));
  await c.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
  const {rows:[{claim}]}=await c.query('SELECT public.claim_ticket_batch_document($1) claim',[x.batch]);
  await c.query('SELECT public.complete_ticket_batch_resources_internal($1,$2,$3,20)',[x.batch,claim.lease,{test:'sealed'}]);
  const {rows:parts}=await c.query('SELECT id,cardinality(ticket_ids) n FROM eshop.ticket_batch_document_parts WHERE batch_id=$1',[x.batch]);
  for(const part of parts){const {rows:[{claim:p}]}=await c.query('SELECT public.claim_ticket_batch_document($1,$2) claim',[x.batch,part.id]);await c.query('SELECT public.complete_ticket_batch_document_internal($1,$2,$3,100,$4)',[part.id,p.lease,'a'.repeat(64),part.n]);}
  const {rows:[{ids}]}=await c.query('SELECT array_agg(ticket_id) ids FROM eshop.ticket_batch_items WHERE batch_id=$1',[x.batch]);
  const {rows:[{sale}]}=await c.query('SELECT public.sell_ticket_batch_items_client_sync_v1($1,$2,$3,false,$4) sale',[x.batch,ids,{},randomUUID()]);assert.equal(sale.code,200);
  assert.deepEqual((await c.query('SELECT id,order_product_ticket,resource,resource_slot,inventory_context FROM eshop.spots WHERE id=ANY($1) ORDER BY id',[seats.map(s=>s.id)])).rows,before);
  async function rejectsPrinted(query,params){await c.query('SAVEPOINT printed_guard');let rejection;try{const r=await c.query(query,params);rejection=Object.values(r.rows[0])[0];}catch(e){rejection=e;}await c.query('ROLLBACK TO SAVEPOINT printed_guard');assert.match(rejection?.message??'',/BATCH_TICKET_PRINT_IMMUTABLE/);if(rejection.success!==undefined)assert.equal(rejection.success,false);}
  await rejectsPrinted('SELECT public.confirm_blueprint_order_change_internal_v1($1,$2)',[seats.map(s=>s.id),{email:'fixture@example.invalid'}]);
  await rejectsPrinted('SELECT public.update_blueprint_internal_v1($1)',[{id:bp.id,occasion:x.occasion,organization:x.organization,groups:[{id:1,title:'Relabeled table'}]}]);
  await rejectsPrinted('SELECT public.update_product_inventory_contexts_internal_v1($1,$2)',[x.product,JSON.stringify([{inventory_context_id:Number(ctx.id),quantity:1}])]);
 } finally {await c.query('ROLLBACK');await c.end();}
});
