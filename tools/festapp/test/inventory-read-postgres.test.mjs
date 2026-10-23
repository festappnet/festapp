import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
import {openDisposableDatabase} from './postgres.mjs';
import {Operations} from '../src/operations/catalog.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};
async function install(db) {
 for(const name of ['20261023163000_product_admin_read_semantics.sql','20261023170000_product_schedule_commands.sql','20261023180000_atomic_standing_inventory.sql','20261023190000_inventory_summary_reads.sql','20261023200000_inventory_authoring_commands.sql'])
  await db.query(await readFile(new URL('../../../supabase/migrations/'+name,import.meta.url),'utf8'));
}
function executor(db,f) {
 const stats=[];
 const owner={root:'/tmp/festapp-inventory-read',profile:{organizationId:f.org,tenantId:'fixture',name:'fixture',backendOrigin:'http://127.0.0.1:61022'},allowedOperations:['inventory.pools.list','inventory.contexts.list'],delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized:action=>action({rpc:async(name,args)=>{
  await db.query('SAVEPOINT rpc');
  try {
   const pools=name==='get_inventory_catalog';assert(pools||name==='get_inventory_context_catalog');
   const data=(await db.query(pools?'select get_inventory_catalog($1,$2,$3,NULL,$4,$5) value':'select get_inventory_context_catalog($2,$1,$3,$6,$4,$5) value',pools?[args.p_organization,args.p_occasion,args.p_unit,args.p_after,args.p_limit]:[args.p_organization,args.p_occasion,args.p_unit,args.p_after,args.p_limit,args.p_pool])).rows[0].value;
   await db.query('RELEASE SAVEPOINT rpc');stats.push({rpc:name,jsonBytes:Buffer.byteLength(JSON.stringify(data)),pools:data.pools?.length??0,contexts:data.inventory_contexts?.length??0});return {data,error:null};
  } catch(e) {await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return {error:{code:e.code,status:e.code==='42501'?403:400}};}
 }},{userId:f.actor})};
 const ops=new Operations(owner);
 return {owner,stats,pools:(args={})=>ops.invoke('inventory.pools.list',{occasionId:f.occasion,...args}),contexts:(poolId,args={})=>ops.invoke('inventory.contexts.list',{occasionId:f.occasion,poolId,...args})};
}

test('inventory UI and MCP share actual context counts without child-join multiplication or hold secrets',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await fixture(db,2);
 const pool=Number((await db.query("insert into inventory_pools(occasion,title,sellable_capacity) values($1,'Supply',80) returning id",[f.occasion])).rows[0].id);
 const contexts=(await db.query("insert into inventory_contexts(inventory_pool,title,\"order\") values($1,'First',2),($1,NULL,1),($1,'Empty',3) returning id",[pool])).rows.map(r=>Number(r.id));
 await db.query("insert into resources(inventory_pool,occasion,title,capacity) values($1,$2,'A',40),($1,$2,'B',60)",[pool,f.occasion]);
 const type=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Items','entry') returning id",[f.occasion])).rows[0].id);
 const product=Number((await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Item',10,'CZK') returning id",[f.occasion,type])).rows[0].id);
 const order=Number((await db.query("insert into eshop.orders(occasion,order_sequence,order_symbol,state) values($1,next_order_sequence($1),generate_order_symbol(),'paid') returning id",[f.occasion])).rows[0].id);
 const ticket=Number((await db.query("insert into eshop.tickets(occasion,state) values($1,'paid') returning id",[f.occasion])).rows[0].id);
 const item=Number((await db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3) returning id',[order,ticket,product])).rows[0].id);
 await db.query('insert into eshop.spots(occasion,inventory_context) select $1,$2 from generate_series(1,100)',[f.occasion,contexts[0]]);
 await db.query('insert into eshop.spots(occasion,inventory_context,order_product_ticket) select $1,$2,$3 from generate_series(1,2)',[f.occasion,contexts[1],item]);
 await db.query('update eshop.spots set order_product_ticket=$2 where id in(select id from eshop.spots where inventory_context=$1 order by id limit 3)',[contexts[0],item]);
 await db.query("update eshop.spots set secret='11111111-2222-4333-8444-555555555555',secret_expiration_time=now()+interval '1 hour' where id=(select id from eshop.spots where inventory_context=$1 and order_product_ticket is null order by id limit 1)",[contexts[0]]);
 const slot=Number((await db.query("insert into resource_slots(resource,title) values((select id from resources where inventory_pool=$1 order by id limit 1),'Assigned slot') returning id",[pool])).rows[0].id);
 await db.query('update eshop.spots set resource_slot=$2 where id=(select id from eshop.spots where inventory_context=$1 and order_product_ticket is not null order by id limit 1)',[contexts[0],slot]);
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);
 const ui=(await db.query("select get_inventory_catalog($1,$2,$3,NULL,NULL,NULL,'summary') value",[f.org,f.occasion,f.unit])).rows[0].value;
 const legacy=(await db.query('select get_inventory_pools_by_occasion_link($1) value',[f.link])).rows[0].value;
 assert.equal(legacy.spots.length,102);assert.equal(ui.spots,undefined);assert(!JSON.stringify(ui).includes('11111111-2222-4333-8444-555555555555'));assert(!JSON.stringify(ui).includes('order_product_ticket'));
 assert.deepEqual(ui.inventory_contexts.map(c=>c.id),[contexts[1],contexts[0],contexts[2]],'UI retains custom context ordering');
 let result=await ex.pools();assert.equal(result.ok,true,JSON.stringify(result));const p=result.data.pools[0];
 assert.equal(p.context_count,3);assert.equal(p.resource_count,2);assert.equal(p.resource_capacity,100);assert.equal(p.sellable_capacity,80);
 assert.equal(p.physical_count,102);assert.equal(p.allocated_count,5);assert.equal(p.unassigned_count,4);assert.equal(p.held_count,1);
 result=await ex.contexts(pool);assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.inventory_contexts.length,3);
 for(const c of result.data.inventory_contexts) {
  const expected=ui.inventory_contexts.find(r=>r.id===c.id);
  for(const key of ['physical_count','allocated_count','unassigned_count','held_count','title']) assert.deepEqual(c[key],expected[key]);
 }
 assert.equal(result.data.inventory_contexts.find(c=>c.id===contexts[2]).physical_count,0);
 assert(!JSON.stringify(result.data).includes('11111111-2222-4333-8444-555555555555'));assert(!JSON.stringify(result.data).includes('order_product_ticket'));
 const scope=ex.owner.delegatedContext;ex.owner.delegatedContext=async()=>({organizationId:f.org,unitId:f.unit+99999});assert.equal((await ex.pools()).error.code,'FORBIDDEN');ex.owner.delegatedContext=scope;
 await db.query('RESET ROLE');const foreign=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);
 const foreignPool=Number((await db.query("insert into inventory_pools(occasion,title) values($1,'Foreign') returning id",[foreign])).rows[0].id);
 await db.query('SET LOCAL ROLE authenticated');assert.equal((await ex.contexts(foreignPool)).error.code,'FORBIDDEN');
 // Unit management alone does not grant order-view access. Keep the live
 // typed permission contract rather than inferring access from role names.
 await db.query('RESET ROLE');await db.query('update occasion_users set is_editor_order_view=false,is_editor=false,is_manager=false,is_editor_order=false,is_editor_view=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await ex.pools()).error.code,'FORBIDDEN');
 await db.query('RESET ROLE');await db.query('update occasion_users set is_editor_order_view=true where occasion=$1 and \"user\"=$2',[f.occasion,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await ex.pools()).ok,true);
 await db.query('RESET ROLE');await db.query('update occasion_users set is_editor_order_view=false where occasion=$1 and \"user\"=$2',[f.occasion,f.actor]);await db.query('update unit_users set is_manager=false,is_editor=false,is_editor_view=false where unit=$1 and "user"=$2',[f.unit,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await ex.pools()).error.code,'FORBIDDEN');
 t.diagnostic('inventory-read-audit '+JSON.stringify({legacyJsonBytes:Buffer.byteLength(JSON.stringify(legacy)),uiJsonBytes:Buffer.byteLength(JSON.stringify(ui)),calls:ex.stats}));
});

test('inventory pool and context keysets bound each collection and accept empty metadata',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await fixture(db,1);
 const pools=(await db.query("insert into inventory_pools(occasion,title) select $1,'Pool '||n from generate_series(1,125) n returning id",[f.occasion])).rows.map(r=>Number(r.id));
 const contexts=(await db.query('insert into inventory_contexts(inventory_pool) select $1 from generate_series(1,125) returning id',[pools[0]])).rows.map(r=>Number(r.id));
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);let after;const seen=[];
 do {const r=await ex.pools({limit:50,...(after?{after}:{})});assert.equal(r.ok,true,JSON.stringify(r));assert(r.data.pools.length<=50);seen.push(...r.data.pools.map(p=>p.id));after=r.data.nextCursor;}while(after);
 assert.deepEqual(seen,pools);after=undefined;const seenContexts=[];
 do {const r=await ex.contexts(pools[0],{limit:50,...(after?{after}:{})});assert.equal(r.ok,true,JSON.stringify(r));assert(r.data.inventory_contexts.length<=50);seenContexts.push(...r.data.inventory_contexts.map(c=>c.id));after=r.data.nextCursor;}while(after);
 assert.deepEqual(seenContexts,contexts);assert.deepEqual((await ex.contexts(pools[1])).data.inventory_contexts,[]);
 assert.equal(ex.stats.length,7);
 for(const [sql,args] of [
  ["select get_inventory_catalog($1,$2,$3,NULL,NULL,NULL,'page')",[f.org,f.occasion,f.unit]],
  ["select get_inventory_catalog($1,$2,$3,NULL,NULL,50,'summary')",[f.org,f.occasion,f.unit]],
  ["select get_inventory_catalog($1,$2,$3,NULL,NULL,101)",[f.org,f.occasion,f.unit]],
  ["select get_inventory_context_catalog($2,$1,$3,$4,NULL,NULL)",[f.org,f.occasion,f.unit,pools[0]]],
 ]) {
  await db.query('SAVEPOINT invalid');await assert.rejects(db.query(sql,args),e=>e.code==='22023');await db.query('ROLLBACK TO SAVEPOINT invalid');await db.query('RELEASE SAVEPOINT invalid');
 }

 await db.query('RESET ROLE');
 assert.equal((await db.query("select has_function_privilege('anon','get_inventory_catalog(bigint,bigint,bigint,text,bigint,integer,text)','execute') allowed")).rows[0].allowed,false);
 assert.equal((await db.query("select has_function_privilege('authenticated','get_inventory_context_facts_internal(bigint,bigint[],bigint[])','execute') allowed")).rows[0].allowed,false);
});

// Pause the actual SQL projection with a relation lock. This exercises rights
// changing after the first scope check, rather than merely a denied new call.
test('two connections: inventory and product reads recheck revoked rights; a moved pool cannot leak context data',options,async t=>{
 const admin=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
 const reader=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);let f;
 t.after(async()=>{
  await admin.query('ROLLBACK');await reader.query('ROLLBACK');await reader.end();
  if(f) {
   await admin.query('BEGIN');
   await admin.query('delete from inventory_contexts where inventory_pool in(select id from inventory_pools where occasion in(select id from occasions where organization=$1))',[f.org]);
   await admin.query('delete from inventory_pools where occasion in(select id from occasions where organization=$1)',[f.org]);
   for(const table of ['places','occasion_users','occasion_link_reservations']) await admin.query(`delete from ${table} where occasion in(select id from occasions where organization=$1)`,[f.org]);
   await admin.query('delete from occasions where organization=$1',[f.org]);
   await admin.query("delete from abuse_policy_overrides where (target_kind='unit' and target_id=$1) or (target_kind='organization' and target_id=$2)",[f.unit,f.org]);
   await admin.query('delete from unit_users where unit=$1',[f.unit]);await admin.query('delete from units where organization=$1',[f.org]);
   await admin.query('delete from user_info where id=$1',[f.actor]);await admin.query('delete from auth.users where id=$1',[f.actor]);await admin.query('delete from organizations where id=$1',[f.org]);await admin.query('COMMIT');
  }await admin.end();
 });
 await admin.query('BEGIN');await install(admin);f=await fixture(admin,2);
 const other=Number((await admin.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);
 const pool=Number((await admin.query("insert into inventory_pools(occasion,title) values($1,'Movable') returning id",[f.occasion])).rows[0].id);
 await admin.query("insert into inventory_contexts(inventory_pool,title) values($1,'Private context')",[pool]);await admin.query('COMMIT');
 const beginRead=async()=>{await reader.query('BEGIN');await reader.query("set local statement_timeout='5s'");await reader.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await reader.query('SET LOCAL ROLE authenticated');};
 const blocked=async()=>{for(let n=0;n<100;n++){if((await admin.query('select wait_event_type from pg_stat_activity where pid=$1',[reader.processID])).rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,10));}assert.fail('actual projection must block before rights are revoked');};
 for(const [sql,args,relation] of [
  ['select get_inventory_catalog($1,$2,$3)',[f.org,f.occasion,f.unit],'eshop.spots'],
  ['select get_inventory_context_catalog($2,$1,$3,$4)',[f.org,f.occasion,f.unit,pool],'eshop.spots'],
  ['select get_inventory_pool_for_edit($2,$1,$3,$4)',[f.org,f.occasion,f.unit,pool],'eshop.products'],
  ['select get_inventory_pool_settings($2,$1,$3,$4)',[f.org,f.occasion,f.unit,pool],'public.inventory_contexts'],
  ['select get_inventory_resources($2,$1,$3,$4)',[f.org,f.occasion,f.unit,pool],'public.resources'],
  ['select get_product_catalog($1,$2,$3)',[f.org,f.occasion,f.unit],'eshop.products'],
  ['select get_product_catalog_page($1,$2,$3)',[f.org,f.occasion,f.unit],'eshop.products'],
  ['select get_product_schedule($2,$1,$3)',[f.org,f.occasion,f.unit],'eshop.product_price_waves'],
 ]) {
  await admin.query('BEGIN');await admin.query(`lock table ${relation} in access exclusive mode`);await beginRead();
  const denied=assert.rejects(reader.query(sql,args),e=>e.code==='42501');await blocked();
  await admin.query('update occasion_users set is_editor_order_view=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await admin.query('COMMIT');await denied;await reader.query('ROLLBACK');
  await admin.query('update occasion_users set is_editor_order_view=true where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
 }
 await admin.query('BEGIN');await admin.query('update inventory_pools set occasion=$2 where id=$1',[pool,other]);await beginRead();
 const denied=assert.rejects(reader.query('select get_inventory_context_catalog($1,$2,$3,$4)',[f.occasion,f.org,f.unit,pool]),e=>e.code==='42501');await blocked();await admin.query('COMMIT');await denied;
});


test('inventory summary owners match authored SQL and expose no private helper grants',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);
 await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
 const owners=['get_inventory_context_facts_internal','get_inventory_pool_rows_internal','get_inventory_context_rows_internal','get_inventory_catalog_data_internal','get_inventory_catalog','get_inventory_context_catalog','get_inventory_pools_by_occasion_link','get_product_catalog','get_product_catalog_page','get_product_schedule'];
 const contract=await readFile(new URL('../../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url),'utf8');
 const assertions=contract.split('\n').filter(line=>owners.some(name=>line.includes("to_regprocedure('public."+name+'(')));
 assert.equal(assertions.length,owners.length);await db.query('DO $$ BEGIN\n'+assertions.join('\n')+'\nEND $$;');
 for(const signature of ['get_inventory_catalog(bigint,bigint,bigint,text,bigint,integer,text)','get_inventory_context_catalog(bigint,bigint,bigint,bigint,bigint,integer)']) {
  for(const role of ['anon','service_role']) assert.equal((await db.query("select has_function_privilege($1,$2,'execute') allowed",[role,signature])).rows[0].allowed,false);
 }
});
