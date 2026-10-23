import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { fixture } from '../../../automation/authorization/benchmark.mjs';
import { openDisposableDatabase } from './postgres.mjs';
import { Operations } from '../src/operations/catalog.mjs';
import { productDescriptors } from '../src/operations/products.mjs';
async function install(db) {
 for(const name of ['20261023163000_product_admin_read_semantics.sql','20261023170000_product_schedule_commands.sql','20261023190000_inventory_summary_reads.sql'])
  await db.query(await readFile(new URL('../../../supabase/migrations/'+name,import.meta.url),'utf8'));
}


test('shared product UI/MCP SQL boundary preserves atomic stock save, scope, versions, replay and usage guards',
 { skip: !process.env.FESTAPP_MCP_TEST_DATABASE_URL }, async t => {
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL); await db.query('BEGIN');
 t.after(async()=>{await db.query('ROLLBACK');await db.end();});
 await install(db);
 await db.query('RESET ROLE'); const f=await fixture(db,2);
 const other=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);
 const otherUnit=Number((await db.query("insert into units(title,organization) values('Other organizer',$1) returning id",[f.org])).rows[0].id);
 await db.query('insert into unit_users(unit,"user",is_manager,is_editor) values($1,$2,true,true)',[otherUnit,f.actor]);
 const type=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Admission','entry') returning id",[f.occasion])).rows[0].id);
 const otherType=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Other','entry') returning id",[other])).rows[0].id);
 const pool=Number((await db.query("insert into inventory_pools(occasion,title) values($1,'Stock') returning id",[f.occasion])).rows[0].id);
 const context=Number((await db.query("insert into inventory_contexts(inventory_pool,title) values($1,'Stock context') returning id",[pool])).rows[0].id);
 const foreignPool=Number((await db.query("insert into inventory_pools(occasion,title) values($1,'Other') returning id",[other])).rows[0].id);
 const foreignContext=Number((await db.query("insert into inventory_contexts(inventory_pool,title) values($1,'Foreign') returning id",[foreignPool])).rows[0].id);
 await db.query('SET LOCAL ROLE authenticated');
 let lose=false, calls=0;
 const client={rpc:async(name,args)=>{
  calls++;await db.query('SAVEPOINT rpc');
  try {
   const values=name==='get_product_catalog_page'?[args.p_organization,args.p_occasion,args.p_unit,args.p_after,args.p_limit]:name==='get_product_catalog'?[args.p_organization,args.p_occasion??null,args.p_unit??null,args.p_occasion_link??null]:[args.p_occasion,args.p_organization,args.p_unit,args.p_action,args.p_product,args.p_command_id];
   assert(['get_product_catalog_page','get_product_catalog','manage_product'].includes(name));
   const sql=name==='get_product_catalog_page'?'select get_product_catalog_page($1,$2,$3,$4,$5) value':name==='get_product_catalog'?'select get_product_catalog($1,$2,$3,$4) value':'select manage_product($1,$2,$3,$4,$5,$6) value';
   const data=(await db.query(sql,values)).rows[0].value; await db.query('RELEASE SAVEPOINT rpc');
   if(lose && name==='manage_product'){lose=false;return {error:{code:'ECONNRESET',status:503}};}
   return {data,error:null};
  }catch(e){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return {error:{code:e.code,status:e.code==='42501'?403:400}};}
 }};
 const owner={root:'/tmp/festapp-products-test',profile:{organizationId:f.org,tenantId:'fixture',name:'fixture',backendOrigin:'http://127.0.0.1:61022'},allowedOperations:productDescriptors.map(d=>d.id),
  authorized:action=>action(client,{userId:f.actor}),delegatedContext:async()=>({organizationId:f.org,unitId:f.unit})};
 const ops=new Operations(owner);const invoke=(op,args={})=>ops.invoke(op,{occasionId:f.occasion,...args});
 const newProduct={title:'Lunch',price:'100.00',currency_code:'CZK',product_type:type,maximum:100,inventory_contexts:[{inventory_context_id:context,quantity:2}]};
 const create={commandId:randomUUID(),product:newProduct};
 let result=await invoke('products.save',create);assert.equal(result.ok,true,JSON.stringify(result));const productId=result.data.productId;
 assert.equal(calls,1,'combined product and inventory save is one domain request');
 const replay=await invoke('products.save',create);assert.deepEqual(replay.data,result.data);assert.equal(replay.data.productId,productId);
 assert.equal((await invoke('products.save',{...create,product:{...newProduct,title:'Changed UUID'}})).ok,false);
 let list=await invoke('products.list');assert.equal(list.ok,true,JSON.stringify(list));let product=list.data.products.find(p=>p.id===productId);
 assert.deepEqual(product.inventory_contexts,[{inventory_context_id:context,quantity:2}]);assert.equal(product.price,'100');
 assert.equal(list.data.productTypes[0].id,type);assert.equal(list.data.inventoryContexts[0].id,context);
 const ui=await client.rpc('get_product_catalog',{p_organization:f.org,p_occasion_link:f.link});assert.equal(ui.error,null);assert.equal(ui.data.catalog.products[0].aggregate_version,product.aggregate_version);
 // Current ProductModel.toJson includes a nullable occasion, unlike the MCP DTO.
 const uiWrite=await client.rpc('manage_product',{p_occasion:f.occasion,p_organization:f.org,p_unit:f.unit,p_action:'save',p_command_id:randomUUID(),
  p_product:{id:productId,occasion:null,title:product.title,expected_aggregate_version:product.aggregate_version}});
 assert.equal(uiWrite.error,null);assert.equal(uiWrite.data.code,200);product.aggregate_version=uiWrite.data.data.aggregate_version;
 const originalVersion=product.aggregate_version;
 const edit={commandId:randomUUID(),product:{id:productId,expected_aggregate_version:originalVersion,title:'Lunch updated',price:'120.00',inventory_contexts:[]}};
 lose=true;result=await invoke('products.save',edit);assert.equal(result.ok,false);assert.equal(result.error.retryable,true);
 result=await invoke('products.save',edit);assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.productId,productId);
 list=await invoke('products.list');product=list.data.products[0];assert.equal(product.title,'Lunch updated');assert.deepEqual(product.inventory_contexts,[]);assert.equal(product.aggregate_version,originalVersion+1);
 assert.equal((await invoke('products.save',{...edit,commandId:randomUUID()})).error.code,'PRODUCT_CHANGED_RELOAD_REQUIRED');
 const invalid={commandId:randomUUID(),product:{id:productId,expected_aggregate_version:product.aggregate_version,title:'Must roll back',inventory_contexts:[{inventory_context_id:foreignContext,quantity:1}]}};
 assert.equal((await invoke('products.save',invalid)).ok,false);
 assert.equal((await invoke('products.list')).data.products[0].title,'Lunch updated','invalid stock assignment rolls back product edit');
 assert.equal((await invoke('products.save',{commandId:randomUUID(),product:{...newProduct,product_type:otherType}})).error.code,'FORBIDDEN');
 const scope=owner.delegatedContext;owner.delegatedContext=async()=>({organizationId:f.org,unitId:f.unit+9999});
 assert.equal((await invoke('products.list')).error.code,'FORBIDDEN');assert.equal((await invoke('products.save',edit)).error.code,'FORBIDDEN');owner.delegatedContext=scope;
 // Reader-only ordinary users can read but cannot save, even with broad MCP scope.
 await db.query('RESET ROLE');await db.query('update unit_users set is_manager=false,is_editor=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
 await db.query('update occasion_users set is_manager=false,is_editor=false,is_editor_order=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await invoke('products.list')).ok,true);assert.equal((await invoke('products.save',edit)).error.code,'FORBIDDEN');
 await db.query('RESET ROLE');await db.query('update unit_users set is_manager=true,is_editor=true where unit=$1 and "user"=$2',[f.unit,f.actor]);await db.query('update occasion_users set is_manager=true,is_editor=true,is_editor_order=true where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 // Scope checks also cover known receipts after the occasion changes organizer.
 await db.query('RESET ROLE');await db.query('update occasions set unit=$2 where id=$1',[f.occasion,otherUnit]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await invoke('products.save',create)).error.code,'FORBIDDEN');
 await db.query('RESET ROLE');await db.query('update occasions set unit=$2 where id=$1',[f.occasion,f.unit]);await db.query('SET LOCAL ROLE authenticated');
 // Domain deletion guards still reject a product used by an order.
 await db.query('RESET ROLE');
 const form=Number((await db.query("insert into forms(occasion,title,link,key,data) values($1,'Product fixture',gen_random_uuid()::text,gen_random_uuid(),'{}') returning id",[f.occasion])).rows[0].id);
 const order=Number((await db.query("insert into eshop.orders(occasion,form,state,price,currency_code,order_sequence,order_symbol,data) values($1,$2,'ordered',120,'CZK',next_order_sequence($1),generate_order_symbol(),'{}') returning id",[f.occasion,form])).rows[0].id);
 const ticket=Number((await db.query("insert into eshop.tickets(occasion,state,ticket_symbol) values($1,'ordered',gen_random_uuid()::text) returning id",[f.occasion])).rows[0].id);
 await db.query('insert into eshop.order_product_ticket("order",product,ticket) values($1,$2,$3)',[order,productId,ticket]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await invoke('products.delete',{commandId:randomUUID(),productId,expectedVersion:product.aggregate_version})).ok,false);
 await db.query('RESET ROLE');await db.query('delete from eshop.order_product_ticket where "order"=$1',[order]);await db.query('SET LOCAL ROLE authenticated');
 const remove={commandId:randomUUID(),productId,expectedVersion:product.aggregate_version};
 assert.equal((await invoke('products.delete',{...remove,commandId:randomUUID(),expectedVersion:0})).error.code,'PRODUCT_CHANGED_RELOAD_REQUIRED');
 result=await invoke('products.delete',remove);assert.equal(result.ok,true,JSON.stringify(result));assert.deepEqual((await invoke('products.delete',remove)).data,result.data);assert.deepEqual((await invoke('products.list')).data.products,[]);
 await db.query('RESET ROLE');
 assert.deepEqual((await db.query("select has_function_privilege('authenticated','public.manage_product(bigint,bigint,bigint,text,jsonb,uuid)','EXECUTE') allowed,has_function_privilege('anon','public.manage_product(bigint,bigint,bigint,text,jsonb,uuid)','EXECUTE') anon,has_function_privilege('service_role','public.manage_product(bigint,bigint,bigint,text,jsonb,uuid)','EXECUTE') service")).rows[0],{allowed:true,anon:false,service:false});
 });


test('server keysets bound rows and metadata and preserve the complete editor projection',
 { skip: !process.env.FESTAPP_MCP_TEST_DATABASE_URL }, async t => {
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
 await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});
 await install(db);
 await db.query('RESET ROLE');const f=await fixture(db,2);
 const type=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,NULL,'entry') returning id",[f.occasion])).rows[0].id);
 await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Unrelated','entry')",[f.occasion]);
 const ids=(await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code,data) select $1,$2,'Product '||n,12.50,'CZK',NULL from generate_series(1,1000) n returning id",[f.occasion,type])).rows.map(r=>Number(r.id));
 const pool=Number((await db.query("insert into inventory_pools(occasion,title) values($1,'Stock') returning id",[f.occasion])).rows[0].id);
 const contexts=(await db.query("insert into inventory_contexts(inventory_pool,title) values($1,'Used A'),($1,'Used B'),($1,'Unrelated') returning id",[pool])).rows.map(r=>Number(r.id));
 await db.query('insert into eshop.product_inventory_contexts(product,inventory_context,quantity) values($1,$2,2),($1,$3,3)',[ids[0],contexts[0],contexts[1]]);
 const form=Number((await db.query("insert into forms(occasion,title,link,key,data) values($1,'Fixture',gen_random_uuid()::text,gen_random_uuid(),'{}') returning id",[f.occasion])).rows[0].id);
 await db.query("insert into form_fields(form,title,product_type,type) values($1,'One',$2,'product'),($1,'Two',$2,'product')",[form,type]);
 const order=Number((await db.query("insert into eshop.orders(occasion,form,state,price,currency_code,order_sequence,order_symbol,data) values($1,$2,'paid',25,'CZK',next_order_sequence($1),generate_order_symbol(),'{}') returning id",[f.occasion,form])).rows[0].id);
 const tickets=(await db.query("insert into eshop.tickets(occasion,state,ticket_symbol) select $1,'paid',gen_random_uuid()::text from generate_series(1,2) returning id",[f.occasion])).rows.map(r=>r.id);
 await db.query('insert into eshop.order_product_ticket("order",product,ticket) select $1,$2,unnest($3::bigint[])',[order,ids[0],tickets]);
 for(const state of ['sent','storno']) {
  const orderId=Number((await db.query("insert into eshop.orders(occasion,form,state,price,currency_code,order_sequence,order_symbol,data) values($1,$2,$3,12.50,'CZK',next_order_sequence($1),generate_order_symbol(),'{}') returning id",[f.occasion,form,state])).rows[0].id);
  const ticket=Number((await db.query("insert into eshop.tickets(occasion,state,ticket_symbol) values($1,$2,gen_random_uuid()::text) returning id",[f.occasion,state])).rows[0].id);
  await db.query('insert into eshop.order_product_ticket("order",product,ticket) values($1,$2,$3)',[orderId,ids[0],ticket]);
 }
 await db.query('SET LOCAL ROLE authenticated');
 const full=(await db.query('select get_product_catalog($1,$2,$3) value',[f.org,f.occasion,f.unit])).rows[0].value.catalog;
 const compat=(await db.query('select get_products_and_types_for_edit($1)::jsonb value',[f.link])).rows[0].value;
 assert.deepEqual(compat.products,full.products);
 let requests=0;
 const owner={root:'/tmp/festapp-product-semantics',profile:{organizationId:f.org,tenantId:'fixture',name:'fixture',backendOrigin:'http://127.0.0.1:61022'},allowedOperations:['products.list'],delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),
  authorized:action=>action({rpc:async(name,args)=>{
   assert.equal(name,'get_product_catalog_page');requests++;
   return {data:(await db.query('select get_product_catalog_page($1,$2,$3,$4,$5) value',[args.p_organization,args.p_occasion,args.p_unit,args.p_after,args.p_limit])).rows[0].value,error:null};
  }},{userId:f.actor})};
 const result=await new Operations(owner).invoke('products.list',{occasionId:f.occasion,limit:50});
 assert.equal(result.ok,true,JSON.stringify(result));assert.equal(requests,1);
 assert.equal(result.data.products[0].purchased_count,3);assert.equal(result.data.products[0].ordered_count,4);
 assert.deepEqual(result.data.products[0].form_ids,[form]);assert.deepEqual(result.data.forms,[{id:form,title:'Fixture'}]);
 assert.equal(result.data.inventoryContexts[0].poolTitle,'Stock');assert.equal(result.data.inventoryContexts[0].blockDate,null);
 assert.equal(JSON.stringify(result.data).includes('order_symbol'),false);
 let after=null;const seen=[];
 do {
  const result=(await db.query('select get_product_catalog_page($1,$2,$3,$4,50) value',[f.org,f.occasion,f.unit,after])).rows[0].value;
  assert(result.catalog.products.length<=50);assert.equal(result.catalog.product_types.length,1);assert.deepEqual(result.catalog.forms,[{id:form,title:'Fixture'}]);
  assert.equal(result.catalog.inventory_contexts.length,after===null?2:0);
  assert.equal(result.catalog.product_inventory_contexts.length,after===null?2:0);
  for(const product of result.catalog.products) {
   assert.deepEqual(product,full.products.find(p=>p.id===product.id));
   assert.equal(product.ordered_count,product.id===ids[0]?4:0);assert.equal(product.paid_count,product.id===ids[0]?2:0);assert.equal(product.sent_count,product.id===ids[0]?1:0);assert.equal(product.purchased_count,product.id===ids[0]?3:0);assert.deepEqual(product.form_ids,[form]);
   assert.equal(product.data,null);assert.equal(product.aggregate_version,0);
   seen.push(product.id);
  }
  after=result.nextCursor;
 } while(after);
 assert.deepEqual(seen,ids);
 assert.deepEqual((await db.query('select get_product_catalog_page($1,$2,$3,$4,50) value',[f.org,f.occasion,f.unit,ids.at(-1)])).rows[0].value.catalog.products,[]);
 for(const [limit,cursor] of [[0,null],[101,null],[null,null],[50,0]]) {
  await db.query('SAVEPOINT invalid');
  await assert.rejects(db.query('select get_product_catalog_page($1,$2,$3,$4,$5)',[f.org,f.occasion,f.unit,cursor,limit]),e=>e.code==='22023');
  await db.query('ROLLBACK TO SAVEPOINT invalid');await db.query('RELEASE SAVEPOINT invalid');
 }
 for(const args of [[f.org+1,f.occasion,f.unit],[f.org,f.occasion,f.unit+1]]) {
  await db.query('SAVEPOINT denied');
  await assert.rejects(db.query('select get_product_catalog_page($1,$2,$3)',args),e=>e.code==='42501');
  await db.query('ROLLBACK TO SAVEPOINT denied');await db.query('RELEASE SAVEPOINT denied');
 }
 await db.query('RESET ROLE');
 const grants=(await db.query("select rolname,has_function_privilege(rolname,'get_product_catalog_page(bigint,bigint,bigint,bigint,integer)','execute') allowed,has_function_privilege(rolname,'get_product_catalog_data_internal(bigint,bigint,integer)','execute') internal from pg_roles where rolname in ('authenticated','anon','service_role') order by rolname")).rows;
 assert.deepEqual(grants,[{rolname:'anon',allowed:false,internal:false},{rolname:'authenticated',allowed:true,internal:false},{rolname:'service_role',allowed:false,internal:false}]);
});

test('two connections: keysets see committed inserts/deletes and scope moves deny a waiting read',
 { skip: !process.env.FESTAPP_MCP_TEST_DATABASE_URL }, async t => {
 const admin=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
 const reader=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
 let f;
 t.after(async()=>{
  await admin.query('ROLLBACK');await reader.query('ROLLBACK');await reader.end();
  if(f) {
   await admin.query('BEGIN');
   for(const sql of ['delete from eshop.products where occasion=$1','delete from eshop.product_types where occasion=$1',
    'delete from places where occasion=$1','delete from occasion_users where occasion=$1','delete from occasion_link_reservations where occasion=$1','delete from occasions where id=$1']) await admin.query(sql,[f.occasion]);
   await admin.query("delete from abuse_policy_overrides where (target_kind='unit' and target_id=$1) or (target_kind='organization' and target_id=$2)",[f.unit,f.org]);
   await admin.query('delete from unit_users where unit=$1',[f.unit]);await admin.query('delete from units where organization=$1',[f.org]);
   await admin.query('delete from user_info where id=$1',[f.actor]);await admin.query('delete from auth.users where id=$1',[f.actor]);
   await admin.query('delete from organizations where id=$1',[f.org]);await admin.query('COMMIT');
  }
  await admin.end();
 });
 await admin.query('BEGIN');await install(admin);
 await admin.query('RESET ROLE');f=await fixture(admin,1);
 const type=Number((await admin.query("insert into eshop.product_types(occasion,title,type) values($1,'Concurrent','entry') returning id",[f.occasion])).rows[0].id);
 const ids=(await admin.query("insert into eshop.products(occasion,product_type,title,price,currency_code) select $1,$2,'Product '||n,10,'CZK' from generate_series(1,4) n returning id",[f.occasion,type])).rows.map(r=>Number(r.id));
 await admin.query('COMMIT');
 await reader.query('BEGIN');await reader.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await reader.query('SET LOCAL ROLE authenticated');
 const page=async(after=null)=>(await reader.query('select get_product_catalog_page($1,$2,$3,$4,2) value',[f.org,f.occasion,f.unit,after])).rows[0].value;
 assert.deepEqual((await page()).catalog.products.map(p=>p.id),ids.slice(0,2));
 await admin.query('BEGIN');await admin.query('delete from eshop.products where id=$1',[ids[2]]);
 const added=Number((await admin.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Later',10,'CZK') returning id",[f.occasion,type])).rows[0].id);
 assert.deepEqual((await page(ids[1])).catalog.products.map(p=>p.id),ids.slice(2),'uncommitted changes are invisible without blocking');
 await admin.query('COMMIT');
 const next=await page(ids[1]);assert.deepEqual(next.catalog.products.map(p=>p.id),[ids[3],added]);assert.equal(next.nextCursor,null);
 await reader.query('COMMIT');
 await admin.query('BEGIN');const otherUnit=Number((await admin.query("insert into units(title,organization) values('Outside consent',$1) returning id",[f.org])).rows[0].id);await admin.query('update occasions set unit=$2 where id=$1',[f.occasion,otherUnit]);
 await reader.query('BEGIN');await reader.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await reader.query('SET LOCAL ROLE authenticated');
 const denied=assert.rejects(page(),e=>e.code==='42501');
 let blocked=false;
 for(let n=0;n<50;n++) {
  if((await admin.query('select wait_event_type from pg_stat_activity where pid=$1',[reader.processID])).rows[0]?.wait_event_type==='Lock') {blocked=true;break;}
  await new Promise(r=>setTimeout(r,20));
 }
 assert(blocked,'read waits for concurrent scope change');await admin.query('COMMIT');await denied;
});
