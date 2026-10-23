import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
import {openDisposableDatabase} from './postgres.mjs';
import {Operations} from '../src/operations/catalog.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};
async function install(db){for(const name of ['20261023163000_product_admin_read_semantics.sql','20261023170000_product_schedule_commands.sql','20261023180000_atomic_standing_inventory.sql','20261023190000_inventory_summary_reads.sql','20261023200000_inventory_authoring_commands.sql'])await db.query(await readFile(new URL('../../../supabase/migrations/'+name,import.meta.url),'utf8'));}
function executor(db,f){
 const stats={calls:[],lose:false};
 const owner={root:'/tmp/festapp-stock-authoring',profile:{organizationId:f.org,tenantId:'fixture',name:'fixture',backendOrigin:'http://127.0.0.1:61022'},allowedOperations:['inventory.change','inventory.pools.inspect','inventory.resources.list'],delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized:action=>action({rpc:async(name,args)=>{
  const request={name,args};stats.calls.push(request);await db.query('SAVEPOINT rpc');try{
   let data;
   if(name==='manage_inventory')data=(await db.query('select manage_inventory($1,$2,$3,$4,$5,$6,$7) value',[args.p_occasion,args.p_organization,args.p_unit,args.p_action,args.p_payload,args.p_command_id,args.p_editor])).rows[0].value;
   else if(name==='get_inventory_pool_settings')data=(await db.query('select get_inventory_pool_settings($1,$2,$3,$4) value',[args.p_occasion,args.p_organization,args.p_unit,args.p_pool])).rows[0].value;
   else {assert.equal(name,'get_inventory_resources');data=(await db.query('select get_inventory_resources($1,$2,$3,$4,$5,$6) value',[args.p_occasion,args.p_organization,args.p_unit,args.p_pool,args.p_after,args.p_limit])).rows[0].value;}
   request.sqlJsonBytes=Buffer.byteLength(JSON.stringify(data));
   if(name==='manage_inventory'){assert.equal(data.sync,undefined);if(data.data?.resource){assert.equal(data.data.resource.data,undefined);assert.equal(data.data.resource.slots,undefined);}}
   await db.query('RELEASE SAVEPOINT rpc');if(stats.lose&&name==='manage_inventory'){stats.lose=false;return {error:{code:'ECONNRESET',status:503}};}return {data,error:null};
  }catch(e){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return {error:{code:e.code,status:e.code==='42501'?403:400}};}
 }},{userId:f.actor})};const ops=new Operations(owner);
 return {stats,owner,change:(command,commandId=randomUUID())=>ops.invoke('inventory.change',{occasionId:f.occasion,commandId,command}),inspect:poolId=>ops.invoke('inventory.pools.inspect',{occasionId:f.occasion,poolId}),resources:(poolId,after,limit=50)=>ops.invoke('inventory.resources.list',{occasionId:f.occasion,poolId,...(after?{after}:{}),limit})};
}
const pool=(f,title=null)=>({occasion:f.occasion,title,description:null,type:null,sellable_capacity:null,data:{is_auto_resource_assignment:true}});
async function transaction(t){const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await fixture(db,2);await db.query('SET LOCAL ROLE authenticated');return {db,f,ex:executor(db,f)};}
function success(result){assert.equal(result.ok,true,JSON.stringify(result));return result.data;}

test('stock authoring shares one pool receipt across retries and UI rules, without full-editor MCP snapshots',options,async t=>{
 const {db,f,ex}=await transaction(t);const command={action:'save_pool',expectedVersion:null,bundle:{pool:pool(f),contexts:[{title:'Day',block_date:null,order:1,data:null}]}};const uuid=randomUUID();
 ex.stats.lose=true;assert.equal((await ex.change(command,uuid)).ok,false);const saved=success(await ex.change(command,uuid));
 const id=saved.pool.pool.id;assert.equal(saved.version,1);assert.equal(saved.pool.contexts.length,1);assert.equal(saved.pool.resources,undefined);assert.equal(saved.pool.products,undefined);
 assert.deepEqual(success(await ex.change(command,uuid)),saved);
 await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) from inventory_pools where occasion=$1',[f.occasion])).rows[0].count),1);await db.query('SET LOCAL ROLE authenticated');
 assert.deepEqual(success(await ex.inspect(id)).settings,saved.pool);
 const resource=success(await ex.change({action:'save_resource',expectedVersion:null,resource:{inventory_pool:id,title:'Supply',capacity:4,booking_rules:{}}})).resource;
 assert.equal(resource.aggregate_version,1);assert.deepEqual(success(await ex.resources(id)).resources,[resource]);
 const current=success(await ex.inspect(id)).settings;
 const uiCommand={bundle:{pool:{...current.pool,title:'Updated'},contexts:current.contexts},expectedVersion:current.aggregate_version};
 const uiId=randomUUID();const ui=(await db.query("select manage_inventory($1,$2,$3,'save_pool',$4,$5,true) value",[f.occasion,f.org,f.unit,uiCommand,uiId])).rows[0].value;
 const legacy=(await db.query('select save_inventory_pool_client_sync_v1($1,$2,$3,$4) value',[f.occasion,uiId,uiCommand.expectedVersion,uiCommand.bundle])).rows[0].value;assert.deepEqual(legacy,ui);
 await db.query('RESET ROLE');const rawPool=(await db.query('select to_jsonb(ip) value from inventory_pools ip where id=$1',[id])).rows[0].value;await db.query('SET LOCAL ROLE authenticated');assert.deepEqual(ui.data.bundle.pool,rawPool);
 assert.equal(ui.status,'applied');assert.equal(ui.data.bundle.resources.length,1);assert(ui.data.bundle.places.length>0);assert.equal(ui.data.bundle.pool.title,'Updated');
 const editor=(await db.query('select get_inventory_pool_for_edit($1,$2,$3,$4) value',[f.occasion,f.org,f.unit,id])).rows[0].value;assert.deepEqual(editor.pool,ui.data.bundle.pool);assert.deepEqual(editor.resources,ui.data.bundle.resources);
 const latest=success(await ex.inspect(id)).settings;assert.equal(latest.pool.title,ui.data.bundle.pool.title);assert.equal(latest.aggregate_version,ui.data.version);
 assert.equal((await ex.change({action:'save_pool',expectedVersion:current.aggregate_version,bundle:{pool:current.pool}})).error.code,'INVENTORY_CHANGED_RELOAD_REQUIRED');
 const unchanged=success(await ex.change({action:'save_pool',expectedVersion:latest.aggregate_version,bundle:{pool:latest.pool}}));assert.equal(unchanged.status,'unchanged');assert.equal(unchanged.version,latest.aggregate_version);
 // The new compact mode cannot replay the legacy response under the same UUID.
 await db.query('SAVEPOINT mode');await assert.rejects(db.query('select save_inventory_pool_client_sync_v1($1,$2,NULL,$3)',[f.occasion,uuid,command.bundle]));await db.query('ROLLBACK TO SAVEPOINT mode');await db.query('RELEASE SAVEPOINT mode');
 assert(ex.stats.calls.filter(c=>c.name==='manage_inventory').every(c=>c.args.p_editor===false));
 t.diagnostic('inventory-authoring-json '+JSON.stringify({compactPoolCreateSqlBytes:ex.stats.calls[0].sqlJsonBytes,editorPoolSaveSqlBytes:Buffer.byteLength(JSON.stringify(ui)),domainRpcCalls:ex.stats.calls.length,interpretation:'Serialized SQL JSON; different save outcomes, same fixture. Not HTTP wire traffic or a latency benchmark.'}));
});

test('held stock cannot disappear through pool/context/resource commands; untitled pools can be deleted',options,async t=>{
 const {db,f,ex}=await transaction(t);
 const settings=success(await ex.change({action:'save_pool',expectedVersion:null,bundle:{pool:pool(f),contexts:[{title:null,block_date:null,order:null,data:null}]}})).pool;
 const id=settings.pool.id;const resource=success(await ex.change({action:'save_resource',expectedVersion:null,resource:{inventory_pool:id,title:'Supply',capacity:4,booking_rules:{}}})).resource;
 await db.query('RESET ROLE');await db.query("update eshop.spots set secret=gen_random_uuid(),secret_expiration_time=now()+interval '1 hour' where id=(select id from eshop.spots where inventory_context=$1 order by id limit 1)",[settings.contexts[0].id]);await db.query('SET LOCAL ROLE authenticated');
 const latest=success(await ex.inspect(id)).settings;
 for(const command of [
  {action:'save_pool',expectedVersion:latest.aggregate_version,bundle:{pool:latest.pool,contexts:[]}},
  {action:'save_resource',expectedVersion:resource.aggregate_version,resource:{id:resource.id,inventory_pool:id,title:'Supply',capacity:0,booking_rules:{}}},
  {action:'delete_resource',expectedVersion:resource.aggregate_version,id:resource.id},
  {action:'delete_pool',expectedVersion:latest.aggregate_version,id},
 ])assert.equal((await ex.change(command)).error.code,'INVENTORY_INTENTION_REJECTED');
 await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) from eshop.spots where inventory_context=$1',[settings.contexts[0].id])).rows[0].count),4);await db.query('SET LOCAL ROLE authenticated');
 assert.equal(success(await ex.inspect(id)).settings.contexts.length,1);
 await db.query('RESET ROLE');await db.query('update eshop.spots set secret=null,secret_expiration_time=null where inventory_context=$1',[settings.contexts[0].id]);await db.query('SET LOCAL ROLE authenticated');
 const command={action:'delete_pool',expectedVersion:latest.aggregate_version,id};const uuid=randomUUID();const removed=success(await ex.change(command,uuid));assert.equal(removed.status,'applied');assert.equal(removed.deletedId,id);assert.deepEqual(success(await ex.change(command,uuid)),removed);
 await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) from inventory_pools where id=$1',[id])).rows[0].count),0);
});

test('authoring reads bound resource pages, reject truncated context replacements and preserve actual scope',options,async t=>{
 const {db,f,ex}=await transaction(t);const id=success(await ex.change({action:'save_pool',expectedVersion:null,bundle:{pool:pool(f,'Paged')}})).pool.pool.id;
 await db.query('RESET ROLE');const resources=(await db.query("insert into resources(occasion,inventory_pool,title,capacity) select $1,$2,'Resource '||n,0 from generate_series(1,125)n returning id",[f.occasion,id])).rows.map(r=>Number(r.id));await db.query('SET LOCAL ROLE authenticated');
 const seen=[];let after;do{const page=success(await ex.resources(id,after));seen.push(...page.resources.map(r=>r.id));after=page.nextCursor;assert(page.resources.length<=50);assert(page.resources.every(r=>r.slots===undefined&&r.data===undefined));}while(after);assert.deepEqual(seen,resources);
 await db.query('RESET ROLE');await db.query('insert into inventory_contexts(inventory_pool) select $1 from generate_series(1,2001)',[id]);await db.query('SET LOCAL ROLE authenticated');assert.equal((await ex.inspect(id)).error.code,'INVENTORY_INTENTION_REJECTED');
 const largeEditor=(await db.query('select get_inventory_pool_for_edit($1,$2,$3,$4) value',[f.occasion,f.org,f.unit,id])).rows[0].value;assert.equal(largeEditor.contexts.length,2001,'full editor reads retain their existing complete-context boundary');
 await db.query('RESET ROLE');const foreign=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);const foreignId=Number((await db.query("insert into inventory_pools(occasion,title) values($1,'Foreign') returning id",[foreign])).rows[0].id);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await ex.inspect(foreignId)).error.code,'FORBIDDEN');assert.equal((await ex.resources(foreignId)).error.code,'FORBIDDEN');assert.equal((await ex.change({action:'delete_pool',expectedVersion:0,id:foreignId})).error.code,'FORBIDDEN');
 assert.equal((await ex.change({action:'save_resource',expectedVersion:null,resource:{inventory_pool:foreignId,title:'Bad',capacity:0,booking_rules:{}}})).error.code,'FORBIDDEN');
 await db.query('RESET ROLE');for(const signature of ['manage_inventory(bigint,bigint,bigint,text,jsonb,uuid,boolean)','get_inventory_pool_settings(bigint,bigint,bigint,bigint)','get_inventory_resources(bigint,bigint,bigint,bigint,bigint,integer)'])for(const role of ['anon','service_role'])assert.equal((await db.query('select has_function_privilege($1,$2,\'execute\') allowed',[role,signature])).rows[0].allowed,false);
});

test('two connections: a scope move during a pool save rolls back its state, version, publication and receipt',options,async t=>{
 const admin=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL),writer=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);let f;
 t.after(async()=>{await admin.query('ROLLBACK');await writer.query('ROLLBACK');await writer.end();if(f){await admin.query('BEGIN');
  await admin.query('delete from inventory_pools where occasion=$1',[f.occasion]);
  for(const table of ['places','occasion_users','occasion_link_reservations'])await admin.query(`delete from ${table} where occasion=$1`,[f.occasion]);
  await admin.query('delete from occasions where id=$1',[f.occasion]);await admin.query("delete from abuse_policy_overrides where (target_kind='unit' and target_id=$1) or (target_kind='organization' and target_id=$2)",[f.unit,f.org]);
  await admin.query('delete from unit_users where unit=$1',[f.unit]);await admin.query('delete from units where organization=$1',[f.org]);await admin.query('delete from user_info where id=$1',[f.actor]);await admin.query('delete from auth.users where id=$1',[f.actor]);await admin.query('delete from organizations where id=$1',[f.org]);await admin.query('COMMIT');}await admin.end();});
 await admin.query('BEGIN');await install(admin);f=await fixture(admin,1);
 const id=Number((await admin.query("insert into inventory_pools(occasion,title) values($1,'Original') returning id",[f.occasion])).rows[0].id);
 const otherUnit=Number((await admin.query("insert into units(organization,title) values($1,'Outside delegation') returning id",[f.org])).rows[0].id);await admin.query('COMMIT');
 await admin.query('BEGIN');await admin.query('update inventory_pools set title=title where id=$1',[id]);await admin.query('update occasions set unit=$2 where id=$1',[f.occasion,otherUnit]);
 await writer.query('BEGIN');await writer.query("set local statement_timeout='5s'");await writer.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await writer.query('SET LOCAL ROLE authenticated');
 const commandId=randomUUID();const denied=assert.rejects(writer.query("select manage_inventory($1,$2,$3,'save_pool',$4,$5,false)",[f.occasion,f.org,f.unit,{expectedVersion:0,bundle:{pool:{...pool(f,'Must roll back'),id}}},commandId]),e=>e.code==='42501');
 let blocked=false;for(let n=0;n<100;n++){if((await admin.query('select wait_event_type from pg_stat_activity where pid=$1',[writer.processID])).rows[0]?.wait_event_type==='Lock'){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}assert(blocked,'writer must enter domain locking before scope changes commit');
 await admin.query('COMMIT');await denied;await writer.query('ROLLBACK');
 assert.equal((await admin.query('select title from inventory_pools where id=$1',[id])).rows[0].title,'Original');
 assert.equal(Number((await admin.query("select count(*) from client_aggregate_versions where aggregate_type='inventory_pool' and aggregate_id=$1",[String(id)])).rows[0].count),0);
 assert.equal(Number((await admin.query('select count(*) from client_mutation_receipts where command_id=$1',[commandId])).rows[0].count),0);
 assert.equal(Number((await admin.query('select count(*) from client_commits where occasion=$1',[f.occasion])).rows[0].count),0);
});

test('authoring receipt owner, scope boundaries and compact read owners match canonical source',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);
 await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
 const owners=['get_inventory_pool_for_edit','get_inventory_pool_settings_data_internal','get_inventory_resource_rows_internal','get_inventory_pool_bundle','get_inventory_pool_settings_internal','inventory_pool_command_snapshot_internal','get_inventory_pool_settings','get_inventory_resources','save_inventory_pool_command_internal','save_inventory_pool_client_sync_v1','delete_inventory_pool_client_sync_v1','check_inventory_entity_scope_internal','manage_inventory'];
 const contract=await readFile(new URL('../../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url),'utf8');const assertions=contract.split('\n').filter(line=>owners.some(name=>line.includes("to_regprocedure('public."+name+'(')));assert.equal(assertions.length,owners.length);await db.query('DO $$ BEGIN\n'+assertions.join('\n')+'\nEND $$;');
 for(const signature of ['get_inventory_pool_settings_internal(bigint)','inventory_pool_command_snapshot_internal(bigint,boolean)','save_inventory_pool_command_internal(bigint,uuid,bigint,jsonb,boolean)','check_inventory_entity_scope_internal(bigint,bigint,bigint)'])for(const role of ['anon','authenticated','service_role'])assert.equal((await db.query('select has_function_privilege($1,$2,\'execute\') allowed',[role,signature])).rows[0].allowed,false);
});


test('a receipt issued by the pre-extraction pool API replays unchanged through the extracted UI owner',options,async t=>{
 const {db,f}=await transaction(t);
 const historical=await readFile(new URL('../../../supabase/migrations/20261021100000_canonical_authorization.sql',import.meta.url),'utf8');
 const definition=historical.match(/CREATE OR REPLACE FUNCTION public\.save_inventory_pool_client_sync_v1\([\s\S]*?\$function\$;/)?.[0];assert(definition,'retained deployed migration contains its original receipt owner');
 await db.query('RESET ROLE');await db.query(definition);await db.query('SET LOCAL ROLE authenticated');
 const commandId=randomUUID(),bundle={pool:pool(f,'Before extraction'),contexts:[]};
 const old=(await db.query('select save_inventory_pool_client_sync_v1($1,$2,NULL,$3) value',[f.occasion,commandId,bundle])).rows[0].value;assert.equal(old.status,'applied');
 await db.query('RESET ROLE');await db.query(await readFile(new URL('../../../database/functions/inventory/save_inventory_pool_client_sync_v1.sql',import.meta.url),'utf8'));await db.query('SET LOCAL ROLE authenticated');
 const replay=(await db.query("select manage_inventory($1,$2,$3,'save_pool',$4,$5,true) value",[f.occasion,f.org,f.unit,{bundle,expectedVersion:null},commandId])).rows[0].value;
 assert.deepEqual(replay,old);
});
