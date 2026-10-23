import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fixture } from '../../../automation/authorization/benchmark.mjs';
import { openDisposableDatabase } from './postgres.mjs';
import { Operations } from '../src/operations/catalog.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};
async function install(db) {
 for(const name of ['20261023163000_product_admin_read_semantics.sql','20261023170000_product_schedule_commands.sql','20261023180000_atomic_standing_inventory.sql','20261023190000_inventory_summary_reads.sql'])
  await db.query(await readFile(new URL('../../../supabase/migrations/'+name,import.meta.url),'utf8'));
}
async function productFixture(db) {
 const f=await fixture(db,2);
 f.type=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Admission','spot') returning id",[f.occasion])).rows[0].id);
 f.product=Number((await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Standing admission',100,'CZK') returning id",[f.occasion,f.type])).rows[0].id);
 return f;
}
function executor(db,f) {
 const stats={requests:0,replies:[],lose:false};
 const owner={root:'/tmp/festapp-standing-fixture',profile:{organizationId:f.org,tenantId:'fixture',name:'fixture',backendOrigin:'http://127.0.0.1:61022'},allowedOperations:['inventory.prepare_standing'],delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized:action=>action({rpc:async(name,args)=>{
  assert.equal(name,'prepare_standing_inventory');stats.requests++;await db.query('SAVEPOINT rpc');
  try {
   const data=(await db.query('select prepare_standing_inventory($1,$2,$3,$4,$5,$6,$7) value',[args.p_occasion,args.p_organization,args.p_unit,args.p_product_id,args.p_expected_version,args.p_capacity,args.p_command_id])).rows[0].value;
   await db.query('RELEASE SAVEPOINT rpc');stats.replies.push({code:data.code,jsonBytes:Buffer.byteLength(JSON.stringify(data))});
   if(stats.lose){stats.lose=false;return {error:{code:'ECONNRESET',status:503}};}
   return {data,error:null};
  }catch(e){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return {error:{code:e.code,status:e.code==='42501'?403:500}};}
 }},{userId:f.actor})};
 const ops=new Operations(owner);
 return {stats,owner,prepare:(extra={})=>ops.invoke('inventory.prepare_standing',{occasionId:f.occasion,productId:f.product,expectedVersion:0,capacity:25,commandId:randomUUID(),...extra})};
}

test('standing preparation is one scoped receipt, replays after loss and returns authoritative IDs/versions without reload',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await productFixture(db);
 const foreign=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);
 const foreignType=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Foreign','spot') returning id",[foreign])).rows[0].id);
 const foreignProduct=Number((await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Foreign',10,'CZK') returning id",[foreign,foreignType])).rows[0].id);
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);assert.equal((await ex.prepare({productId:foreignProduct})).error.code,'FORBIDDEN');const commandId=randomUUID();ex.stats.lose=true;
 assert.equal((await ex.prepare({commandId})).error.retryable,true);
 const saved=await ex.prepare({commandId});assert.equal(saved.ok,true,JSON.stringify(saved));const p=saved.data.preparation;
 assert.equal(p.product.occasion,f.occasion);assert.equal(p.product.aggregate_version,1);assert.equal(p.product.type,'spot');
 assert.equal(p.pool.aggregate_version,2);assert.equal(p.resource.aggregate_version,1);assert.equal(p.resource.capacity,25);
 assert.deepEqual(p.product.inventory_contexts,[{inventory_context_id:p.context.id,quantity:1}]);
 assert.equal(p.context.inventory_pool,p.pool.id);assert.equal(p.resource.inventory_pool,p.pool.id);assert.equal(p.pool.data.is_auto_resource_assignment,false);
 assert.deepEqual((await ex.prepare({commandId})).data,saved.data);assert.equal(ex.stats.requests,4,'one denied scope call plus three exact attempts; no post-save reload');
 assert.equal((await ex.prepare()).error.code,'PRODUCT_CHANGED_RELOAD_REQUIRED');
 await db.query('RESET ROLE');
 assert.equal(Number((await db.query('select count(*) n from inventory_pools where occasion=$1',[f.occasion])).rows[0].n),1);
 assert.equal(Number((await db.query('select count(*) n from resources where occasion=$1',[f.occasion])).rows[0].n),1);
 assert.equal(Number((await db.query('select count(*) n from client_mutation_receipts where command_id=$1',[commandId])).rows[0].n),1);
 assert.equal(Number((await db.query("select count(*) n from client_commits where occasion=$1 and source='inventory.standing.prepare'",[f.occasion])).rows[0].n),1);
 assert.equal(Number((await db.query("select count(*) n from client_commits where occasion=$1 and source in ('inventory.pool.save','inventory.resource.save','inventory.product.contexts')",[f.occasion])).rows[0].n),0,'no nested child publication');
 const raw=(await db.query('select get_product_catalog($1,$2,$3) value',[f.org,f.occasion,f.unit])).rows[0].value.catalog.products[0];
 assert.equal(raw.aggregate_version,p.product.aggregate_version);assert.equal(Number(raw.price),Number(p.product.price));
 await db.query('SET LOCAL ROLE authenticated');
 const scope=ex.owner.delegatedContext;ex.owner.delegatedContext=async()=>({organizationId:f.org,unitId:f.unit+99999});assert.equal((await ex.prepare({commandId})).error.code,'FORBIDDEN');ex.owner.delegatedContext=scope;
 await db.query('RESET ROLE');await db.query('update unit_users set is_manager=false,is_editor=false where unit=$1 and "user"=$2',[f.unit,f.actor]);await db.query('update occasion_users set is_manager=false,is_editor=false,is_editor_order=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await ex.prepare({commandId})).error.code,'FORBIDDEN');
 t.diagnostic('standing-data-audit '+JSON.stringify(ex.stats));
});

test('failure between children rolls back all new stock, and insufficient capacity preserves sold items and addressed seats',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await productFixture(db);
 await db.query('SAVEPOINT original_owner');
 await db.query("CREATE OR REPLACE FUNCTION public.save_inventory_resource_internal(p_occasion bigint,p_expected_version bigint,p_resource jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected after pool'; END $$");
 await db.query('SET LOCAL ROLE authenticated');let ex=executor(db,f);assert.equal((await ex.prepare()).ok,false);
 await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) n from inventory_pools where occasion=$1',[f.occasion])).rows[0].n),0);
 await db.query('ROLLBACK TO SAVEPOINT original_owner');await db.query('RELEASE SAVEPOINT original_owner');
 await db.query('SAVEPOINT original_link_owner');
 await db.query("CREATE OR REPLACE FUNCTION public.update_product_inventory_contexts_internal_v1(p_product_id bigint,p_contexts jsonb) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected after resource'; END $$");
 await db.query('SET LOCAL ROLE authenticated');assert.equal((await executor(db,f).prepare()).ok,false);
 await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) n from resources where occasion=$1',[f.occasion])).rows[0].n),0);
 assert.equal(Number((await db.query('select count(*) n from inventory_pools where occasion=$1',[f.occasion])).rows[0].n),0);
 await db.query('ROLLBACK TO SAVEPOINT original_link_owner');await db.query('RELEASE SAVEPOINT original_link_owner');

 await db.query(`update occasions set features='[{"code":"blueprint","is_enabled":true}]' where id=$1`,[f.occasion]);
 const blueprint=Number((await db.query("insert into eshop.blueprints(occasion,organization,title,objects) values($1,$2,'Existing addressed seats','[]') returning id",[f.occasion,f.org])).rows[0].id);
 const order=Number((await db.query("insert into eshop.orders(occasion,order_sequence,order_symbol,state,price,currency_code,data) values($1,next_order_sequence($1),generate_order_symbol(),'paid',100,'CZK','{}') returning id",[f.occasion])).rows[0].id);
 const ticket=Number((await db.query("insert into eshop.tickets(occasion,state) values($1,'paid') returning id",[f.occasion])).rows[0].id);
 const item=Number((await db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3) returning id',[order,ticket,f.product])).rows[0].id);
 const seat=Number((await db.query("insert into eshop.spots(occasion,product,order_product_ticket,title) values($1,$2,$3,'Addressed seat') returning id",[f.occasion,f.product,item])).rows[0].id);
 await db.query('update eshop.spots set blueprint=$2 where id=$1',[seat,blueprint]);
 await db.query('insert into eshop.blueprint_seat_bindings(blueprint,node_id,spot) values($1,gen_random_uuid(),$2)',[blueprint,seat]);
 const before=(await db.query('select to_jsonb(o) value from eshop.orders o where id=$1',[order])).rows[0].value;
 await db.query('SET LOCAL ROLE authenticated');ex=executor(db,f);
 const rejectedId=randomUUID();const rejected=await ex.prepare({capacity:0,commandId:rejectedId});assert.equal(rejected.error.code,'STANDING_INVENTORY_REJECTED',JSON.stringify(rejected));
 assert.equal((await ex.prepare({capacity:0,commandId:rejectedId})).error.code,'STANDING_INVENTORY_REJECTED');
 await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) n from inventory_pools where occasion=$1',[f.occasion])).rows[0].n),0);
 await db.query('SET LOCAL ROLE authenticated');const result=await ex.prepare({capacity:2});assert.equal(result.ok,true,JSON.stringify(result));
 assert.equal(result.data.preparation.product.purchased_count,1);assert.equal(result.data.preparation.product.ordered_count,1);
 await db.query('RESET ROLE');const context=result.data.preparation.context.id;
 assert.equal(Number((await db.query('select count(*) n from eshop.spots where inventory_context=$1 and order_product_ticket=$2',[context,item])).rows[0].n),1);
 assert.equal(Number((await db.query('select order_product_ticket from eshop.spots where id=$1',[seat])).rows[0].order_product_ticket),item);
 assert.deepEqual((await db.query('select to_jsonb(o) value from eshop.orders o where id=$1',[order])).rows[0].value,before);
});

test('competing preparations serialize on the product; one winner creates stock and the other conflicts',options,async t=>{
 const first=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL),second=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);let f;
 t.after(async()=>{
  await first.query('ROLLBACK');await second.query('ROLLBACK');await second.end();
  if(f) {
   await first.query('BEGIN');
   await first.query('delete from client_mutation_receipts where occasion=$1',[f.occasion]);
   for(const table of ['client_commit_items','client_commit_components']) await first.query(`delete from ${table} where commit_id in(select commit_id from client_commits where occasion=$1)`,[f.occasion]);
   await first.query('delete from client_commits where occasion=$1',[f.occasion]);
   await first.query("delete from client_aggregate_versions where scope_type='occasion' and scope_id=ANY($1::bigint[])",[f.occasions]);
   for(const sql of ['delete from eshop.spots where occasion=ANY($1::bigint[])','delete from resources where occasion=ANY($1::bigint[])',
    'delete from inventory_contexts where inventory_pool in(select id from inventory_pools where occasion=ANY($1::bigint[]))',
    'delete from inventory_pools where occasion=ANY($1::bigint[])','delete from eshop.products where occasion=ANY($1::bigint[])',
    'delete from eshop.product_types where occasion=ANY($1::bigint[])','delete from places where occasion=ANY($1::bigint[])',
    'delete from occasion_users where occasion=ANY($1::bigint[])','delete from occasion_link_reservations where occasion=ANY($1::bigint[])','delete from occasions where id=ANY($1::bigint[])']) await first.query(sql,[f.occasions]);
   await first.query("delete from abuse_policy_overrides where (target_kind='unit' and target_id=$1) or (target_kind='organization' and target_id=$2)",[f.unit,f.org]);
   await first.query('delete from unit_users where unit=$1',[f.unit]);await first.query('delete from units where id=$1',[f.unit]);
   await first.query('delete from user_info where id=$1',[f.actor]);await first.query('delete from auth.users where id=$1',[f.actor]);await first.query('delete from organizations where id=$1',[f.org]);await first.query('COMMIT');
  }
  await first.end();
 });
 await first.query('BEGIN');await install(first);f=await productFixture(first);f.occasions=(await first.query('select id from occasions where organization=$1',[f.org])).rows.map(r=>r.id);
 const replayProduct=Number((await first.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Concurrent replay',100,'CZK') returning id",[f.occasion,f.type])).rows[0].id);
 await first.query('COMMIT');
 for(const db of [first,second]) {await db.query('BEGIN');await db.query('set local statement_timeout=5000');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);}
 await first.query('SET LOCAL ROLE authenticated');const one=executor(first,f),two=executor(second,f);
 const winner=await one.prepare();assert.equal(winner.ok,true,JSON.stringify(winner));
 await second.query('SET LOCAL ROLE authenticated');const pending=two.prepare();
 let blocked=false;
 await first.query('RESET ROLE');
 for(let n=0;n<50;n++) {
  if((await first.query('select wait_event_type from pg_stat_activity where pid=$1',[second.processID])).rows[0]?.wait_event_type==='Lock') {blocked=true;break;}
  await new Promise(r=>setTimeout(r,20));
 }
 assert(blocked,'second command must wait on actual first preparation');await first.query('COMMIT');
 const loser=await pending;assert.equal(loser.error.code,'PRODUCT_CHANGED_RELOAD_REQUIRED',JSON.stringify(loser));
 await second.query('ROLLBACK');
 assert.equal(Number((await first.query('select count(*) n from inventory_pools where occasion=$1',[f.occasion])).rows[0].n),1);
 // A second product qualifies same-UUID overlap independently of the conflict.
 for(const db of [first,second]) {await db.query('BEGIN');await db.query('set local statement_timeout=5000');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');}
 const same={productId:replayProduct,commandId:randomUUID()};const original=await one.prepare(same);assert.equal(original.ok,true,JSON.stringify(original));
 const replaying=two.prepare(same);await first.query('RESET ROLE');blocked=false;
 for(let n=0;n<50;n++) {
  if((await first.query('select wait_event_type from pg_stat_activity where pid=$1',[second.processID])).rows[0]?.wait_event_type==='Lock') {blocked=true;break;}
  await new Promise(r=>setTimeout(r,20));
 }
 assert(blocked,'same command must wait for its in-flight receipt');await first.query('COMMIT');
 assert.deepEqual((await replaying).data,original.data);await second.query('ROLLBACK');
 assert.equal(Number((await first.query('select count(*) n from inventory_pools where occasion=$1',[f.occasion])).rows[0].n),2);
});

for(const name of ['eshop/standing_existing_product_inventory_test.sql','eshop/inventory_command_boundaries_test.sql','eshop/inventory_resource_safety_test.sql']) {
 test(`inventory regression: ${name}`,options,async t=>{
  const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);
  await db.query('SET LOCAL ROLE postgres');await db.query("select set_config('request.jwt.claim.role','service_role',true)");
  await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
  await db.query(await readFile(new URL('../../../database/tests/'+name,import.meta.url),'utf8'));
 });
}


test('runtime source parity and grants for the shared inventory owners',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);
 await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
 const owners=['save_inventory_pool_internal','update_inventory_pool_bundle_internal_v1','save_inventory_resource_internal','save_resource_client_sync_v1','prepare_standing_inventory'];
 const contract=await readFile(new URL('../../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url),'utf8');
 const assertions=contract.split('\n').filter(line=>owners.some(name=>line.includes("to_regprocedure('public."+name+'(')));
 assert.equal(assertions.length,owners.length);await db.query('DO $$ BEGIN\n'+assertions.join('\n')+'\nEND $$;');
 for(const role of ['anon','service_role']) assert.equal((await db.query("select has_function_privilege($1,'prepare_standing_inventory(bigint,bigint,bigint,bigint,bigint,integer,uuid)','execute') allowed",[role])).rows[0].allowed,false);
 for(const signature of ['save_inventory_pool_internal(jsonb)','save_inventory_resource_internal(bigint,bigint,jsonb)']) assert.equal((await db.query("select has_function_privilege('authenticated',$1,'execute') allowed",[signature])).rows[0].allowed,false);
});
