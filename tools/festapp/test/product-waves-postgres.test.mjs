import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { fixture } from '../../../automation/authorization/benchmark.mjs';
import { openDisposableDatabase } from './postgres.mjs';
import { Operations } from '../src/operations/catalog.mjs';
import { productScheduleDescriptors } from '../src/operations/product-schedules.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};
const migration=new URL('../../../supabase/migrations/20261023170000_product_schedule_commands.sql',import.meta.url);
const future=days=>new Date(Date.now()+days*86400000).toISOString();
async function install(db) {await db.query(await readFile(new URL('../../../supabase/migrations/20261023163000_product_admin_read_semantics.sql',import.meta.url),'utf8'));await db.query(await readFile(migration,'utf8'));await db.query(await readFile(new URL('../../../supabase/migrations/20261023190000_inventory_summary_reads.sql',import.meta.url),'utf8'));await db.query(await readFile(new URL('../../../supabase/migrations/20261023210000_product_authoring_options.sql',import.meta.url),'utf8'));}
function executor(db,f) {
 const stats={requests:0,bytes:0,lose:false,replies:[]};
 const owner={root:'/tmp/festapp-wave-fixture',profile:{organizationId:f.org,tenantId:'fixture',name:'fixture',backendOrigin:'http://127.0.0.1:61022'},allowedOperations:productScheduleDescriptors.map(d=>d.id),delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),
 authorized:action=>action({rpc:async(name,args)=>{
  stats.requests++;await db.query('SAVEPOINT rpc');
  try {
   const read=name==='get_product_schedule';assert(read||name==='manage_product_schedule');
   const data=(await db.query(read?'select get_product_schedule($1,$2,$3,$4,$5) value':'select manage_product_schedule($1,$2,$3,$4,$5,$6) value',read?[args.p_occasion,args.p_organization,args.p_unit,args.p_after,args.p_limit]:[args.p_occasion,args.p_organization,args.p_unit,args.p_action,args.p_payload,args.p_command_id])).rows[0].value;
   await db.query('RELEASE SAVEPOINT rpc');const bytes=Buffer.byteLength(JSON.stringify(data));stats.bytes+=bytes;stats.replies.push({rpc:name,action:args.p_action??null,code:data.code??200,waves:data.waves?.length??null,jsonBytes:bytes});
   if(stats.lose&&!read){stats.lose=false;return {error:{code:'ECONNRESET',status:503}};}
   return {data,error:null};
  } catch(e) {await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return {error:{code:e.code,status:e.code==='42501'?403:400}};}
 }},{userId:f.actor})};
 const ops=new Operations(owner);
 return {owner,stats,list:args=>ops.invoke('product_schedules.list',{occasionId:f.occasion,...args}),change:(command,commandId=randomUUID())=>ops.invoke('product_schedules.change',{occasionId:f.occasion,commandId,command})};
}

test('MCP scheduling uses UI domain owners with atomic first target, normalized receipts, conflicts and scoped replay',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');
 t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await fixture(db,2);
 const other=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);
 const type=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Products','entry') returning id",[f.occasion])).rows[0].id);
 const product=Number((await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Admission',100,'CZK') returning id",[f.occasion,type])).rows[0].id);
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);
 assert.deepEqual((await ex.list()).data.waves,[]);
 const time=future(10);const command={action:'save_new_target',product_id:product,change_time:time,price:'200.00',is_hidden:false,expected_price_revision:null,expected_visibility_revision:null};
 const commandId=randomUUID();ex.stats.lose=true;const before=ex.stats.requests;
 const lost=await ex.change(command,commandId);assert.equal(lost.error.retryable,true);
 const created=await ex.change(command,commandId);assert.equal(created.ok,true,JSON.stringify(created));
 assert.equal(ex.stats.requests-before,2,'one domain request per attempt');
 const waveId=created.data.waveId;assert.equal(created.data.wave.id,waveId);assert.equal(created.data.targets.length,2);
 assert.deepEqual((await ex.change(command,commandId)).data,created.data);
 await db.query('RESET ROLE');
 assert.equal(Number((await db.query('select count(*) n from eshop.product_price_waves where occasion=$1',[f.occasion])).rows[0].n),1);
 assert.equal(Number((await db.query('select count(*) n from eshop.planned_changes where subject_id=$1',[product])).rows[0].n),2);
 assert.equal(Number((await db.query('select count(*) n from client_mutation_receipts where command_id=$1',[commandId])).rows[0].n),1,'no outer second receipt');
 assert.equal(Number((await db.query("select count(*) n from client_commits where occasion=$1 and source='inventory.wave.target.save'",[f.occasion])).rows[0].n),1,'single sync publication');
 assert.equal(Number((await db.query('select price from eshop.products where id=$1',[product])).rows[0].price),100);
 await db.query('SET LOCAL ROLE authenticated');
 let listed=await ex.list();assert.equal(listed.ok,true,JSON.stringify(listed));assert.equal(listed.data.waves[0].pending_product_count,1);assert.equal(listed.data.waves[0].pending_change_count,2);
 const ui=(await db.query('select get_product_catalog($1,$2,$3) value',[f.org,f.occasion,f.unit])).rows[0].value.catalog;
 assert.deepEqual(ui.price_waves,listed.data.waves);
 const edit={action:'save_target',product_id:product,wave_id:waveId,expected_wave_revision:1,price:'210.00',is_hidden:null,expected_price_revision:1,expected_visibility_revision:1};
 let result=await ex.change(edit);assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.targets.length,1);assert.equal(result.data.targets[0].revision,2);
 const conflictId=randomUUID();assert.equal((await ex.change(edit,conflictId)).error.code,'PRODUCT_SCHEDULE_CHANGED_RELOAD_REQUIRED');
 assert.equal((await ex.change(edit,conflictId)).error.code,'PRODUCT_SCHEDULE_CHANGED_RELOAD_REQUIRED','conflict itself is receipted');
 const move={action:'move_wave',wave_id:waveId,expected_wave_revision:1,change_time:future(11)};
 const moveId=randomUUID();result=await ex.change(move,moveId);assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.wave.revision,2);assert.deepEqual((await ex.change(move,moveId)).data,result.data);
 assert.equal((await ex.change({...move,change_time:future(12)})).error.code,'PRODUCT_SCHEDULE_CHANGED_RELOAD_REQUIRED');
 const cancel={action:'cancel_wave',wave_id:waveId,expected_wave_revision:2};const cancelId=randomUUID();
 result=await ex.change(cancel,cancelId);assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.wave,null);assert.deepEqual((await ex.change(cancel,cancelId)).data,result.data,'replay after wave deletion');
 assert.deepEqual((await ex.list()).data.waves,[]);
 const standaloneId=randomUUID();const standalone={action:'create_price_change',product_id:product,price:'130',change_time:future(12)};
 result=await ex.change(standalone,standaloneId);assert.equal(result.ok,true,JSON.stringify(result));const changeId=result.data.change.id;
 assert.deepEqual((await ex.change(standalone,standaloneId)).data,result.data);
 result=await ex.change({action:'save_price_change',product_id:product,change_id:changeId,expected_revision:1,price:'140',change_time:standalone.change_time});assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.change.revision,2);
 assert.equal((await ex.change({action:'cancel_price_change',product_id:product,change_id:changeId,expected_revision:1})).error.code,'PRODUCT_SCHEDULE_CHANGED_RELOAD_REQUIRED');
 const cancelPriceId=randomUUID();const cancelPrice={action:'cancel_price_change',product_id:product,change_id:changeId,expected_revision:2};
 result=await ex.change(cancelPrice,cancelPriceId);assert.equal(result.ok,true,JSON.stringify(result));assert.deepEqual((await ex.change(cancelPrice,cancelPriceId)).data,result.data);
 // Validation fails after term creation, rolling back the term and its children.
 const rejectedId=randomUUID();const invalid={...command,change_time:future(13),price:'99999999.99'};
 await db.query('RESET ROLE');await db.query("update eshop.products set data='{\"deposit\":{\"amount\":99999999.99}}' where id=$1",[product]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await ex.change(invalid,rejectedId)).error.code,'PRODUCT_SCHEDULE_REJECTED');
 assert.equal((await ex.change(invalid,rejectedId)).error.code,'PRODUCT_SCHEDULE_REJECTED');
 assert.equal((await ex.list()).data.waves.length,0,'failed first target leaves no empty wave');
 const scope=ex.owner.delegatedContext;ex.owner.delegatedContext=async()=>({organizationId:f.org,unitId:f.unit+99999});
 assert.equal((await ex.change(cancel,cancelId)).error.code,'FORBIDDEN');assert.equal((await ex.list()).error.code,'FORBIDDEN');ex.owner.delegatedContext=scope;
 await db.query('RESET ROLE');
 const foreignWave=Number((await db.query('insert into eshop.product_price_waves(occasion,change_time) values($1,$2) returning id',[other,future(14)])).rows[0].id);
 await db.query('SET LOCAL ROLE authenticated');assert.equal((await ex.change({action:'cancel_wave',wave_id:foreignWave,expected_wave_revision:1})).error.code,'FORBIDDEN');
 await db.query('RESET ROLE');await db.query('update unit_users set is_manager=false,is_editor=false where unit=$1 and "user"=$2',[f.unit,f.actor]);await db.query('update occasion_users set is_manager=false,is_editor=false,is_editor_order=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await ex.change(cancel,cancelId)).error.code,'FORBIDDEN','rights are rechecked before replay');
 await db.query('RESET ROLE');
 assert.equal((await db.query("select has_function_privilege('anon','manage_product_schedule(bigint,bigint,bigint,text,jsonb,uuid)','execute') allowed")).rows[0].allowed,false);
 assert.equal((await db.query("select has_function_privilege('service_role','manage_product_schedule(bigint,bigint,bigint,text,jsonb,uuid)','execute') allowed")).rows[0].allowed,false);
 t.diagnostic('product-schedule-data-audit '+JSON.stringify({fixture:'domain-actions',attempts:ex.stats.requests,replies:ex.stats.replies}));
});

test('wave read is bounded and identical to the administration term projection',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await fixture(db,1);
 await db.query("insert into eshop.product_price_waves(occasion,change_time) select $1,now()+n*interval '1 day' from generate_series(1,125) n",[f.occasion]);
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);let after;const waves=[];
 do {const r=await ex.list({limit:50,...(after?{after}:{})});assert.equal(r.ok,true,JSON.stringify(r));assert(r.data.waves.length<=50);waves.push(...r.data.waves);after=r.data.nextCursor;}while(after);
 assert.equal(waves.length,125);assert.equal(ex.stats.requests,3);assert.equal(new Set(waves.map(w=>w.id)).size,125);
 assert.deepEqual(waves,(await db.query('select get_product_catalog($1,$2,$3) value',[f.org,f.occasion,f.unit])).rows[0].value.catalog.price_waves);
 t.diagnostic('product-schedule-data-audit '+JSON.stringify({fixture:'125-wave-pages',attempts:ex.stats.requests,replies:ex.stats.replies}));
});

test('scheduler and wave move use sorted product locks with two real connections',options,async t=>{
 const admin=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
 const scheduler=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);let f;
 t.after(async()=>{
  await admin.query('ROLLBACK');await scheduler.query('ROLLBACK');await scheduler.end();
  if(f) {
   await admin.query('BEGIN');
   for(const sql of ['delete from eshop.planned_changes where occasion=$1','delete from eshop.product_price_waves where occasion=$1',
    'delete from eshop.products where occasion=$1','delete from eshop.product_types where occasion=$1','delete from places where occasion=$1',
    'delete from occasion_users where occasion=$1','delete from occasion_link_reservations where occasion=$1','delete from occasions where id=$1']) await admin.query(sql,[f.occasion]);
   await admin.query("delete from abuse_policy_overrides where (target_kind='unit' and target_id=$1) or (target_kind='organization' and target_id=$2)",[f.unit,f.org]);
   await admin.query('delete from unit_users where unit=$1',[f.unit]);await admin.query('delete from units where id=$1',[f.unit]);
   await admin.query('delete from user_info where id=$1',[f.actor]);await admin.query('delete from auth.users where id=$1',[f.actor]);await admin.query('delete from organizations where id=$1',[f.org]);await admin.query('COMMIT');
  }
  await admin.end();
 });
 await admin.query('BEGIN');await install(admin);f=await fixture(admin,1);
 const type=Number((await admin.query("insert into eshop.product_types(occasion,title,type) values($1,'Concurrent','entry') returning id",[f.occasion])).rows[0].id);
 const ids=(await admin.query("insert into eshop.products(occasion,product_type,title,price,currency_code) select $1,$2,'Product '||n,10,'CZK' from generate_series(1,2) n returning id",[f.occasion,type])).rows.map(r=>Number(r.id));
 const wave=Number((await admin.query('insert into eshop.product_price_waves(occasion,change_time) values($1,$2) returning id',[f.occasion,future(15)])).rows[0].id);
 // Deliberately reverse due-time order relative to product ID.
 await admin.query("insert into eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion) values('products.price',$1,'202',now()-interval '2 minutes',$3),('products.price',$2,'101',now()-interval '1 minute',$3)",[ids[1],ids[0],f.occasion]);
 await admin.query("insert into eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion,wave_id) select 'products.price',unnest($1::bigint[]),'300',$2,$3,$4",[ids,future(15),f.occasion,wave]);
 await admin.query('COMMIT');
 await admin.query('BEGIN');await admin.query('set local statement_timeout=5000');await admin.query('select 1 from eshop.products where id=$1 for update',[ids[0]]);
 await scheduler.query('BEGIN');await scheduler.query('set local statement_timeout=5000');await scheduler.query("select set_config('request.jwt.claim.role','service_role',true)");await scheduler.query('SET LOCAL ROLE service_role');
 let schedulerFailure;const running=scheduler.query('select apply_planned_changes_client_sync_v1()').catch(e=>{schedulerFailure=e;});
 let blocked=false;
 for(let n=0;n<50;n++) {
  if((await admin.query('select wait_event_type from pg_stat_activity where pid=$1',[scheduler.processID])).rows[0]?.wait_event_type==='Lock') {blocked=true;break;}
  await new Promise(r=>setTimeout(r,20));
 }
 assert(blocked,'actual scheduler must wait while the wave owner holds the first product');
 await admin.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await admin.query('SET LOCAL ROLE authenticated');
 const ex=executor(admin,f);const result=await ex.change({action:'move_wave',wave_id:wave,expected_wave_revision:1,change_time:future(16)});
 assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.wave.revision,2);
 await admin.query('ROLLBACK');await running;assert.equal(schedulerFailure,undefined);
 await scheduler.query('RESET ROLE');
 assert.deepEqual((await scheduler.query('select price::text from eshop.products where id=ANY($1::bigint[]) order by id',[ids])).rows.map(r=>Number(r.price)),[101,202]);
 const commits=Number((await scheduler.query("select count(*) n from client_commits where occasion=$1 and source='inventory.product.planned'",[f.occasion])).rows[0].n);
 assert.equal(commits,2);
 await scheduler.query('SET LOCAL ROLE service_role');await scheduler.query('select apply_planned_changes_client_sync_v1()');await scheduler.query('RESET ROLE');
 assert.equal(Number((await scheduler.query("select count(*) n from client_commits where occasion=$1 and source='inventory.product.planned'",[f.occasion])).rows[0].n),2,'scheduler retry does not duplicate sync');
});


for(const name of ['eshop/product_price_scheduling_test.sql','eshop/product_price_waves_test.sql',
 'eshop/product_wave_blueprint_guard_test.sql','eshop/atomic_wave_target_test.sql',
 'eshop/product_price_sync_failure_test.sql','eshop/integration/product_price_scheduling_flow_test.sql',
 ]) {
 test(`canonical SQL regression: ${name}`,options,async t=>{
  const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');
  t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);
  await db.query('SET LOCAL ROLE postgres');
  await db.query("select set_config('request.jwt.claim.role','service_role',true)");
  await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
  const sql=await readFile(new URL('../../../database/tests/'+name,import.meta.url),'utf8');
  for(const [,source] of sql.matchAll(/^-- test-setup: (database\/[\w./-]+\.sql)$/gm)) await db.query(await readFile(new URL('../../../'+source,import.meta.url),'utf8'));
  await db.query(sql);
 });
}


test('runtime source parity for changed schedule and catalog owners',options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');
 t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);
 await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
 const contract=await readFile(new URL('../../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url),'utf8');
 const owners=['get_product_catalog_data_internal','get_products_and_types_for_edit','save_product_wave_target_client_sync_v1',
  'manage_product_schedule','get_product_price_waves_internal','get_product_schedule','apply_planned_changes_client_sync_v1','apply_planned_changes'];
 const assertions=contract.split('\n').filter(line=>owners.some(name=>line.includes("to_regprocedure('public."+name+'(')));
 assert.equal(assertions.length,owners.length);
 await db.query('DO $$ BEGIN\n'+assertions.join('\n')+'\nEND $$;');
});
