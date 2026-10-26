import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {options,setup,executor,create,formPatch,save,denied} from './form-fixtures.mjs';
const stored=async(db,id)=>(await db.query('select data from forms where id=$1',[id])).rows[0].data;

test('settings executor preserves unrelated metadata and shares UI snapshots, original versions and frozen retries',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);const formId=made.formId;
 await db.query(`update forms set data='{"private_owner":{"keep":true},"schedule":{"sale_preparation":true,"private_flag":7},"design":{"background_mode":"pattern"}}' where id=$1`,[formId]);
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);const settings={is_reminder_enabled:true,reminder_interval_seconds:0,communication_tone:'informal',variable_symbol:{type:'sequence',starting_number:12345},payment_message:{type:'occasion_title'},payments:{bankEnabled:true},design:{is_card_design:true,primary_color:'#1255AA',secondary_color:'#FFAABBCC',font_family:'Noto Sans',countdown_style:'normal'},schedule:{start_time:'2030-10-27T01:30:00+02:00',end_time:'2030-10-27T01:30:00+01:00',enable_countdown:true,show_before_start_message:true,before_start_message:'<p>Later</p>',countdown_title:'Soon'}};
 const args={occasionId:f.occasion,form:formPatch(made.authoring,{settings}),commandId:randomUUID()};
 const result=await ex.ops.invoke('forms.save',args);assert.equal(result.ok,true,JSON.stringify(result));const data=result.data.authoring.form.data;
 for(const [k,v] of Object.entries(settings))assert.deepEqual(typeof v==='object'?Object.fromEntries(Object.keys(v).map(key=>[key,data[k][key]])):data[k],v);
 assert.deepEqual(data.private_owner,{keep:true});assert.equal(data.schedule.sale_preparation,true);assert.equal(data.design.background_mode,'pattern');
 assert.deepEqual((await ex.ops.invoke('forms.save',args)).data.authoring,result.data.authoring);
 const link=(await db.query('select link from forms where id=$1',[formId])).rows[0].link;const ui=(await db.query('select get_form_for_edit($1) value',[link])).rows[0].value;
 assert.deepEqual(ui.data.form.data,data);
 const later=await ex.ops.invoke('forms.save',{...args,commandId:randomUUID(),form:formPatch(result.data.authoring,{settings:{communication_tone:'formal'}})});assert.equal(later.ok,true,JSON.stringify(later));
 assert.deepEqual((await ex.ops.invoke('forms.save',args)).data.authoring,result.data.authoring);
 assert.equal((await ex.ops.invoke('forms.save',{...args,commandId:randomUUID()})).error.code,'FORM_CHANGED_RELOAD_REQUIRED');
});

test('null resets known overrides to inheritance without deleting lifecycle or other-owner settings',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);await db.query(`update units set data='{"communication_tone":"informal"}' where id=$1`,[f.unit]);
 await db.query(`update forms set data='{"communication_tone":"formal","is_reminder_enabled":false,"reminder_interval_seconds":0,"private_owner":7,"schedule":{"sale_preparation":true,"start_time":"2030-01-01T00:00:00Z","end_time":"2031-01-01T00:00:00Z"},"design":{"primary_color":"#123456","background_mode":"pattern"},"variable_symbol":{"type":"sequence","starting_number":1,"preferred_digits":5}}' where id=$1`,[made.formId]);
 await db.query('SET LOCAL ROLE authenticated');const result=await save(db,f,formPatch(made.authoring,{settings:{communication_tone:null,is_reminder_enabled:null,reminder_interval_seconds:null,schedule:null,design:{primary_color:null},variable_symbol:{type:'random',starting_number:null}}}));assert.equal(result.code,200,JSON.stringify(result));
 assert.deepEqual(result.data.authoring.form.data,{private_owner:7,schedule:{sale_preparation:true},design:{background_mode:'pattern'},variable_symbol:{type:'random',preferred_digits:5}});
 await db.query('RESET ROLE');assert.equal((await db.query('select get_effective_form_data($1) value',[made.formId])).rows[0].value.communication_tone,'informal');
 // Opening still belongs to the lifecycle owner; a settings reset cannot restore preparation.
 const opened=await save(db,f,formPatch(result.data.authoring,{is_open:true,settings:{schedule:null}}));assert.equal(opened.code,200,JSON.stringify(opened));assert.equal(opened.data.authoring.form.data.schedule.sale_preparation,false);
});

test('invalid SQL settings reject atomically before title/field mutation and cannot patch private lifecycle metadata',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);const before=await stored(db,made.formId);
 const invalid=[{unknown:true},{schedule:{sale_preparation:false}},{design:{background_mode:'injected'}},{payments:{account_id:'acct_injected'}},{is_reminder_enabled:'true'},{reminder_interval_seconds:-1},{reminder_interval_seconds:1.5},{communication_tone:'casual'},{variable_symbol:{type:'sequence'}},{variable_symbol:{starting_number:10000000000}},{variable_symbol:{type:'sequence',starting_number:'123'}},{payment_message:{type:'custom'}},{design:{primary_color:'red'}},{payments:{stripeConnectionId:'wrong'}},{schedule:{start_time:'2030-01-01T00:00:00'}},{schedule:{start_time:'2031-01-01T00:00:00Z',end_time:'2030-01-01T00:00:00Z'}}];
 await db.query('SET LOCAL ROLE authenticated');
 for(const settings of invalid){await db.query('SAVEPOINT invalid_settings');await assert.rejects(save(db,f,formPatch(made.authoring,{title:'Must rollback',settings})),error=>error.code?.startsWith('22'));await db.query('ROLLBACK TO SAVEPOINT invalid_settings');await db.query('RELEASE SAVEPOINT invalid_settings');assert.deepEqual(await stored(db,made.formId),before);assert.equal((await db.query('select title from forms where id=$1',[made.formId])).rows[0].title,'Synthetic form');}
 const inspected=(await executor(db,f).ops.invoke('forms.inspect',{occasionId:f.occasion,formId:made.formId})).data.authoring;assert.equal(inspected.form.aggregate_version,made.authoring.form.aggregate_version);
});

test('released metadata boundary normalizes historical data and uses the same settings validation as the new patch',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);const metadata={private_owner:9,is_reminder_enabled:false,communication_tone:'informal',design:{primary_color:'#112233',background_mode:'pattern'}};
 await db.query('SET LOCAL ROLE authenticated');const legacy=async p=>(await db.query('select update_form_client_sync_v1($1,$2) value',[{occasion:f.occasion,...p},randomUUID()])).rows[0].value;
 const result=await legacy(formPatch(made.authoring,{data:[null,metadata]}));assert.equal(result.code,200,JSON.stringify(result));assert.deepEqual(result.data.authoring.form.data,metadata);
 await denied(db,'select update_form_client_sync_v1($1,$2)',[{occasion:f.occasion,...formPatch(result.data.authoring,{data:{...metadata,reminder_interval_seconds:-1},title:'Must rollback'})},randomUUID()],'22023');assert.deepEqual(await stored(db,made.formId),metadata);
 await denied(db,'select update_form_client_sync_v1($1,$2)',[{occasion:f.occasion,...formPatch(result.data.authoring,{data:metadata,settings:{communication_tone:'formal'}})},randomUUID()],'22023');
 const saved=await save(db,f,formPatch(result.data.authoring,{settings:{communication_tone:'formal'}}));assert.equal(saved.code,200);assert.equal(saved.data.authoring.form.data.private_owner,9);
});

test('payment options use the UI bank projection and form-author predicate; foreign form/unit and revoked readers fail closed',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);const formLink=(await db.query('select link from forms where id=$1',[made.formId])).rows[0].link;const bank=(await db.query("insert into eshop.bank_accounts(title,type,account_number) values('Linked form bank','FIO','123456/0800') returning id")).rows[0].id;await db.query('insert into eshop.unit_bank_accounts(unit,bank_account,priority) values($1,$2,0)',[f.unit,bank]);await db.query('update occasion_users set is_editor=false,is_editor_view=false,is_editor_order=false,is_editor_order_view=false,is_manager=false where occasion=$1',[f.occasion]);await db.query('update unit_users set is_editor=true,is_manager=false,is_editor_view=false where unit=$1',[f.unit]);
 await db.query('SET LOCAL ROLE authenticated');assert.equal((await db.query('select can_write_orders($1) value',[f.occasion])).rows[0].value,false);
 const result=await executor(db,f).ops.invoke('forms.paymentOptions',{occasionId:f.occasion,formId:made.formId,livemode:true});assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.livemode,true);assert.deepEqual(result.data.bankAccounts.map(b=>b.id),[Number(bank)]);
 const ui=(await db.query('select get_form_for_edit($1) value',[formLink])).rows[0].value;assert.deepEqual(result.data.bankAccounts,ui.data.available_bank_accounts);
 await denied(db,'select get_form_payment_options($1,$2,$3,$4,true)',[f.occasion,f.org,f.unit,made.formId+999999]);await denied(db,'select get_form_payment_options($1,$2,$3,$4,true)',[f.occasion,f.org,f.unit+999999,made.formId]);
 await db.query('RESET ROLE');await db.query('update unit_users set is_editor=false,is_editor_view=true where unit=$1',[f.unit]);await db.query('SET LOCAL ROLE authenticated');await denied(db,'select get_form_payment_options($1,$2,$3,$4,true)',[f.occasion,f.org,f.unit,made.formId]);
});

test('existing Stripe selection validates actual recipient scope and compatibility, preserves runtime restrictions and never allocates a payment',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);const conn=randomUUID();await db.query(`update organizations set data=coalesce(data,'{}')||'{"DEFAULT_URL":"https://forms.example.invalid"}' where id=$1`,[f.org]);
 await db.query("insert into eshop.stripe_connections(id,organization_id,unit_id,account_id,livemode,state,model_verified,paused,charges_enabled,card_payments_active,business_name) values($1,$2,$3,$4,true,'connected',true,false,true,true,'Synthetic recipient')",[conn,f.org,f.unit,'acct_'+conn.replaceAll('-','')]);
 const otherUnit=(await db.query("insert into units(title,organization) values('Other recipient unit',$1) returning id",[f.org])).rows[0].id;const other=randomUUID();await db.query("insert into eshop.stripe_connections(id,organization_id,unit_id,account_id,livemode,state,model_verified) values($1,$2,$3,$4,true,'connected',true)",[other,f.org,otherUnit,'acct_'+other.replaceAll('-','')]);
 const counts=async()=> (await db.query('select (select count(*) from eshop.payment_info) payments,(select count(*) from eshop.payment_reference_reservations) refs')).rows[0];const before=await counts();
 await db.query('SET LOCAL ROLE authenticated');let result=await save(db,f,formPatch(made.authoring,{settings:{payments:{bankEnabled:false,stripeConnectionId:conn}}}));assert.equal(result.code,200,JSON.stringify(result));
 const options=await executor(db,f).ops.invoke('forms.paymentOptions',{occasionId:f.occasion,formId:made.formId,livemode:true});assert.equal(options.ok,true,JSON.stringify(options));assert.equal(options.data.stripeRecipient.connectionId,conn);assert(!JSON.stringify(options).includes('acct_'));
 assert.equal(options.data.availability.configured.stripe,true);assert.notEqual(options.data.availability.stripeUnavailableReason,null); // no live activation in fixture
 const foreign=await save(db,f,formPatch(result.data.authoring,{settings:{payments:{stripeConnectionId:other}},title:'Must rollback'}));assert.equal(foreign.status,'rejected',JSON.stringify(foreign));assert.equal((await stored(db,made.formId)).payments.stripeConnectionId,conn);
 await db.query('RESET ROLE');await db.query('update eshop.stripe_connections set paused=true where id=$1',[conn]);await db.query('SET LOCAL ROLE authenticated');result=await save(db,f,formPatch(result.data.authoring,{settings:{payment_message:{type:'none'}}}));assert.equal(result.code,200,JSON.stringify(result));
 const paused=await executor(db,f).ops.invoke('forms.paymentOptions',{occasionId:f.occasion,formId:made.formId,livemode:true});assert.equal(paused.data.availability.stripeUnavailableReason,'paused');assert.equal(result.data.authoring.form.data.payments.stripeConnectionId,conn);
 await db.query('RESET ROLE');assert.deepEqual(await counts(),before);
});

test('incomplete payment methods and foreign bank selection roll back settings and other aggregate writes together',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);await db.query('update eshop.products set price=100 where id=$1',[made.authoring.products[0].id]);await db.query('SET LOCAL ROLE authenticated');
 const result=await save(db,f,formPatch(made.authoring,{is_open:true,title:'Must rollback',settings:{payments:{bankEnabled:false,stripeConnectionId:null}}}));assert.equal(result.status,'rejected',JSON.stringify(result));assert.equal((await db.query('select is_open from forms where id=$1',[made.formId])).rows[0].is_open,false);
 const foreign=await save(db,f,formPatch(made.authoring,{bank_account:999999999,title:'Must rollback',settings:{communication_tone:'informal'}}));assert.equal(foreign.status,'rejected');assert.equal((await stored(db,made.formId))?.communication_tone,undefined);
});

for(const file of ['eshop/reminders/form_reminder_inheritance_test.sql','eshop/stripe/connections_test.sql']){
 test('existing settings consumer: '+file,options,async t=>{const{db}=await setup(t);await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));if(file.includes('reminder')){await db.query("select set_config('request.jwt.claim.role','service_role',true)");await db.query(await readFile(new URL('../../../database/tests/blueprint/fixtures.sql',import.meta.url),'utf8'));await db.query(await readFile(new URL('../../../database/tests/helpers/canonical_blueprint_order_fixture.sql',import.meta.url),'utf8'));}await db.query(await readFile(new URL('../../../database/tests/'+file,import.meta.url),'utf8'));});
}

test('MCP schemas and the private SQL settings owner expose the same supported key contract, including nested resets',options,async t=>{
 const {db}=await setup(t);const{z}=await import('zod');const{formDescriptors}=await import('../src/operations/forms.mjs');
 const spec=(await db.query('select form_settings_keys_internal() value')).rows[0].value;
 for(const signature of ['form_settings_keys_internal()','normalize_form_metadata_internal(jsonb)','form_settings_from_metadata_internal(jsonb)','apply_form_settings_internal(jsonb,jsonb)','get_form_bank_accounts_internal(bigint)']){
  for(const role of ['anon','authenticated','service_role'])assert.equal((await db.query("select has_function_privilege($1,$2,'EXECUTE') allowed",[role,'public.'+signature])).rows[0].allowed,false,role+' '+signature);
 }
 for(const signature of ['get_form_payment_options(bigint,bigint,bigint,bigint,boolean)','get_form_stripe_recipient(bigint,bigint,boolean)']){
  assert.equal((await db.query("select has_function_privilege('authenticated',$1,'EXECUTE') allowed",['public.'+signature])).rows[0].allowed,true);
  for(const role of ['anon','service_role'])assert.equal((await db.query("select has_function_privilege($1,$2,'EXECUTE') allowed",[role,'public.'+signature])).rows[0].allowed,false);
 }

 const schema=z.toJSONSchema(formDescriptors.find(d=>d.id==='forms.save').input).properties.form.properties.settings;
 assert.equal(schema.additionalProperties,false);assert.deepEqual(Object.keys(schema.properties).sort(),Object.keys(spec).sort());
 for(const [section,keys] of Object.entries(spec))if(keys){const object=schema.properties[section].anyOf.find(s=>s.type==='object');assert.equal(object.additionalProperties,false);assert.deepEqual(Object.keys(object.properties).sort(),keys.toSorted());}
});

test('legacy sale dates normalize once in admin reads and saves; reset cannot resurrect a root alias in the actual runtime gate',options,async t=>{
 const{db,f}=await setup(t);await db.query(await readFile(new URL('../../../database/functions/eshop_forms/form_availability.sql',import.meta.url),'utf8'));const made=await create(db,f);
 const legacy={start_time:'2030-01-01 00:00:00+00',end_time:'2031-01-01T00:00:00Z',private_owner:7,schedule:{sale_preparation:true,end_time:null}};
 await db.query('update forms set data=$1 where id=$2',[legacy,made.formId]);const link=(await db.query('select link from forms where id=$1',[made.formId])).rows[0].link;
 const before=(await db.query("select get_form_availability_snapshot_internal($1,'2029-01-01T00:00:00Z') value",[made.formId])).rows[0].value;
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);const read=await ex.ops.invoke('forms.inspect',{occasionId:f.occasion,formId:made.formId});assert.equal(read.ok,true,JSON.stringify(read));const data=read.data.authoring.form.data;
 assert(!Object.hasOwn(data,'start_time'));assert(!Object.hasOwn(data,'end_time'));assert.equal(Date.parse(data.schedule.start_time),Date.parse(before.startAt));assert.equal(Date.parse(data.schedule.end_time),Date.parse(before.endAt));
 const ui=(await db.query('select get_form_for_edit($1) value',[link])).rows[0].value;assert.deepEqual(ui.data.form.data,data);
 const reset=await ex.ops.invoke('forms.save',{occasionId:f.occasion,commandId:randomUUID(),form:formPatch(read.data.authoring,{settings:{schedule:null}})});assert.equal(reset.ok,true,JSON.stringify(reset));
 await db.query('RESET ROLE');const persisted=await stored(db,made.formId);assert.deepEqual(persisted,{private_owner:7,schedule:{sale_preparation:true}});
 const after=(await db.query("select get_form_availability_snapshot_internal($1,'2029-01-01T00:00:00Z') value",[made.formId])).rows[0].value;assert.equal(after.startAt,null);assert.equal(after.endAt,null);
 // The bounded released-input adapter also retires aliases on its next save.
 const saved=(await db.query('select update_form_client_sync_v1($1,$2) value',[{occasion:f.occasion,...formPatch(reset.data.authoring,{data:legacy})},randomUUID()])).rows[0].value;assert.equal(saved.code,200,JSON.stringify(saved));const canonical=await stored(db,made.formId);assert(!Object.hasOwn(canonical,'start_time'));assert(!Object.hasOwn(canonical,'end_time'));assert(canonical.schedule.start_time.includes('T'));
});
