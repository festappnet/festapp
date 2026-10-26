import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {connection,options,install,setup,executor,create,formPatch,save,denied} from './form-fixtures.mjs';
import {openDisposableDatabase} from './postgres.mjs';
test('forms executor creates a closed draft and returns only the administration snapshot and original versions',options,async t=>{
 const{db,f}=await setup(t);await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);const args={occasionId:f.occasion,title:'Atomic form',commandId:randomUUID()};const result=await ex.ops.invoke('forms.create',args);assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.authoring.form.is_open,false);assert(!Object.hasOwn(result.data.authoring.form,'link'));assert(!Object.hasOwn(result.data.authoring.form,'key'));
 assert.equal((await ex.ops.invoke('forms.create',args)).data.formId,result.data.formId);
 const id=result.data.formId;const actual=(await db.query('select link from forms where id=$1',[id])).rows[0];const ui=(await db.query('select get_form_for_edit($1) value',[actual.link])).rows[0].value;assert.equal(ui.data.form.aggregate_version,result.data.authoring.form.aggregate_version);assert.deepEqual(ui.data.form_fields,result.data.authoring.fields);assert(Object.hasOwn(ui.data.form,'key'));
 const inspection=await ex.ops.invoke('forms.inspect',{occasionId:f.occasion,formId:id});assert.equal(inspection.ok,true,JSON.stringify(inspection));assert.equal(inspection.data.authoring.form.id,id);
 t.diagnostic('form create/inspect JSON '+JSON.stringify(ex.calls));
});

test('bounded summaries share UI counts, tolerate malformed historical bindings and omit keys, links, data and unrelated products',options,async t=>{
 const{db,f}=await setup(t);const first=await create(db,f);await db.query('insert into forms(occasion,title) select $1,\'Form \x27||n from generate_series(1,104)n',[f.occasion]);
 const type=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Unrelated','food') returning id",[f.occasion])).rows[0].id);await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) select $1,$2,'Unrelated '||n,1,'CZK' from generate_series(1,125)n",[f.occasion,type]);
 await db.query("insert into eshop.orders(occasion,form,state,order_sequence,order_symbol,data) values($1,$2,'ordered',next_order_sequence($1),generate_order_symbol(),'{\"form\":\"not-a-uuid\"}')",[f.occasion,first.formId]);
 const key=(await db.query('select key from forms where id=$1',[first.formId])).rows[0].key;await db.query("insert into eshop.orders(occasion,form,state,order_sequence,order_symbol,data) values($1,$2,'ordered',next_order_sequence($1),generate_order_symbol(),jsonb_build_object('form',$3::text))",[f.occasion,first.formId,key]);
 const other=Number((await db.query('select id from forms where occasion=$1 and id<>$2 order by id limit 1',[f.occasion,first.formId])).rows[0].id);
 await db.query("insert into eshop.orders(occasion,form,state,order_sequence,order_symbol,data) values($1,null,'ordered',next_order_sequence($1),generate_order_symbol(),jsonb_build_object('form',$2::text)),($1,$3,'ordered',next_order_sequence($1),generate_order_symbol(),jsonb_build_object('form',$2::text))",[f.occasion,key,other]);
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);const seen=[];let after;do{const result=await ex.ops.invoke('forms.list',{occasionId:f.occasion,...(after?{after}:{})});assert.equal(result.ok,true,JSON.stringify(result));assert(result.data.forms.length<=50);for(const row of result.data.forms){assert(!Object.hasOwn(row,'key'));assert(!Object.hasOwn(row,'link'));assert(!Object.hasOwn(row,'data'));}seen.push(...result.data.forms);after=result.data.nextCursor;}while(after);assert.equal(seen.length,105);assert.equal(seen.find(r=>r.id===first.formId).response_count,3);
 assert.equal(seen.find(r=>r.id===other).response_count,1);
 const ui=(await db.query('select get_all_forms_with_fields($1) value',[f.link])).rows[0].value.data;assert.equal(ui.find(r=>r.id===first.formId).response_count,3);
 const actualLink=(await db.query('select link from forms where id=$1',[first.formId])).rows[0].link;
 assert.equal((await db.query('select get_form_for_edit($1) value',[actualLink])).rows[0].value.data.form.can_delete,false);
 const inspected=await ex.ops.invoke('forms.inspect',{occasionId:f.occasion,formId:first.formId});assert.equal(inspected.ok,true);assert(!inspected.data.authoring.productTypes.some(p=>p.id===type));assert(!JSON.stringify(inspected).includes('Unrelated'));
 t.diagnostic('bounded form list '+JSON.stringify(ex.calls));
});

test('one form save edits fields and settings atomically, preserves omitted metadata and replays its saved normalized result',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);const initial=made.authoring;const originalLink=(await db.query('select link from forms where id=$1',[made.formId])).rows[0].link;const field=initial.fields.find(x=>x.type==='email');await db.query("update form_fields set data='{\"legacy\":\"preserve\"}' where id=$1",[field.id]);await db.query('SET LOCAL ROLE authenticated');const payload=formPatch(initial,{title:'Changed',participant_capacity:10,show_remaining_capacity:false,form_fields:[{id:field.id,title:'Address',description:null,type:'email',is_required:true,is_hidden:false,is_ticket_field:false,order:0}]});const commandId=randomUUID();const saved=await save(db,f,payload,commandId);assert.equal(saved.code,200,JSON.stringify(saved));assert.equal((await db.query('select link from forms where id=$1',[made.formId])).rows[0].link,originalLink);const snapshot=saved.data.authoring;assert.equal(snapshot.form.title,'Changed');assert.equal(snapshot.form.participant_capacity,10);assert.equal(snapshot.form.show_remaining_capacity,false);assert.equal(snapshot.fields.find(x=>x.id===field.id).data.legacy,'preserve');assert(snapshot.form.aggregate_version>initial.form.aggregate_version);
 const replay=await save(db,f,payload,commandId);assert.deepEqual(replay.data,saved.data);
 const ex=executor(db,f);const stale=await ex.ops.invoke('forms.save',{occasionId:f.occasion,form:payload,commandId:randomUUID()});assert.equal(stale.error.code,'FORM_CHANGED_RELOAD_REQUIRED');
 await denied(db,"select manage_form($1,$2,$3,'save',$4,$5)",[f.occasion,f.org,f.unit,{id:made.formId,title:'No baseline'},randomUUID()],'22023');
});

test('foreign fields/types reject the entire save and current UI mutations share the same receipt owner',options,async t=>{
 const{db,f}=await setup(t);const own=await create(db,f);const foreignOc=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);const foreign=await create(db,{...f,occasion:foreignOc});const foreignField=foreign.authoring.fields[0].id;
 const foreignType=foreign.authoring.productTypes[0].id;await db.query('SET LOCAL ROLE authenticated');
 await denied(db,"select manage_form($1,$2,$3,'save',$4,$5)",[f.occasion,f.org,f.unit,formPatch(own.authoring,{title:'Must rollback',form_fields:[{id:foreignField,type:'email',title:'Foreign'}]}),randomUUID()],'22023');assert.equal((await db.query('select title from forms where id=$1',[own.formId])).rows[0].title,'Synthetic form');
 await denied(db,"select manage_form($1,$2,$3,'save',$4,$5)",[f.occasion,f.org,f.unit,formPatch(own.authoring,{form_fields:[{type:'product_type',product_type_id:foreignType}]}),randomUUID()],'22023');
 const ui=(await db.query('select update_form_client_sync_v1($1,$2) value',[{...formPatch(own.authoring,{title:'UI save'}),occasion:f.occasion},randomUUID()])).rows[0].value;assert.equal(ui.code,200);assert.equal(ui.data.authoring.form.title,'UI save');
 assert.equal((await save(db,f,formPatch(own.authoring,{title:'Stale MCP'}))).code,409);
});

test('copy retries keep one form and recheck source permissions; deletion retains the slug tombstone and replay',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);const target=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);await db.query('SET LOCAL ROLE authenticated');const args=[target,f.org,f.unit,'duplicate',{source_form_id:made.formId,source_occasion_id:f.occasion,source_unit_id:f.unit,locale:'cs'},randomUUID()];const sql='select manage_form($1,$2,$3,$4,$5,$6) value';const copied=(await db.query(sql,args)).rows[0].value;assert.equal(copied.code,200,JSON.stringify(copied));assert.equal((await db.query(sql,args)).rows[0].value.data.formId,copied.data.formId);
 await db.query('RESET ROLE');await db.query('update occasion_users set is_editor_view=false where occasion=$1',[f.occasion]);await db.query('update unit_users set is_editor_view=false where unit=$1',[f.unit]);await db.query('SET LOCAL ROLE authenticated');await denied(db,sql,args);
 const id=copied.data.formId;const slug=(await db.query('select link from forms where id=$1',[id])).rows[0].link;const delArgs=[target,f.org,f.unit,'delete',{id,expected_aggregate_version:copied.data.authoring.form.aggregate_version},randomUUID()];assert.equal((await db.query(sql,delArgs)).rows[0].value.code,200);assert.equal((await db.query(sql,delArgs)).rows[0].value.code,200);
 await db.query('RESET ROLE');assert.equal((await db.query('select count(*) n from forms where id=$1',[id])).rows[0].n,'0');assert.equal((await db.query('select count(*) n from form_link_reservations where slug=$1',[slug])).rows[0].n,'1');
});

test('all changed SQL owners match the forward contract; scope, private grants and unknown inputs fail closed',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);await db.query('SET LOCAL ROLE authenticated');await denied(db,'select get_form_for_authoring($1,$2,$3,$4)',[f.occasion,f.org+999,f.unit,made.formId]);await denied(db,'select get_form_catalog_page($1,$2,$3,$4,$5)',[f.occasion,f.org,f.unit,null,101],'22023');
 await denied(db,"select manage_form($1,$2,$3,'save',$4,$5)",[f.occasion,f.org,f.unit,formPatch(made.authoring,{key:randomUUID()}),randomUUID()],'22023');
 await db.query('RESET ROLE');await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));const source=await readFile(new URL('../../../supabase/migrations/20261026190000_form_authoring.sql',import.meta.url),'utf8');const names=new Set([...source.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)/gi)].map(m=>m[1]));const contract=await readFile(new URL('../../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url),'utf8');const checks=contract.split('\n').filter(l=>[...names].some(n=>l.includes("to_regprocedure('public."+n+'(')));assert.equal(checks.length,[...source.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)/gi)].length);await db.query('DO $$ BEGIN\n'+checks.join('\n')+'\nEND $$;');
 for(const role of ['anon','service_role'])assert.equal((await db.query("select has_function_privilege($1,'manage_form(bigint,bigint,bigint,text,jsonb,uuid)','execute') allowed",[role])).rows[0].allowed,false);
 assert.equal((await db.query("select has_function_privilege('authenticated','get_form_authoring_snapshot_internal(bigint)','execute') allowed")).rows[0].allowed,false);assert.equal((await db.query("select to_regprocedure('public.form_catalog_read_rule(boolean,boolean)') old")).rows[0].old,null);
});

test('a saved receipt stays frozen after another save; catalog-type references never rewrite products',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);await db.query('SET LOCAL ROLE authenticated');const id=randomUUID();const payload=formPatch(made.authoring,{title:'First',form_fields:[{type:'product_type',title:'Another choice',description:null,is_required:false,is_hidden:false,is_ticket_field:true,order:9,product_type_id:made.authoring.productTypes[0].id}]});
 const first=await save(db,f,payload,id);assert.equal(first.code,200);assert.deepEqual(first.data.authoring.productVersions,made.authoring.productVersions);assert(first.data.authoring.fields.some(x=>x.title==='Another choice'&&x.id>0));
 assert.equal((await save(db,f,formPatch(first.data.authoring,{title:'Later'}))).code,200);
 assert.deepEqual((await save(db,f,payload,id)).data,first.data);
});

test('capacity reduction below committed tickets rejects the full aggregate without changing existing orders',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);const product=made.authoring.products[0].id;
 await db.query('update forms set participant_capacity=2 where id=$1',[made.formId]);const order=Number((await db.query("insert into eshop.orders(occasion,form,state,price,currency_code,order_sequence,order_symbol,data) values($1,$2,'paid',0,'CZK',next_order_sequence($1),generate_order_symbol(),'{}') returning id",[f.occasion,made.formId])).rows[0].id);
 for(let i=0;i<2;i++){const ticket=Number((await db.query("insert into eshop.tickets(occasion,state) values($1,'paid') returning id",[f.occasion])).rows[0].id);await db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3)',[order,ticket,product]);}
 await db.query('SET LOCAL ROLE authenticated');const result=await save(db,f,formPatch(made.authoring,{title:'Rejected title',participant_capacity:1}));assert.notEqual(result.code,200,JSON.stringify(result));
 assert.equal((await db.query('select participant_capacity from forms where id=$1',[made.formId])).rows[0].participant_capacity,2);assert.equal((await db.query('select title from forms where id=$1',[made.formId])).rows[0].title,'Synthetic form');
 await db.query('RESET ROLE');assert.equal((await db.query('select count(*) n from eshop.order_product_ticket where "order"=$1',[order])).rows[0].n,'2');
});

test('two connections serialize capacity save with the real checkout owner; checkout cannot use the old limit',options,async t=>{
 const admin=await openDisposableDatabase(connection),checkout=await openDisposableDatabase(connection);let f,formId;
 t.after(async()=>{try{
  await checkout.query('ROLLBACK');await admin.query('ROLLBACK');await admin.query('RESET ROLE');
  if(f){await admin.query('BEGIN');await admin.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);
   assert.equal((await admin.query('select count(*) n from eshop.orders where occasion=$1',[f.occasion])).rows[0].n,'0');
   await admin.query('delete from client_mutation_receipts where occasion=$1',[f.occasion]);
   for(const table of ['client_commit_items','client_commit_components'])await admin.query(`delete from ${table} where commit_id in(select commit_id from client_commits where occasion=$1)`,[f.occasion]);
   await admin.query('delete from client_commits where occasion=$1',[f.occasion]);await admin.query("delete from client_aggregate_versions where scope_type='occasion' and scope_id=$1",[f.occasion]);
   await admin.query('delete from form_link_reservations where form=$1',[formId]);await admin.query('delete from occasion_link_reservations where occasion=$1',[f.occasion]);
   await admin.query('select delete_occasion_internal_v1($1)',[f.occasion]);
   await admin.query("delete from abuse_policy_overrides where (target_kind='unit' and target_id=$1) or (target_kind='organization' and target_id=$2)",[f.unit,f.org]);await admin.query('delete from unit_users where unit=$1',[f.unit]);await admin.query('delete from units where id=$1',[f.unit]);await admin.query('delete from user_info where id=$1',[f.actor]);await admin.query('delete from auth.users where id=$1',[f.actor]);await admin.query('delete from organizations where id=$1',[f.org]);await admin.query('COMMIT');
  }
 }finally{await checkout.end();await admin.end();}});
 await admin.query('BEGIN');await install(admin);const {fixture}=await import('../../../automation/authorization/benchmark.mjs');f=await fixture(admin,1);
 await admin.query(`update occasions set features='[{"code":"ticket","is_enabled":true},{"code":"form","is_enabled":true}]' where id=$1`,[f.occasion]);
 const made=await create(admin,f);formId=made.formId;await admin.query('update forms set is_open=true,participant_capacity=2 where id=$1',[formId]);const key=(await admin.query('select key from forms where id=$1',[formId])).rows[0].key;await admin.query('COMMIT');
 await admin.query('BEGIN');await admin.query("set local statement_timeout='5s'");await admin.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);await admin.query('SET LOCAL ROLE authenticated');
 const changed=await save(admin,f,formPatch(made.authoring,{participant_capacity:1}));assert.equal(changed.code,200,JSON.stringify(changed));
 await checkout.query('BEGIN');await checkout.query("set local statement_timeout='5s'");await checkout.query("select set_config('request.jwt.claim.role','service_role',true),set_config('festapp.email_wake','scheduled',true)");
 const pid=Number((await checkout.query('select pg_backend_pid() pid')).rows[0].pid),writer=Number((await admin.query('select pg_backend_pid() pid')).rows[0].pid);
 const product=made.authoring.products[0].id;let completed=false;
 const running=checkout.query('select create_ticket_order_internal_v1($1) value',[{form:key,email:'synthetic@example.invalid',ticket:Array.from({length:2},()=>({fields:[{product_type:product}]}))}]).finally(()=>{completed=true;});
 let blocked=false;for(let attempt=0;attempt<40&&!completed;attempt++){blocked=(await admin.query('select $1::int=any(pg_blocking_pids($2::int)) blocked',[writer,pid])).rows[0].blocked;if(blocked)break;await new Promise(resolve=>setTimeout(resolve,25));}
 assert.equal(blocked,true,'checkout must wait on the canonical form lock');await admin.query('COMMIT');const result=(await running).rows[0].value;await checkout.query('ROLLBACK');
 assert.notEqual(result.code,200,JSON.stringify(result));assert.match(JSON.stringify(result),/CAPACITY/i);
 assert.equal((await admin.query('select participant_capacity from forms where id=$1',[formId])).rows[0].participant_capacity,1);
});

for(const file of ['forms/create_form_test.sql','forms/delete_form_test.sql','eshop_forms/get_form_for_edit_short_title_test.sql','eshop_forms/form_editor_deletion_test.sql','eshop_forms/form_capacity_test.sql','eshop_forms/choice_validation_copy_locale_test.sql']){
 test('existing form regression: '+file,options,async t=>{const{db}=await setup(t);await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));await db.query(await readFile(new URL('../../../database/tests/'+file,import.meta.url),'utf8'));});
}

test('form save uses the same typed author permission as create and the domain owner, and revocation denies replay',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);
 await db.query('update occasion_users set is_editor=false,is_editor_view=false,is_editor_order=false,is_editor_order_view=false,is_manager=false where occasion=$1',[f.occasion]);await db.query('update unit_users set is_editor=true,is_manager=false,is_editor_view=false where unit=$1',[f.unit]);
 await db.query('SET LOCAL ROLE authenticated');const config=(await db.query('select get_app_config_v218($1) value',[{organization:f.org,link:f.link,platform:{platform:'web'}}])).rows[0].value;assert.equal(config.capabilities['forms.write'],true);assert.equal(config.capabilities['forms.catalog.read'],true);assert.equal(config.capabilities['orders.write'],false);assert.equal((await db.query('select can_author_forms($1) allowed',[f.occasion])).rows[0].allowed,true);
 const payload=formPatch(made.authoring,{title:'Unit editor'}),commandId=randomUUID();const saved=await save(db,f,payload,commandId);assert.equal(saved.code,200,JSON.stringify(saved));assert.equal((await db.query('select get_form_for_authoring($1,$2,$3,$4) value',[f.occasion,f.org,f.unit,made.formId])).rows[0].value.authoring.form.id,made.formId);
 await db.query('RESET ROLE');await db.query('update unit_users set is_editor=false where unit=$1',[f.unit]);await db.query('SET LOCAL ROLE authenticated');
 await denied(db,"select manage_form($1,$2,$3,'save',$4,$5)",[f.occasion,f.org,f.unit,payload,commandId]);
});
