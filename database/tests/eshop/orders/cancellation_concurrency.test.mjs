import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
const require=createRequire(new URL('../../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
if (!connectionString || new URL(connectionString).hostname!=='127.0.0.1' || new URL(connectionString).port!=='55432')
  throw new Error('Use only the disposable Festapp test DB on 127.0.0.1:55432');
async function connect(){const c=new Client({connectionString});await c.connect();await c.query("SET statement_timeout='15s'");return c;}

test('whole-order and final-ticket cancellation commit one history and automatic notice',async()=>{
 const setup=await connect();const clients=await Promise.all([connect(),connect()]);
 const actor=randomUUID(); const commands=[randomUUID(),randomUUID()];let fixture;
 try {
  await setup.query('BEGIN');
  await setup.query(`INSERT INTO auth.users(id,email) VALUES($1,$2);
  `,[actor,`${actor}@example.invalid`]);
  await setup.query('INSERT INTO public.user_info(id,email_readonly) VALUES($1,$2)',[actor,`${actor}@example.invalid`]);
  ({rows:[fixture]}=await setup.query(`WITH org AS(INSERT INTO public.organizations(title) VALUES('Cancellation concurrency') RETURNING id),
   un AS(INSERT INTO public.units(title,organization) SELECT 'Cancellation concurrency',id FROM org RETURNING id,organization),
   oc AS(INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) SELECT 'Cancellation concurrency',organization,id,$1,now(),now()+interval '1 day' FROM un RETURNING id,organization,unit)
   SELECT * FROM oc`,[randomUUID()]));
  await setup.query('UPDATE public.user_info SET organization=$1 WHERE id=$2',[fixture.organization,actor]);
  await setup.query('INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES($1,$2,true,true)',[fixture.unit,actor]);
  await setup.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES($1,$2,true)',[fixture.id,actor]);
  const {rows:[o]}=await setup.query(`INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data) VALUES(public.next_order_sequence($1),public.generate_order_symbol(),$1,'ordered',jsonb_build_object('email',$2::text)) RETURNING id`,[fixture.id,`${actor}@example.invalid`]);fixture.order=o.id;
  const {rows:[t]}=await setup.query("INSERT INTO eshop.tickets(occasion,state) VALUES($1,'ordered') RETURNING id",[fixture.id]);fixture.ticket=t.id;
  await setup.query('INSERT INTO eshop.order_product_ticket("order",ticket) VALUES($1,$2)',[o.id,t.id]);
  assert.equal((await setup.query('SELECT worker_url FROM public.email_capacity')).rows.every(r=>r.worker_url===null),true,'fixture must not wake any provider');
  await setup.query('COMMIT');
  const results=await Promise.all(clients.map(async(c,i)=>{
   await c.query('BEGIN');
   await c.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[actor]);
   await c.query('SET LOCAL ROLE authenticated');
   const {rows:[r]}=i===0
    ?await c.query('SELECT public.storno_order_client_sync_v1($1,$2) AS result',[o.id,commands[i]])
    :await c.query('SELECT public.storno_tickets_client_sync_v1($1,$2) AS result',[[t.id],commands[i]]);
   await c.query('COMMIT'); return r.result;
  }));
  assert.ok(results.every(r=>r.code===200));
  const {rows:[counts]}=await setup.query(`SELECT
   (SELECT count(*)::int FROM eshop.orders_history WHERE "order"=$1 AND state='storno') AS history,
   (SELECT count(*)::int FROM public.email_messages WHERE order_id=$1 AND message_kind='order_storno') AS notices,
   (SELECT count(*)::int FROM public.client_mutation_receipts WHERE command_id=ANY($2::uuid[]) AND status='completed') AS receipts`,[o.id,commands]);
  assert.deepEqual(counts,{history:1,notices:1,receipts:2});
 } finally {
  await Promise.all(clients.map(async c=>{await c.query('ROLLBACK');await c.end();}));
  await setup.query('ROLLBACK');
  // Everything is synthetic in this disposable DB. Retain receipts as evidence.
  await setup.end();
 }
});

async function authoringFixture(c) {
 const actor=randomUUID();
 await c.query('INSERT INTO auth.users(id,email) VALUES($1,$2)',[actor,`${actor}@example.invalid`]);
 await c.query('INSERT INTO public.user_info(id,email_readonly) VALUES($1,$2)',[actor,`${actor}@example.invalid`]);
 const {rows:[f]}=await c.query(`WITH org AS(INSERT INTO public.organizations(title) VALUES('Authoring concurrency') RETURNING id),
  un AS(INSERT INTO public.units(title,organization) SELECT 'Authoring concurrency',id FROM org RETURNING id,organization),
  oc AS(INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) SELECT 'Authoring concurrency',organization,id,$1,now(),now()+interval '1 day' FROM un RETURNING id,organization,unit)
  SELECT * FROM oc`,[randomUUID()]);
 await c.query('UPDATE public.user_info SET organization=$1 WHERE id=$2',[f.organization,actor]);
 await c.query('INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,is_editor_order,is_editor_order_view) VALUES($1,$2,true,true,true,true)',[f.id,actor]);
 const {rows:[pt]}=await c.query("INSERT INTO eshop.product_types(occasion,title,type) VALUES($1,'Admission','spot') RETURNING id",[f.id]);
 const {rows:[p]}=await c.query("INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES($1,$2,'Admission',10,'CZK') RETURNING id",[f.id,pt.id]);
 return {...f,actor,product:p.id};
}
async function asActor(c,actor) {
 await c.query('BEGIN');
 await c.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[actor]);
 await c.query('SET LOCAL ROLE authenticated');
}

test('concurrent additions preserve both selected members and existing admin flags',async()=>{
 const setup=await connect(), clients=await Promise.all([connect(),connect()]);
 try {
  const f=await authoringFixture(setup), members=[randomUUID(),randomUUID()];
  for(const member of members) {
   await setup.query('INSERT INTO auth.users(id,email) VALUES($1,$2)',[member,`${member}@example.invalid`]);
   await setup.query('INSERT INTO public.user_info(id,organization) VALUES($1,$2)',[member,f.organization]);
   await setup.query('INSERT INTO public.occasion_users(occasion,"user") VALUES($1,$2)',[f.id,member]);
  }
  const {rows:[g]}=await setup.query("INSERT INTO public.user_group_info(occasion,title) VALUES($1,'Concurrent group') RETURNING id",[f.id]);
  await setup.query('INSERT INTO public.user_groups("group","user",is_admin) VALUES($1,$2,true)',[g.id,f.actor]);
  const results=await Promise.all(clients.map(async(c,i)=>{
   await asActor(c,f.actor);
   const {rows:[r]}=await c.query('SELECT public.add_user_group_members_client_sync_v1($1,$2,$3,$4) AS result',[f.id,g.id,[members[i]],randomUUID()]);
   await c.query('COMMIT');return r.result;
  }));
  assert.ok(results.every(r=>r.code===200));
  const {rows:[r]}=await setup.query('SELECT count(*)::int AS n,bool_and(is_admin) FILTER(WHERE "user"=$2) AS retained FROM public.user_groups WHERE "group"=$1',[g.id,f.actor]);
  assert.deepEqual(r,{n:3,retained:true});
 } finally {for(const c of clients){await c.query('ROLLBACK');await c.end();}await setup.end();}
});

test('simultaneous new wave targets converge on one wave and conflict on a stale target',async()=>{
 const setup=await connect(),clients=await Promise.all([connect(),connect()]);
 try {
  const f=await authoringFixture(setup);
  await setup.query('BEGIN');
  await setup.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[f.actor]);
  const {rows:[link]}=await setup.query("UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',$1,NULL,true) WHERE id=$1 RETURNING link",[f.id]);
  await setup.query('COMMIT');
  const target={occasion_link:link.link,product_id:Number(f.product),change_time:new Date(Date.now()+86400000).toISOString(),price:20,is_hidden:null,expected_price_revision:null,expected_visibility_revision:null};
  const results=await Promise.allSettled(clients.map(async c=>{
   await asActor(c,f.actor);
   try {const {rows:[r]}=await c.query('SELECT public.save_product_wave_target_client_sync_v1($1,$2) AS result',[target,randomUUID()]);await c.query('COMMIT');return r.result;}
   catch(e){await c.query('ROLLBACK');throw e;}
  }));
  assert.equal(results.filter(r=>r.status==='fulfilled' && r.value.code===200).length,1);
  assert.equal(results.filter(r=>r.status==='rejected' && r.reason.code==='40001').length,1);
  const {rows:[r]}=await setup.query('SELECT (SELECT count(*)::int FROM eshop.product_price_waves WHERE occasion=$1) AS waves,(SELECT count(*)::int FROM eshop.planned_changes WHERE occasion=$1) AS targets',[f.id]);
  assert.deepEqual(r,{waves:1,targets:1});
 } finally {for(const c of clients){await c.query('ROLLBACK');await c.end();}await setup.end();}
});

test('blueprint removal waits for a real hold and rechecks its committed allocation',async()=>{
 const setup=await connect(),holder=await connect(),editor=await connect();
 try {
  const f=await authoringFixture(setup);
  const {rows:[bp]}=await setup.query('INSERT INTO eshop.blueprints(occasion,organization,objects) VALUES($1,$2,\'[]\') RETURNING id',[f.id,f.organization]);
  const {rows:[seat]}=await setup.query("INSERT INTO eshop.spots(occasion,blueprint,product,title) VALUES($1,$2,$3,'Held seat') RETURNING id",[f.id,bp.id,f.product]);
  const {rows:[form]}=await setup.query("INSERT INTO public.forms(occasion,blueprint,is_open) VALUES($1,$2,true) RETURNING key",[f.id,bp.id]);
  await holder.query('BEGIN');await holder.query('SET LOCAL ROLE anon');
  const {rows:[held]}=await holder.query('SELECT public.select_spot($1,$2,$3,true) AS result',[form.key,randomUUID(),seat.id]);
  assert.equal(held.result.code,200);
  await asActor(editor,f.actor);
  const pid=(await editor.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
  const pending=editor.query('SELECT public.update_blueprint_client_sync_v1($1,$2) AS result',[
    {id:Number(bp.id),occasion:Number(f.id),organization:Number(f.organization),objects:[],expected_aggregate_version:0},randomUUID()]);
  let waiting=false;
  for(let i=0;i<100;i++) {
   waiting=(await setup.query("SELECT wait_event_type='Lock' AS waiting FROM pg_stat_activity WHERE pid=$1",[pid])).rows[0]?.waiting;
   if(waiting)break;await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert.equal(waiting,true,'editor must wait for the actual seat row lock');
  await holder.query('COMMIT');
  const {rows:[saved]}=await pending;
  assert.equal(saved.result.status,'rejected');
  assert.equal(JSON.stringify(saved.result).includes('secret'),false);
  await editor.query('COMMIT');
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM eshop.spots WHERE id=$1 AND secret IS NOT NULL',[seat.id])).rows[0].n,1);
 } finally {await holder.query('ROLLBACK');await editor.query('ROLLBACK');await Promise.all([holder.end(),editor.end(),setup.end()]);}
});

test('forward reassembly preserves Auth consumption and receipts and installs the authored bodies/ACL',async()=>{
 const c=await connect();
 try {
  const {readFile}=await import('node:fs/promises');
  const key=randomUUID().replaceAll('-','').repeat(2);
  await c.query("SELECT set_config('request.jwt.claim.role','service_role',false)");
  assert.equal((await c.query("SELECT public.consume_auth_abuse_v1('reset.account',$1) AS allowed",[key])).rows[0].allowed,true);
  const budgetSQL="SELECT sum(amount)::text AS used FROM public.abuse_budget_usage WHERE rule_key='reset.account' AND scope_id=public.abuse_recipient_key_v1($1)";
  const before=(await c.query(budgetSQL,[key])).rows[0];
  const receipt=(await c.query("SELECT command_id,actor_id,response,request_sha256 FROM public.client_mutation_receipts WHERE command_name='inventory.order.cancel' ORDER BY created_at LIMIT 1")).rows[0];
  assert.ok(receipt);
  const migration=await readFile(new URL('../../../../supabase/migrations/20261020120000_canonical_operations_foundation.sql',import.meta.url),'utf8');
  await c.query(migration);
  assert.deepEqual((await c.query(budgetSQL,[key])).rows[0],before,'definition assembly must never reset consumed budgets');
  assert.deepEqual((await c.query('SELECT command_id,actor_id,response,request_sha256 FROM public.client_mutation_receipts WHERE command_id=$1',[receipt.command_id])).rows[0],receipt);
  const manifest=JSON.parse(await readFile(new URL('../../../../automation/operations-foundation-sources.json',import.meta.url),'utf8'));
  const declarations=[];
  for(const source of manifest.sources) {
   const sql=await readFile(new URL(`../../../functions/${source}`,import.meta.url),'utf8');
   for(const m of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?(\w+)\s*\([\s\S]*?\bAS\s+(\$\w*\$)([\s\S]*?)\2/ig)) {
    declarations.push({name:m[1].toLowerCase(),body:m[3].trim(),definer:/SECURITY\s+DEFINER/i.test(m[0].slice(0,m[0].indexOf(m[2]))),source});
   }
  }
  assert.ok(declarations.length>150,'the full forward assembly must be checked');
  const names=[...new Set(declarations.map(d=>d.name))];
  const {rows:catalog}=await c.query("SELECT proname,prosrc,proconfig FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname=ANY($1::text[])",[names]);
  for(const d of declarations) {
   const matching=catalog.filter(r=>r.proname===d.name && r.prosrc.trim()===d.body);
   assert.ok(matching.length,`${d.source}: ${d.name} authored body must be installed`);
   if(d.definer)assert.ok(matching.every(r=>r.proconfig?.includes('search_path=public, extensions')),d.name);
  }
  const {rows:[acl]}=await c.query(`SELECT
   has_function_privilege('authenticated','public.delete_order_client_sync_v1(bigint,uuid)','EXECUTE') AS command,
   has_function_privilege('authenticated','public.update_inventory_pool_bundle_internal_v1(jsonb)','EXECUTE') AS pool,
   has_function_privilege('authenticated','public.report_cleaning_issue_internal_v1(bigint,text,text)','EXECUTE') AS cleaning,
   has_function_privilege('authenticated','public.consume_auth_abuse_v1(text,text)','EXECUTE') AS auth`);
  assert.deepEqual(acl,{command:true,pool:false,cleaning:false,auth:false});
 } finally {await c.end();}
});

test('cancellation and deletion preserve admission before order locking',async()=>{
 const setup=await connect(),deleting=await connect(),cancelling=await connect();
 try {
  const f=await authoringFixture(setup);
  await setup.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[f.unit,f.actor]);
  const {rows:[o]}=await setup.query("INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data) VALUES(public.next_order_sequence($1),public.generate_order_symbol(),$1,'ordered','{}') RETURNING id",[f.id]);
  await setup.query('BEGIN');await setup.query('SELECT 1 FROM public.email_capacity FOR UPDATE');
  await asActor(deleting,f.actor);await asActor(cancelling,f.actor);
  const dp=(await deleting.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const cp=(await cancelling.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  async function waitForLock(pid){for(let i=0;i<100;i++){
   if((await setup.query("SELECT wait_event_type='Lock' AS waiting FROM pg_stat_activity WHERE pid=$1",[pid])).rows[0]?.waiting)return;
   await new Promise(resolve=>setTimeout(resolve,10));
  }throw new Error('expected a controlled lock wait');}
  const deletion=deleting.query('SELECT public.delete_order_client_sync_v1($1,$2) AS result',[o.id,randomUUID()]);
  await waitForLock(dp); // owns admission, blocked at the outer queue capacity lock
  const cancellation=cancelling.query('SELECT public.storno_order_client_sync_v1($1,$2) AS result',[o.id,randomUUID()]);
  // Observe both promise outcomes immediately, including expected missing-row errors.
  const cancellationResult=cancellation.then(value=>({value}),error=>({error}));
  await waitForLock(cp);
  await setup.query('COMMIT');
  assert.equal((await deletion).rows[0].result.code,200);await deleting.query('COMMIT');
  const result=await cancellationResult;
  assert.notEqual(result.error?.code,'40P01','admission/order inversion must not deadlock');
  assert.notEqual(result.error?.code,'57014','wait must not time out');
  if(result.error) assert.ok(['P0001','42501','P0002'].includes(result.error.code),result.error.message);
  await cancelling.query('ROLLBACK');
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM eshop.orders WHERE id=$1',[o.id])).rows[0].n,0);
 } finally {
  await setup.query('ROLLBACK');await deleting.query('ROLLBACK');await cancelling.query('ROLLBACK');
  await Promise.all([setup.end(),deleting.end(),cancelling.end()]);
 }
});

async function versionedFormFixture(c,f) {
 const {rows:[p]}=await c.query('SELECT product_type FROM eshop.products WHERE id=$1',[f.product]);
 const link=randomUUID();
 const {rows:[form]}=await c.query('INSERT INTO public.forms(occasion,title,link) VALUES($1,$2,$3) RETURNING id',[f.id,'Original form',link]);
 await c.query("SELECT public.reserve_public_link_internal('form',$1,$2,true)",[form.id,link]);
 const {rows:[field]}=await c.query("INSERT INTO public.form_fields(form,type,title,product_type) VALUES($1,'product_type','Admission',$2) RETURNING id",[form.id,p.product_type]);
 return {id:Number(form.id),occasion:Number(f.id),link,title:'Form save',expected_aggregate_version:0,
  expected_product_versions:{[f.product]:0},expected_product_type_versions:{[p.product_type]:0},
  form_fields:[{id:Number(field.id),type:'product_type',title:'Admission',product_type:{id:Number(p.product_type),title:'Admission',type:'spot',
   products:[{id:Number(f.product),title:'From form',price:10,currency_code:'CZK',is_hidden:false}]}}]};
}
async function expectDatabaseLock(observer,pid) {
 for(let i=0;i<100;i++) {
  if((await observer.query("SELECT wait_event_type='Lock' AS waiting FROM pg_stat_activity WHERE pid=$1",[pid])).rows[0]?.waiting)return;
  await new Promise(resolve=>setTimeout(resolve,10));
 }
 throw new Error('expected the actual authoring command to wait on its parent row');
}
test('two original product snapshots produce one save and one conflict',async()=>{
 const setup=await connect(),clients=await Promise.all([connect(),connect()]);
 try {
  const f=await authoringFixture(setup);
  const results=await Promise.all(clients.map(async(c,index)=>{
   await asActor(c,f.actor);
   const {rows:[r]}=await c.query('SELECT public.update_product_client_sync_v1($1,$2) AS result',[
    {id:Number(f.product),title:`Editor ${index}`,expected_aggregate_version:0},randomUUID()]);
   await c.query('COMMIT');return r.result;
  }));
  assert.deepEqual(results.map(r=>r.status).sort(),['applied','conflict']);
  assert.equal(results.find(r=>r.status==='applied').data.aggregate_version,1);
 } finally {for(const c of clients){await c.query('ROLLBACK');await c.end();}await setup.end();}
});
for(const first of ['product','form'])test(`${first} save invalidates the competing editor after its real product-lock wait`,async()=>{
 const setup=await connect(),writer=await connect(),waiter=await connect();
 try {
  const f=await authoringFixture(setup),form=await versionedFormFixture(setup,f);
  await asActor(writer,f.actor);
  const product={id:Number(f.product),title:'From product',expected_aggregate_version:0};
  const run=(c,kind)=>c.query(`SELECT public.${kind==='product'?'update_product':'update_form'}_client_sync_v1($1,$2) AS result`,[kind==='product'?product:form,randomUUID()]);
  assert.equal((await run(writer,first)).rows[0].result.status,'applied');
  await asActor(waiter,f.actor);
  const pid=(await waiter.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const other=first==='product'?'form':'product';
  const pending=run(waiter,other);
  await expectDatabaseLock(setup,pid);
  await writer.query('COMMIT');
  const result=(await pending).rows[0].result;
  assert.equal(result.status,'conflict');await waiter.query('COMMIT');
  assert.equal((await setup.query('SELECT title FROM eshop.products WHERE id=$1',[f.product])).rows[0].title,first==='product'?'From product':'From form');
  assert.equal((await setup.query('SELECT title FROM public.forms WHERE id=$1',[form.id])).rows[0].title,first==='product'?'Original form':'Form save');
 } finally {await writer.query('ROLLBACK');await waiter.query('ROLLBACK');await Promise.all([setup.end(),writer.end(),waiter.end()]);}
});
test('pool reconciliation rejects a link phantom and resumes the same command without a pool/product deadlock',async()=>{
 const setup=await connect(),editor=await connect();
 try {
  const f=await authoringFixture(setup);
  const {rows:[p]}=await setup.query("INSERT INTO public.inventory_pools(occasion,title) VALUES($1,'Original pool') RETURNING id",[f.id]);
  const {rows:[ic]}=await setup.query("INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES($1,'Context') RETURNING id",[p.id]);
  const {rows:[other]}=await setup.query("INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) SELECT occasion,product_type,'Other',10,'CZK' FROM eshop.products WHERE id=$1 RETURNING id",[f.product]);
  await setup.query('INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES($1,$2,1)',[f.product,ic.id]);
  await setup.query('BEGIN');await setup.query('SELECT 1 FROM public.inventory_pools WHERE id=$1 FOR UPDATE',[p.id]);
  await asActor(editor,f.actor);const pid=(await editor.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const command=randomUUID(),bundle={pool:{id:Number(p.id),occasion:Number(f.id),title:'Pool changed'},contexts:[]};
  const pending=editor.query('SELECT public.save_inventory_pool_client_sync_v1($1,$2,0,$3) AS result',[f.id,command,bundle]).then(r=>({r}),error=>({error}));
  await expectDatabaseLock(setup,pid);
  await setup.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);
  await setup.query('SELECT public.update_product_inventory_contexts_client_sync_v1($1,$2,$3)',[other.id,JSON.stringify([{inventory_context_id:Number(ic.id),quantity:1}]),randomUUID()]);
  await setup.query('COMMIT');
  const blocked=await pending;assert.equal(blocked.error?.code,'40001');await editor.query('ROLLBACK');
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM public.client_mutation_receipts WHERE command_id=$1',[command])).rows[0].n,0);
  assert.equal((await setup.query('SELECT title FROM public.inventory_pools WHERE id=$1',[p.id])).rows[0].title,'Original pool');
  await asActor(editor,f.actor);
  const result=(await editor.query('SELECT public.save_inventory_pool_client_sync_v1($1,$2,0,$3) AS result',[f.id,command,bundle])).rows[0].result;
  assert.equal(result.status,'applied');await editor.query('COMMIT');
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM eshop.product_inventory_contexts WHERE product=ANY($1::bigint[])',[[f.product,other.id]])).rows[0].n,0);
 } finally {await setup.query('ROLLBACK');await editor.query('ROLLBACK');await Promise.all([setup.end(),editor.end()]);}
});
async function resourceFixture(c,f,title='Resource') {
 const pools=[];
 for(const label of ['A','B']) {
  const {rows:[pool]}=await c.query('INSERT INTO public.inventory_pools(occasion,title) VALUES($1,$2) RETURNING id',[f.id,label]);
  const {rows:[context]}=await c.query('INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES($1,$2) RETURNING id',[pool.id,label]);
  pools.push({...pool,context:context.id});
 }
 const {rows:[resource]}=await c.query('INSERT INTO public.resources(occasion,inventory_pool,title,capacity,booking_rules) VALUES($1,$2,$3,1,$4) RETURNING id',[f.id,pools[0].id,title,{}]);
 return {pools,resource:resource.id};
}
test('opposing resource moves lock both pools in one order and reconcile both sides',async()=>{
 const setup=await connect(),clients=await Promise.all([connect(),connect()]);
 try {
  const f=await authoringFixture(setup),g=await resourceFixture(setup,f);
  const {rows:[other]}=await setup.query("INSERT INTO public.resources(occasion,inventory_pool,title,capacity,booking_rules) VALUES($1,$2,'Other',1,'{}') RETURNING id",[f.id,g.pools[1].id]);
  const ids=[g.resource,other.id];
  const results=await Promise.all(clients.map(async(c,i)=>{
   await asActor(c,f.actor);
   const result=(await c.query('SELECT public.save_resource_client_sync_v1($1,$2,0,$3) AS result',[f.id,randomUUID(),{
    id:Number(ids[i]),inventory_pool:Number(g.pools[1-i].id),title:`Moved ${i}`,capacity:1,booking_rules:{}}])).rows[0].result;
   await c.query('COMMIT');return result;
  }));
  assert.ok(results.every(r=>r.status==='applied'));
  for(let i=0;i<2;i++) {
   assert.equal((await setup.query('SELECT inventory_pool FROM public.resources WHERE id=$1',[ids[i]])).rows[0].inventory_pool,g.pools[1-i].id);
   assert.equal((await setup.query('SELECT count(*)::int AS n FROM eshop.spots WHERE inventory_context=$1',[g.pools[i].context])).rows[0].n,1);
  }
 } finally {for(const c of clients){await c.query('ROLLBACK');await c.end();}await setup.end();}
});
test('resource deletion waits for its pool before acquiring the resource row',async()=>{
 const setup=await connect(),deleting=await connect(),probe=await connect();
 try {
  const f=await authoringFixture(setup),g=await resourceFixture(setup,f);
  await setup.query('BEGIN');await setup.query('SELECT 1 FROM public.inventory_pools WHERE id=$1 FOR UPDATE',[g.pools[0].id]);
  await asActor(deleting,f.actor);const pid=(await deleting.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=deleting.query('SELECT public.delete_resource_client_sync_v1($1,$2,$3,0) AS result',[f.id,g.resource,randomUUID()]);
  await expectDatabaseLock(setup,pid);
  await probe.query('BEGIN');
  await probe.query('SELECT 1 FROM public.resources WHERE id=$1 FOR UPDATE NOWAIT',[g.resource]);
  await probe.query('ROLLBACK');await setup.query('COMMIT');
  assert.equal((await pending).rows[0].result.status,'applied');await deleting.query('COMMIT');
 } finally {await setup.query('ROLLBACK');await deleting.query('ROLLBACK');await probe.query('ROLLBACK');await Promise.all([setup.end(),deleting.end(),probe.end()]);}
});
test('resource capacity change waits for a spot writer and rechecks its committed hold',async()=>{
 const setup=await connect(),holder=await connect(),editor=await connect();
 try {
  const f=await authoringFixture(setup),g=await resourceFixture(setup,f),secret=randomUUID();
  const {rows:[spot]}=await setup.query('INSERT INTO eshop.spots(occasion,inventory_context,resource) VALUES($1,$2,$3) RETURNING id',[f.id,g.pools[0].context,g.resource]);
  await holder.query('BEGIN');await holder.query("UPDATE eshop.spots SET secret=$2,secret_expiration_time=now()+interval '1 hour' WHERE id=$1",[spot.id,secret]);
  await asActor(editor,f.actor);const pid=(await editor.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=editor.query('SELECT public.save_resource_client_sync_v1($1,$2,0,$3) AS result',[f.id,randomUUID(),{
   id:Number(g.resource),inventory_pool:Number(g.pools[0].id),title:'Unsafe shrink',capacity:0,booking_rules:{}}]);
  await expectDatabaseLock(setup,pid);await holder.query('COMMIT');
  const result=(await pending).rows[0].result;assert.equal(result.status,'rejected');assert.equal(result.code,409);
  assert.ok(!JSON.stringify(result).includes(secret));await editor.query('COMMIT');
  assert.equal((await setup.query('SELECT capacity FROM public.resources WHERE id=$1',[g.resource])).rows[0].capacity,1);
 } finally {await holder.query('ROLLBACK');await editor.query('ROLLBACK');await Promise.all([setup.end(),holder.end(),editor.end()]);}
});

test('competing assignments serialize and reject the losing original mapping without a receipt',async()=>{
 const setup=await connect(),writer=await connect(),waiter=await connect();
 try {
  const f=await authoringFixture(setup);
  const {rows:[pool]}=await setup.query("INSERT INTO public.inventory_pools(occasion,title) VALUES($1,'Assignment pool') RETURNING id",[f.id]);
  const {rows:[ctx]}=await setup.query("INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES($1,'Assignment context') RETURNING id",[pool.id]);
  const {rows:[r]}=await setup.query("INSERT INTO public.resources(occasion,inventory_pool,title,capacity) VALUES($1,$2,'Resource',1) RETURNING id",[f.id,pool.id]);
  const spots=[];for(let i=0;i<3;i++)spots.push((await setup.query('INSERT INTO eshop.spots(occasion,inventory_context,resource) VALUES($1,$2,$3) RETURNING id',[f.id,ctx.id,i===0?r.id:null])).rows[0].id);
  const changes=id=>JSON.stringify([{old_spot_id:Number(spots[0]),new_spot_id:Number(id),resource_id:Number(r.id),inventory_context_id:Number(ctx.id)}]);
  await asActor(writer,f.actor);
  assert.equal((await writer.query('SELECT public.update_spot_assignments_client_sync_v1($1,$2) AS r',[changes(spots[1]),randomUUID()])).rows[0].r.status,'applied');
  await asActor(waiter,f.actor);const command=randomUUID(),pid=(await waiter.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=waiter.query('SELECT public.update_spot_assignments_client_sync_v1($1,$2)',[changes(spots[2]),command]);
  const rejected=assert.rejects(pending,e=>e.code==='40001');
  await expectDatabaseLock(setup,pid);await writer.query('COMMIT');await rejected;await waiter.query('ROLLBACK');
  assert.deepEqual((await setup.query('SELECT id FROM eshop.spots WHERE resource=$1',[r.id])).rows.map(r=>r.id),[spots[1]]);
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM public.client_mutation_receipts WHERE command_id=$1',[command])).rows[0].n,0);
 } finally {await writer.query('ROLLBACK');await waiter.query('ROLLBACK');await Promise.all([setup.end(),writer.end(),waiter.end()]);}
});
test('ticket swap waits for the actual spot lock and rejects a newly committed hold',async()=>{
 const setup=await connect(),holder=await connect(),editor=await connect();
 try {
  const f=await authoringFixture(setup),spots=[];
  for(let i=0;i<2;i++)spots.push((await setup.query('INSERT INTO eshop.spots(occasion,product) VALUES($1,$2) RETURNING id',[f.id,f.product])).rows[0].id);
  await holder.query('BEGIN');const secret=randomUUID();await holder.query("UPDATE eshop.spots SET secret=$1,secret_expiration_time=now()+interval '1 hour' WHERE id=$2",[secret,spots[1]]);
  await asActor(editor,f.actor);const pid=(await editor.query('SELECT pg_backend_pid() AS id')).rows[0].id,command=randomUUID();
  const pending=editor.query('SELECT public.swap_spot_tickets_client_sync_v1($1,$2,$3)',[spots[0],spots[1],command]);
  const rejected=assert.rejects(pending,e=>e.code==='55000'&&e.message==='SPOT_HELD');
  await expectDatabaseLock(setup,pid);await holder.query('COMMIT');await rejected;await editor.query('ROLLBACK');
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM public.client_mutation_receipts WHERE command_id=$1',[command])).rows[0].n,0);
  assert.equal((await setup.query('SELECT secret FROM eshop.spots WHERE id=$1',[spots[1]])).rows[0].secret,secret);
 } finally {await holder.query('ROLLBACK');await editor.query('ROLLBACK');await Promise.all([setup.end(),holder.end(),editor.end()]);}
});

test('concurrent replay of profile import invalidates companion owners exactly once',async()=>{
 const setup=await connect(),clients=await Promise.all([connect(),connect()]);
 try {
  const f=await authoringFixture(setup),companion=randomUUID();
  await setup.query('UPDATE public.occasion_users SET is_manager=true WHERE occasion=$1 AND "user"=$2',[f.id,f.actor]);
  await setup.query('INSERT INTO auth.users(id,email) VALUES($1,$2)',[companion,`${companion}@example.invalid`]);
  await setup.query('INSERT INTO public.user_info(id,organization) VALUES($1,$2)',[companion,f.organization]);
  await setup.query('INSERT INTO public.occasion_users(occasion,"user") VALUES($1,$2)',[f.id,companion]);
  await setup.query("INSERT INTO public.user_companions(occasion,\"user\",companion,origin,created_by) VALUES($1,$2,$3,'admin_assigned',$2)",[f.id,f.actor,companion]);
  const command=randomUUID();
  const results=await Promise.all(clients.map(async c=>{
   await asActor(c,f.actor);const result=(await c.query("SELECT public.import_profiles_client_sync_v1($1,$2,'[]','[]') AS r",[f.id,command])).rows[0].r;
   await c.query('COMMIT');return result;
  }));
  assert.equal(results[0].status,'applied');assert.deepEqual(results[0],results[1]);
  assert.equal((await setup.query("SELECT source_revision::int AS n FROM public.client_sync_private_scopes WHERE component='private_profile' AND occasion=$1 AND user_id=$2",[f.id,f.actor])).rows[0].n,1);
 } finally {for(const c of clients){await c.query('ROLLBACK');await c.end();}await setup.end();}
});

test('editors in different occasions share the global profile parent and reject the stale projection',async()=>{
 const setup=await connect(),writer=await connect(),waiter=await connect();
 try {
  const f=await authoringFixture(setup),target=randomUUID();
  const {rows:[other]}=await setup.query("INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time) VALUES($1,$2,'Other profile scope',$3,now(),now()+interval '1 day') RETURNING id",[f.organization,f.unit,randomUUID()]);
  await setup.query('UPDATE public.occasion_users SET is_manager=true WHERE occasion=$1 AND "user"=$2',[f.id,f.actor]);
  await setup.query('INSERT INTO public.occasion_users(occasion,"user",is_manager) VALUES($1,$2,true)',[other.id,f.actor]);
  await setup.query('INSERT INTO auth.users(id,email) VALUES($1,$2)',[target,`${target}@example.invalid`]);
  await setup.query("INSERT INTO public.user_info(id,organization,name) VALUES($1,$2,'Original')",[target,f.organization]);
  await setup.query('INSERT INTO public.occasion_users(occasion,"user") VALUES($1,$3),($2,$3)',[f.id,other.id,target]);
  const save=(c,oc,name)=>c.query('SELECT public.save_profile_client_sync_v1($1,$2,$3,0,$4) AS r',[oc,target,randomUUID(),{occasion:Number(oc),user:target,data:{name}}]);
  await asActor(writer,f.actor);assert.equal((await save(writer,f.id,'Winner')).rows[0].r.status,'applied');
  await asActor(waiter,f.actor);const pid=(await waiter.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=save(waiter,other.id,'Stale');await expectDatabaseLock(setup,pid);await writer.query('COMMIT');
  assert.equal((await pending).rows[0].r.status,'conflict');await waiter.query('COMMIT');
  assert.equal((await setup.query('SELECT name FROM public.user_info WHERE id=$1',[target])).rows[0].name,'Winner');
 } finally {await writer.query('ROLLBACK');await waiter.query('ROLLBACK');await Promise.all([setup.end(),writer.end(),waiter.end()]);}
});

test('concurrent occasion deletion replays the same receipt after waiting for the deleted row',async()=>{
 const setup=await connect(),writer=await connect(),waiter=await connect();
 try {
  const f=await authoringFixture(setup),command=randomUUID();
  await setup.query('INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES($1,$2,true,true)',[f.unit,f.actor]);
  await asActor(writer,f.actor);
  const first=(await writer.query('SELECT public.delete_occasion_client_sync_v1($1,$2) AS r',[f.id,command])).rows[0].r;assert.equal(first.status,'applied');
  await asActor(waiter,f.actor);const pid=(await waiter.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=waiter.query('SELECT public.delete_occasion_client_sync_v1($1,$2) AS r',[f.id,command]);
  await expectDatabaseLock(setup,pid);await writer.query('COMMIT');assert.deepEqual((await pending).rows[0].r,first);await waiter.query('COMMIT');
 } finally {await writer.query('ROLLBACK');await waiter.query('ROLLBACK');await Promise.all([setup.end(),writer.end(),waiter.end()]);}
});
test('event deletion rejects a child-link phantom before mutation and resumes the same command',async()=>{
 const setup=await connect(),editor=await connect();
 try {
  const f=await authoringFixture(setup),ids=[];
  for(const title of ['Parent','Child'])ids.push((await setup.query("INSERT INTO public.events(occasion,title,start_time,end_time) VALUES($1,$2,now()+interval '1 hour',now()+interval '2 hours') RETURNING id",[f.id,title])).rows[0].id);
  await setup.query('BEGIN');await setup.query('SELECT 1 FROM public.events WHERE id=$1 FOR UPDATE',[ids[0]]);
  await asActor(editor,f.actor);const command=randomUUID(),pid=(await editor.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=editor.query('SELECT public.delete_event_client_sync_v1($1,$2,$3,0)',[f.id,ids[0],command]);const rejected=assert.rejects(pending,e=>e.code==='40001');
  await expectDatabaseLock(setup,pid);await setup.query('INSERT INTO public.event_groups(event_parent,event_child) VALUES($1,$2)',ids);await setup.query('COMMIT');await rejected;await editor.query('ROLLBACK');
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM public.client_mutation_receipts WHERE command_id=$1',[command])).rows[0].n,0);
  await asActor(editor,f.actor);assert.equal((await editor.query('SELECT public.delete_event_client_sync_v1($1,$2,$3,0) AS r',[f.id,ids[0],command])).rows[0].r.status,'applied');await editor.query('COMMIT');
  assert.equal((await setup.query("SELECT version::int AS n FROM public.client_aggregate_versions WHERE aggregate_type='event' AND scope_id=$1 AND aggregate_id=$2",[f.id,ids[1]])).rows[0].n,1);
 } finally {await setup.query('ROLLBACK');await editor.query('ROLLBACK');await Promise.all([setup.end(),editor.end()]);}
});
test('empty-slot deletion keeps a booking and its version committed while waiting for the slot lock',async()=>{
 const setup=await connect(),holder=await connect(),editor=await connect();
 try {
  const f=await authoringFixture(setup);
  const {rows:[sp]}=await setup.query("INSERT INTO public.speakers(occasion,title) VALUES($1,'Counselor') RETURNING id",[f.id]);
  const {rows:[slot]}=await setup.query("INSERT INTO public.events(occasion,title,start_time,end_time,data) VALUES($1,'Slot',now()+interval '1 hour',now()+interval '2 hours','{\"is_counseling_slot\":true}') RETURNING id",[f.id]);
  await setup.query('INSERT INTO public.event_speakers(event,speaker) VALUES($1,$2)',[slot.id,sp.id]);
  await setup.query("INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version) VALUES('event','occasion',$1,$2,7)",[f.id,slot.id]);
  await holder.query('BEGIN');await holder.query('SELECT 1 FROM public.events WHERE id=$1 FOR UPDATE',[slot.id]);await holder.query('INSERT INTO public.event_users(event,"user") VALUES($1,$2)',[slot.id,f.actor]);
  await asActor(editor,f.actor);const pid=(await editor.query('SELECT pg_backend_pid() AS id')).rows[0].id,command=randomUUID();
  const pending=editor.query('SELECT public.delete_empty_counseling_slots_client_sync_v1($1,NULL,$2) AS r',[sp.id,command]);
  await expectDatabaseLock(setup,pid);await holder.query('COMMIT');const result=(await pending).rows[0].r;assert.equal(result.status,'unchanged');assert.equal(result.data.deleted,0);await editor.query('COMMIT');
  assert.equal((await setup.query("SELECT version::int AS n FROM public.client_aggregate_versions WHERE aggregate_type='event' AND scope_id=$1 AND aggregate_id=$2",[f.id,slot.id])).rows[0].n,7);
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM public.event_users WHERE event=$1',[slot.id])).rows[0].n,1);
 } finally {await holder.query('ROLLBACK');await editor.query('ROLLBACK');await Promise.all([setup.end(),holder.end(),editor.end()]);}
});
test('product save rejects a newly committed order parent and retries the same command under the complete lock set',async()=>{
 const setup=await connect(),editor=await connect();
 try {
  const f=await authoringFixture(setup),command=randomUUID(),payload={id:Number(f.product),title:'After parent retry',expected_aggregate_version:0};
  await setup.query('BEGIN');await setup.query('SELECT 1 FROM eshop.products WHERE id=$1 FOR UPDATE',[f.product]);
  await asActor(editor,f.actor);const pid=(await editor.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=editor.query('SELECT public.update_product_client_sync_v1($1,$2)',[payload,command]);const rejected=assert.rejects(pending,e=>e.code==='40001');
  await expectDatabaseLock(setup,pid);
  const {rows:[order]}=await setup.query("INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state) VALUES($1,public.next_order_sequence($1),public.generate_order_symbol(),'ordered') RETURNING id",[f.id]);
  const {rows:[ticket]}=await setup.query("INSERT INTO eshop.tickets(occasion,state) VALUES($1,'ordered') RETURNING id",[f.id]);
  await setup.query('INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES($1,$2,$3)',[order.id,ticket.id,f.product]);await setup.query('COMMIT');await rejected;await editor.query('ROLLBACK');
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM public.client_mutation_receipts WHERE command_id=$1',[command])).rows[0].n,0);
  await asActor(editor,f.actor);assert.equal((await editor.query('SELECT public.update_product_client_sync_v1($1,$2) AS r',[payload,command])).rows[0].r.status,'applied');await editor.query('COMMIT');
 } finally {await setup.query('ROLLBACK');await editor.query('ROLLBACK');await Promise.all([setup.end(),editor.end()]);}
});

test('resource deletion waits for real allocation and rejects the newly allocated inventory',async()=>{
 const setup=await connect(),allocator=await connect(),editor=await connect();
 try {
  const f=await authoringFixture(setup),g=await resourceFixture(setup,f);
  await setup.query("UPDATE public.inventory_pools SET data='{\"is_auto_resource_assignment\":true}' WHERE id=$1",[g.pools[0].id]);
  await setup.query('INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES($1,$2,1)',[f.product,g.pools[0].context]);
  await setup.query('SELECT public.adjust_spot_capacity_for_pool($1)',[g.pools[0].id]);
  const {rows:[order]}=await setup.query("INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state) VALUES($1,public.next_order_sequence($1),public.generate_order_symbol(),'ordered') RETURNING id",[f.id]);
  const {rows:[ticket]}=await setup.query("INSERT INTO eshop.tickets(occasion,state) VALUES($1,'ordered') RETURNING id",[f.id]);
  await setup.query('INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES($1,$2,$3)',[order.id,ticket.id,f.product]);
  await allocator.query('BEGIN');await allocator.query('SELECT public.lock_order_capacity_scope_internal($1::bigint[])',[[order.id]]);await allocator.query('SELECT public.apply_allocations($1)',[order.id]);
  assert.equal((await allocator.query('SELECT count(*)::int AS n FROM eshop.spots WHERE resource=$1 AND order_product_ticket IS NOT NULL',[g.resource])).rows[0].n,1);
  await asActor(editor,f.actor);const pid=(await editor.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=editor.query('SELECT public.delete_resource_client_sync_v1($1,$2,$3,0) AS r',[f.id,g.resource,randomUUID()]);
  await expectDatabaseLock(setup,pid);await allocator.query('COMMIT');assert.equal((await pending).rows[0].r.status,'rejected');await editor.query('COMMIT');
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM eshop.spots WHERE resource=$1 AND order_product_ticket IS NOT NULL',[g.resource])).rows[0].n,1);
 } finally {await allocator.query('ROLLBACK');await editor.query('ROLLBACK');await Promise.all([setup.end(),allocator.end(),editor.end()]);}
});
test('blueprint editing rechecks a hold created by the anonymous reservation RPC',async()=>{
 const setup=await connect(),buyer=await connect(),editor=await connect();
 try {
  const f=await authoringFixture(setup),secret=randomUUID();
  const {rows:[bp]}=await setup.query("INSERT INTO eshop.blueprints(occasion,organization,title,objects) VALUES($1,$2,'Seats','[]') RETURNING id",[f.id,f.organization]);
  const {rows:[form]}=await setup.query("INSERT INTO public.forms(occasion,blueprint,title,is_open) VALUES($1,$2,'Open seats',true) RETURNING key",[f.id,bp.id]);
  const {rows:[seat]}=await setup.query("INSERT INTO eshop.spots(occasion,blueprint,product,title) VALUES($1,$2,$3,'Seat') RETURNING id",[f.id,bp.id,f.product]);
  await buyer.query('BEGIN');await buyer.query("SELECT set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','anon',true)");await buyer.query('SET LOCAL ROLE anon');
  assert.equal((await buyer.query('SELECT public.select_spot($1,$2,$3,true) AS r',[form.key,secret,seat.id])).rows[0].r.code,200);
  await asActor(editor,f.actor);const pid=(await editor.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=editor.query('SELECT public.update_blueprint_client_sync_v1($1,$2) AS r',[{id:Number(bp.id),occasion:Number(f.id),organization:Number(f.organization),objects:[],expected_aggregate_version:0},randomUUID()]);
  await expectDatabaseLock(setup,pid);await buyer.query('COMMIT');const result=(await pending).rows[0].r;assert.equal(result.status,'rejected');assert.ok(!JSON.stringify(result).includes(secret));await editor.query('COMMIT');
  assert.equal((await setup.query('SELECT secret FROM eshop.spots WHERE id=$1',[seat.id])).rows[0].secret,secret);
 } finally {await buyer.query('ROLLBACK');await editor.query('ROLLBACK');await Promise.all([setup.end(),buyer.end(),editor.end()]);}
});
for(const first of ['group','place'])test(`${first} writer keeps the original private-place baseline across concurrent group and map editors`,async()=>{
 const setup=await connect(),writer=await connect(),waiter=await connect();
 try {
  const f=await authoringFixture(setup);
  const {rows:[place]}=await setup.query("INSERT INTO public.places(occasion,title,type,is_hidden,coordinates) VALUES($1,'Private','group',true,'{\"latLng\":{\"lat\":0,\"lng\":0}}') RETURNING id",[f.id]);
  const {rows:[group]}=await setup.query("INSERT INTO public.user_group_info(occasion,title,place) VALUES($1,'Group',$2) RETURNING id",[f.id,place.id]);
  await setup.query('INSERT INTO public.user_groups("group","user",is_admin) VALUES($1,$2,true)',[group.id,f.actor]);
  const payload={id:Number(group.id),title:'Group changed',description:null,type:null,placeId:null,privatePlace:{id:Number(place.id),title:'Private',description:null,coordinates:{latLng:{lat:4,lng:5}},order:0,icon:null},participants:[{user_id:f.actor,is_admin:true}]};
  const run=(c,kind)=>kind==='group'
   ?c.query('SELECT public.save_user_group_client_sync_v1($1,$2,0,$3) AS r',[f.id,randomUUID(),payload])
   :c.query('SELECT public.move_place_client_sync_v1($1,$2,$3,0,2,3) AS r',[f.id,place.id,randomUUID()]);
  await asActor(writer,f.actor);assert.equal((await run(writer,first)).rows[0].r.status,'applied');
  await asActor(waiter,f.actor);const pid=(await waiter.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  const pending=run(waiter,first==='group'?'place':'group');await expectDatabaseLock(setup,pid);await writer.query('COMMIT');assert.equal((await pending).rows[0].r.status,'conflict');await waiter.query('COMMIT');
  assert.equal((await setup.query("SELECT (coordinates#>>'{latLng,lat}')::int AS lat FROM public.places WHERE id=$1",[place.id])).rows[0].lat,first==='group'?4:2);
 } finally {await writer.query('ROLLBACK');await waiter.query('ROLLBACK');await Promise.all([setup.end(),writer.end(),waiter.end()]);}
});

test('owned companion deletion waits for an admitted attendance command and replays after account removal',async()=>{
 const setup=await connect(),attendee=await connect(),deleter=await connect();
 try {
  const f=await authoringFixture(setup);
  await setup.query("UPDATE public.occasions SET features='[{\"code\":\"companions\",\"is_enabled\":true,\"allow_user_create\":true,\"max_companions\":2},{\"code\":\"workshops\",\"is_enabled\":true}]' WHERE id=$1",[f.id]);
  await setup.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[f.actor]);
  const created=(await setup.query('SELECT public.create_companion_client_sync_v1($1,$2,$3) AS r',[f.id,'Companion',randomUUID()])).rows[0].r;assert.equal(created.status,'applied');const companion=created.data.companion.id;
  const {rows:[event]}=await setup.query("INSERT INTO public.events(occasion,title,start_time,end_time) VALUES($1,'Attendance',now()+interval '1 hour',now()+interval '2 hours') RETURNING id",[f.id]);
  await asActor(attendee,f.actor);assert.equal((await attendee.query("SELECT public.set_event_attendance_client_sync_v1($1,$2,'sign_in',$3) AS r",[event.id,companion,randomUUID()])).rows[0].r.code,200);
  await asActor(deleter,f.actor);const pid=(await deleter.query('SELECT pg_backend_pid() AS id')).rows[0].id,command=randomUUID();
  const pending=deleter.query('SELECT public.delete_owned_companion_client_sync_v1($1,$2,$3) AS r',[f.id,companion,command]);
  await expectDatabaseLock(setup,pid);await attendee.query('COMMIT');const deleted=(await pending).rows[0].r;assert.equal(deleted.status,'applied');await deleter.query('COMMIT');
  assert.equal((await setup.query('SELECT count(*)::int AS n FROM public.user_info WHERE id=$1',[companion])).rows[0].n,0);
  await asActor(deleter,f.actor);assert.deepEqual((await deleter.query('SELECT public.delete_owned_companion_client_sync_v1($1,$2,$3) AS r',[f.id,companion,command])).rows[0].r,deleted);await deleter.query('COMMIT');
 } finally {await attendee.query('ROLLBACK');await deleter.query('ROLLBACK');await Promise.all([setup.end(),attendee.end(),deleter.end()]);}
});
