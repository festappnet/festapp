import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {options,setup,executor,create,formPatch,save,denied} from './form-fixtures.mjs';
const defaultPayments={bankEnabled:false,cashEnabled:false,cashInstructions:'',providerConnections:{}};
const stored=async(db,id)=>(await db.query('select data from forms where id=$1',[id])).rows[0].data;

test('settings executor preserves unrelated metadata and shares UI snapshots, original versions and frozen retries',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);const formId=made.formId;
 await db.query(`update forms set data='{"private_owner":{"keep":true},"schedule":{"sale_preparation":true,"private_flag":7},"design":{"paper_texture":"pattern","presale_header":"event_and_date"}}' where id=$1`,[formId]);
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);const settings={is_reminder_enabled:true,reminder_interval_seconds:0,communication_tone:'informal',sale_opening_notifications:{enabled:false,collection_paused:false},variable_symbol:{type:'sequence',starting_number:12345},payment_message:{type:'occasion_title'},payments:{bankEnabled:true},design:{embed_inherit_style:false,presale_header:'event_and_date',theme_mode:'dark',is_card_design:true,primary_color:'#1255AA',secondary_color:'#FFAABBCC',font_family:'Noto Sans',countdown_style:'normal'},schedule:{start_time:'2030-10-27T01:30:00+02:00',end_time:'2030-10-27T01:30:00+01:00',enable_countdown:true,countdown_title:'Soon'}};
 const args={occasionId:f.occasion,form:formPatch(made.authoring,{settings}),commandId:randomUUID()};
 const result=await ex.ops.invoke('forms.save',args);assert.equal(result.ok,true,JSON.stringify(result));const data=result.data.authoring.form.data;
 for(const [k,v] of Object.entries(settings))assert.deepEqual(typeof v==='object'?Object.fromEntries(Object.keys(v).map(key=>[key,data[k][key]])):data[k],v);
 assert.deepEqual(data.private_owner,{keep:true});assert.equal(data.schedule.sale_preparation,true);assert.equal(data.design.paper_texture,'pattern');
 assert.deepEqual((await ex.ops.invoke('forms.save',args)).data.authoring,result.data.authoring);
 const link=(await db.query('select link from forms where id=$1',[formId])).rows[0].link;const ui=(await db.query('select get_form_for_edit($1) value',[link])).rows[0].value;
 assert.deepEqual(ui.data.form.data,data);
 const later=await ex.ops.invoke('forms.save',{...args,commandId:randomUUID(),form:formPatch(result.data.authoring,{settings:{communication_tone:'formal'}})});assert.equal(later.ok,true,JSON.stringify(later));
 assert.deepEqual((await ex.ops.invoke('forms.save',args)).data.authoring,result.data.authoring);
 assert.equal((await ex.ops.invoke('forms.save',{...args,commandId:randomUUID()})).error.code,'FORM_CHANGED_RELOAD_REQUIRED');
});

test('null resets known overrides to inheritance without deleting lifecycle or other-owner settings',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);await db.query(`update units set data='{"communication_tone":"informal"}' where id=$1`,[f.unit]);
 await db.query(`update forms set data='{"communication_tone":"formal","is_reminder_enabled":false,"reminder_interval_seconds":0,"private_owner":7,"schedule":{"sale_preparation":true,"start_time":"2030-01-01T00:00:00Z","end_time":"2031-01-01T00:00:00Z"},"design":{"primary_color":"#123456","paper_texture":"pattern"},"variable_symbol":{"type":"sequence","starting_number":1,"preferred_digits":5}}' where id=$1`,[made.formId]);
 await db.query('SET LOCAL ROLE authenticated');const result=await save(db,f,formPatch(made.authoring,{settings:{communication_tone:null,is_reminder_enabled:null,reminder_interval_seconds:null,schedule:null,design:{primary_color:null},variable_symbol:{type:'random',starting_number:null}}}));assert.equal(result.code,200,JSON.stringify(result));
 assert.deepEqual(result.data.authoring.form.data,{private_owner:7,schedule:{sale_preparation:true},design:{paper_texture:'pattern'},variable_symbol:{type:'random',preferred_digits:5},payments:defaultPayments});
 await db.query('RESET ROLE');assert.equal((await db.query('select get_effective_form_data($1) value',[made.formId])).rows[0].value.communication_tone,'informal');
 // Opening still belongs to the lifecycle owner; a settings reset cannot restore preparation.
 const opened=await save(db,f,formPatch(result.data.authoring,{is_open:true,payment_selection_intent:'replace',settings:{schedule:null,payment_deadline:{mode:'none'},payments:{bankEnabled:false,cashEnabled:true,cashInstructions:'U vstupu',providerConnections:{}}}}));assert.equal(opened.code,200,JSON.stringify(opened));assert.equal(opened.data.authoring.form.data.schedule.sale_preparation,false);
});

test('invalid SQL settings reject atomically before title/field mutation and cannot patch private lifecycle metadata',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);const before=await stored(db,made.formId);
 const invalid=[{design:{presale_header:'event_and_date',theme_mode:'auto'}},{design:{presale_header:'event_and_date',theme_mode:true}},{unknown:true},{schedule:{sale_preparation:false}},{design:{paper_texture:'injected'}},{payments:{account_id:'acct_injected'}},{is_reminder_enabled:'true'},{reminder_interval_seconds:-1},{reminder_interval_seconds:1.5},{communication_tone:'casual'},{variable_symbol:{type:'sequence'}},{variable_symbol:{starting_number:10000000000}},{variable_symbol:{type:'sequence',starting_number:'123'}},{payment_message:{type:'custom'}},{design:{primary_color:'red'}},{payments:{stripeConnectionId:'wrong'}},{schedule:{start_time:'2030-01-01T00:00:00'}},{schedule:{start_time:'2031-01-01T00:00:00Z',end_time:'2030-01-01T00:00:00Z'}}];
 await db.query('SET LOCAL ROLE authenticated');
 for(const settings of invalid){await db.query('SAVEPOINT invalid_settings');const rejected=await save(db,f,formPatch(made.authoring,{title:'Must rollback',settings})).catch(error=>{assert(error.code?.startsWith('22'),JSON.stringify(settings)+' '+error.message);return null;});if(rejected)assert.equal(rejected.status,'rejected',JSON.stringify(settings));await db.query('ROLLBACK TO SAVEPOINT invalid_settings');await db.query('RELEASE SAVEPOINT invalid_settings');assert.deepEqual(await stored(db,made.formId),before);assert.equal((await db.query('select title from forms where id=$1',[made.formId])).rows[0].title,'Synthetic form');}
 const inspected=(await executor(db,f).ops.invoke('forms.inspect',{occasionId:f.occasion,formId:made.formId})).data.authoring;assert.equal(inspected.form.aggregate_version,made.authoring.form.aggregate_version);
});

test('released metadata boundary normalizes historical data and uses the same settings validation as the new patch',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);const metadata={private_owner:9,is_reminder_enabled:false,communication_tone:'informal',design:{primary_color:'#112233',paper_texture:'pattern'}};
 await db.query('SET LOCAL ROLE authenticated');const legacy=async p=>(await db.query('select update_form_client_sync_v1($1,$2) value',[{occasion:f.occasion,...p},randomUUID()])).rows[0].value;
 const result=await legacy(formPatch(made.authoring,{data:[null,metadata]}));assert.equal(result.code,200,JSON.stringify(result));assert.deepEqual(result.data.authoring.form.data,{...metadata,design:{...metadata.design,presale_header:'event_and_date'},payments:{bankEnabled:true}});
 await denied(db,'select update_form_client_sync_v1($1,$2)',[{occasion:f.occasion,...formPatch(result.data.authoring,{data:{...metadata,reminder_interval_seconds:-1},title:'Must rollback'})},randomUUID()],'22023');assert.deepEqual(await stored(db,made.formId),{...metadata,design:{...metadata.design,presale_header:'event_and_date'},payments:{bankEnabled:true}});
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
 const{db,f}=await setup(t);const made=await create(db,f);const conn=randomUUID();await db.query("insert into eshop.organization_payment_method_policies(organization_id,method,enabled) values($1,'stripe',true)",[f.org]);await db.query(`update organizations set data=coalesce(data,'{}')||'{"DEFAULT_URL":"https://forms.example.invalid"}' where id=$1`,[f.org]);
 await db.query("insert into eshop.stripe_connections(id,organization_id,unit_id,account_id,livemode,state,model_verified,paused,charges_enabled,card_payments_active,business_name) values($1,$2,$3,$4,true,'connected',true,false,true,true,'Synthetic recipient')",[conn,f.org,f.unit,'acct_'+conn.replaceAll('-','')]);
 const otherUnit=(await db.query("insert into units(title,organization) values('Other recipient unit',$1) returning id",[f.org])).rows[0].id;const other=randomUUID();await db.query("insert into eshop.stripe_connections(id,organization_id,unit_id,account_id,livemode,state,model_verified) values($1,$2,$3,$4,true,'connected',true)",[other,f.org,otherUnit,'acct_'+other.replaceAll('-','')]);
 const counts=async()=> (await db.query('select (select count(*) from eshop.payment_info) payments,(select count(*) from eshop.payment_reference_reservations) refs')).rows[0];const before=await counts();
 await db.query('SET LOCAL ROLE authenticated');let result=await save(db,f,formPatch(made.authoring,{settings:{payments:{bankEnabled:false,stripeConnectionId:conn}}}));assert.equal(result.code,200,JSON.stringify(result));
 const options=await executor(db,f).ops.invoke('forms.paymentOptions',{occasionId:f.occasion,formId:made.formId,livemode:true});assert.equal(options.ok,true,JSON.stringify(options));assert.equal(options.data.stripeRecipient.connectionId,conn);assert(!JSON.stringify(options).includes('acct_'));
 assert.equal(options.data.availability.providers.stripe.configured,true);assert.notEqual(options.data.availability.providers.stripe.reason.code,null); // no live activation in fixture
 const modern=await executor(db,f).ops.invoke('forms.save',{occasionId:f.occasion,commandId:randomUUID(),form:formPatch(result.data.authoring,{settings:{payments:{bankEnabled:false,providerConnections:{stripe:conn}}}})});assert.equal(modern.ok,true,JSON.stringify(modern));result={data:modern.data};
 const foreign=await save(db,f,formPatch(result.data.authoring,{settings:{payments:{providerConnections:{stripe:other}}},title:'Must rollback'}));assert.equal(foreign.status,'rejected',JSON.stringify(foreign));assert.equal((await stored(db,made.formId)).payments.providerConnections.stripe,conn);
 await db.query('RESET ROLE');await db.query('update eshop.stripe_connections set paused=true where id=$1',[conn]);await db.query('SET LOCAL ROLE authenticated');result=await save(db,f,formPatch(result.data.authoring,{settings:{payment_message:{type:'none'}}}));assert.equal(result.code,200,JSON.stringify(result));
 const paused=await executor(db,f).ops.invoke('forms.paymentOptions',{occasionId:f.occasion,formId:made.formId,livemode:true});assert.equal(paused.data.availability.providers.stripe.reason.code,'paused');assert.equal(result.data.authoring.form.data.payments.providerConnections.stripe,conn);
 await db.query('RESET ROLE');assert.deepEqual(await counts(),before);
});

test('payment null resets share the canonical merge owner and the real MCP save contract',options,async t=>{
 const{db,f}=await setup(t);const connections={stripe:randomUUID(),barion:randomUUID()};
 const payments={bankEnabled:false,cashEnabled:false,cashInstructions:'',providerConnections:connections};
 const merge=async input=>(await db.query('select merge_form_payments_internal($1,$2) value',[payments,input])).rows[0].value;
 assert.deepEqual(await merge(null),payments,'SQL NULL is an internal preservation request');
 const patch=async value=>(await db.query('select apply_form_settings_internal($1,$2) value',[{payments,private_owner:7},{payments:value}])).rows[0].value;
 assert.deepEqual(await patch(null),{payments:defaultPayments,private_owner:7});
 assert.deepEqual(await patch({bankEnabled:null,providerConnections:connections}),{payments:{bankEnabled:false,cashEnabled:false,cashInstructions:'',providerConnections:connections},private_owner:7});
 assert.deepEqual(await patch({providerConnections:null}),{payments:{bankEnabled:false,cashEnabled:false,cashInstructions:'',providerConnections:{}},private_owner:7});
 assert.deepEqual(await merge({bankEnabled:true}),{bankEnabled:true,cashEnabled:false,cashInstructions:'',providerConnections:{barion:connections.barion}},'released Stripe-only omission preserves other providers');
 const made=await create(db,f);await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);
 let result=await ex.ops.invoke('forms.save',{occasionId:f.occasion,commandId:randomUUID(),form:formPatch(made.authoring,{settings:{payments:{bankEnabled:false,cashEnabled:false,cashInstructions:'',providerConnections:{}}}})});
 assert.equal(result.ok,true,JSON.stringify(result));
 for(const value of [{bankEnabled:null,providerConnections:{}},null,{providerConnections:null}]){
  result=await ex.ops.invoke('forms.save',{occasionId:f.occasion,commandId:randomUUID(),form:formPatch(result.data.authoring,{settings:{payments:value}})});
  assert.equal(result.ok,true,JSON.stringify(result));assert.deepEqual(result.data.authoring.form.data.payments,defaultPayments);
 }
});

test('incomplete payment methods and foreign bank selection roll back settings and other aggregate writes together',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);await db.query('update eshop.products set price=100 where id=$1',[made.authoring.products[0].id]);await db.query('SET LOCAL ROLE authenticated');
 const result=await save(db,f,formPatch(made.authoring,{is_open:true,title:'Must rollback',settings:{payments:{bankEnabled:false,stripeConnectionId:null}}}));assert.equal(result.status,'rejected',JSON.stringify(result));assert.equal((await db.query('select is_open from forms where id=$1',[made.formId])).rows[0].is_open,false);
 const foreign=await save(db,f,formPatch(made.authoring,{bank_account:999999999,title:'Must rollback',settings:{communication_tone:'informal'}}));assert.equal(foreign.status,'rejected');assert.equal((await stored(db,made.formId))?.communication_tone,undefined);
});

for(const file of ['eshop/reminders/form_reminder_inheritance_test.sql','eshop/stripe/connections_test.sql']){
 test('existing settings consumer: '+file,options,async t=>{
  const{db}=await setup(t);
  await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
  if(file.includes('reminder')) await db.query("select set_config('request.jwt.claim.role','service_role',true)");
  const sql=await readFile(new URL('../../../database/tests/'+file,import.meta.url),'utf8');
  // Honor the same test-owned setup contract as the canonical SQL runner.
  for(const [,source] of sql.matchAll(/^-- test-setup: (database\/[\w./-]+\.sql)$/gm)) {
   await db.query(await readFile(new URL('../../../'+source,import.meta.url),'utf8'));
  }
  await db.query(sql);
 });
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
 await db.query('RESET ROLE');const persisted=await stored(db,made.formId);assert.deepEqual(persisted,{private_owner:7,schedule:{sale_preparation:true},payments:defaultPayments});
 const after=(await db.query("select get_form_availability_snapshot_internal($1,'2029-01-01T00:00:00Z') value",[made.formId])).rows[0].value;assert.equal(after.startAt,null);assert.equal(after.endAt,null);
 // The bounded released-input adapter also retires aliases on its next save.
 const saved=(await db.query('select update_form_client_sync_v1($1,$2) value',[{occasion:f.occasion,...formPatch(reset.data.authoring,{data:legacy})},randomUUID()])).rows[0].value;assert.equal(saved.code,200,JSON.stringify(saved));const canonical=await stored(db,made.formId);assert(!Object.hasOwn(canonical,'start_time'));assert(!Object.hasOwn(canonical,'end_time'));assert(canonical.schedule.start_time.includes('T'));
});


test('wizard design round-trips through the form editor and MCP save without losing background mode',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);
 const design={primary_color:'#14284B',secondary_color:'#A87F28',background_mode:'gradient',font_family:'Roboto Slab'};
 await db.query('update forms set data=$2 where id=$1',[made.formId,{design}]);
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);
 const saveMode=async(state,mode)=>{
  const result=await ex.ops.invoke('forms.save',{occasionId:f.occasion,form:formPatch(state,{settings:{design:{...design,background_mode:mode}}}),commandId:randomUUID()});
  assert.equal(result.ok,true,JSON.stringify(result));
  assert.deepEqual(result.data.authoring.form.data.design,{...design,background_mode:mode});
  return result.data.authoring;
 };
 const gradient=await saveMode(made.authoring,'gradient');
 const solid=await saveMode(gradient,'solid');
 const reset=await save(db,f,formPatch(solid,{settings:{design:{background_mode:null}}}));
 assert.equal(reset.code,200,JSON.stringify(reset));assert.equal(reset.data.authoring.form.data.design.background_mode,undefined);
 assert.equal(reset.data.authoring.form.data.design.primary_color,design.primary_color);
 await denied(db,"select manage_form($1,$2,$3,'save',$4,$5)",[f.occasion,f.org,f.unit,formPatch(reset.data.authoring,{settings:{design:{background_mode:'unsupported'}}}),randomUUID()],'22023');
});

test('form appearance partial writes preserve unrelated design and reset to system default',options,async t=>{
 const {db}=await setup(t);
 let data={design:{primary_color:'#123456'}};
 for(const mode of ['light','dark','system']){
  data=(await db.query('select apply_form_settings_internal($1,$2) value',[data,{design:{theme_mode:mode}}])).rows[0].value;
  assert.deepEqual(data.design,{primary_color:'#123456',theme_mode:mode});
 }
 data=(await db.query('select apply_form_settings_internal($1,$2) value',[data,{design:{theme_mode:null}}])).rows[0].value;
 assert.deepEqual(data,{design:{primary_color:'#123456'}});
});


test('MCP sale-opening settings use the actual campaign owner and keep workflow state server-owned',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);await db.query('SET LOCAL ROLE authenticated');
 const ex=executor(db,f);
 const enabled=await ex.ops.invoke('forms.save',{occasionId:f.occasion,commandId:randomUUID(),form:formPatch(made.authoring,{is_open:true,payment_selection_intent:'replace',settings:{payment_deadline:{mode:'none'},payments:{bankEnabled:false,cashEnabled:true,cashInstructions:'U vstupu',providerConnections:{}},schedule:{start_time:'2030-01-15T18:00:00+01:00',end_time:'2030-02-20T12:00:00+01:00'},sale_opening_notifications:{enabled:true,collection_paused:false}}})});
 assert.equal(enabled.ok,true,JSON.stringify(enabled));assert.equal(enabled.data.authoring.form.data.sale_opening_notifications.enabled,true);
 await db.query('RESET ROLE');
 const campaign=(await db.query('select id,phase from sale_opening_campaigns where form_id=$1',[made.formId])).rows[0];assert.equal(campaign.phase,'armed');
 await db.query('SET LOCAL ROLE authenticated');
 const disabled=await ex.ops.invoke('forms.save',{occasionId:f.occasion,commandId:randomUUID(),form:formPatch(enabled.data.authoring,{settings:{sale_opening_notifications:{enabled:false}}})});
 assert.equal(disabled.ok,true,JSON.stringify(disabled));
 await db.query('RESET ROLE');
 assert.deepEqual((await db.query('select id,phase from sale_opening_campaigns where form_id=$1',[made.formId])).rows[0],{id:campaign.id,phase:'cancelled'});
 assert.equal(Number((await db.query('select count(*) n from sale_opening_subscriptions where campaign_id=$1',[campaign.id])).rows[0].n),0);
});

test('embed appearance accepts only booleans, patches without losing design and resets',options,async t=>{
 const {db}=await setup(t);
 let data={design:{font_family:'Noto Sans',paper_texture:'keep'}};
 for(const enabled of [false,true]) {
  data=(await db.query('select apply_form_settings_internal($1,$2) value',[data,{design:{embed_inherit_style:enabled}}])).rows[0].value;
  assert.equal(data.design.embed_inherit_style,enabled);
  assert.equal(data.design.font_family,'Noto Sans');
  assert.equal(data.design.paper_texture,'keep');
 }
 for(const invalid of ['false',0,{},[]]) await denied(db,'select apply_form_settings_internal($1,$2)',[data,{design:{embed_inherit_style:invalid}}],'22023');
 data=(await db.query('select apply_form_settings_internal($1,$2) value',[data,{design:{embed_inherit_style:null}}])).rows[0].value;
 assert.equal('embed_inherit_style' in data.design,false);
});

test('released full-metadata saves preserve an omitted embed preference and honor explicit changes',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);
 await db.query('SET LOCAL ROLE authenticated');
 let result=await save(db,f,formPatch(made.authoring,{settings:{design:{embed_inherit_style:false}}}));
 assert.equal(result.code,200,JSON.stringify(result));
 for(const design of [false,[],{embed_inherit_style:'false'}]) {
  await denied(db,'select update_form_client_sync_v1($1,$2)',[
   {occasion:f.occasion,...formPatch(result.data.authoring,{data:{design}})},randomUUID()
  ],'22023');
  assert.equal((await stored(db,made.formId)).design.embed_inherit_style,false);
 }
 for(const [data,expected] of [[{},false],[{design:null},false],[{design:{font_family:'Noto Sans'}},false],
     [{design:{embed_inherit_style:true}},true],[{design:{embed_inherit_style:false}},false],
     [{design:{embed_inherit_style:null}},undefined]]) {
  result=(await db.query('select update_form_client_sync_v1($1,$2) value',[
    {occasion:f.occasion,...formPatch(result.data.authoring,{data})},randomUUID()
  ])).rows[0].value;
  assert.equal(result.code,200,JSON.stringify(result));
  assert.equal(result.data.authoring.form.data.design?.embed_inherit_style,expected);
 }
});

test('form authors toggle intent but cannot supply Unit destination settings',options,async t=>{
 const{db,f}=await setup(t);const made=await create(db,f);await db.query('SET LOCAL ROLE authenticated');
 const saved=await save(db,f,formPatch(made.authoring,{settings:{analytics:{enabled:true}}}));assert.equal(saved.code,200,JSON.stringify(saved));
 assert.deepEqual(saved.data.authoring.form.data.analytics,{enabled:true});
 await denied(db,'select apply_form_settings_internal($1,$2)',['{}',{analytics:{gtm_container:'GTM-AB12'}}]);
 await db.query('SAVEPOINT unsupported');
 await assert.rejects(save(db,f,formPatch(saved.data.authoring,{settings:{analytics:{gtm_container:'GTM-CD34'}}})),/unsupported form setting/);
 await db.query('ROLLBACK TO SAVEPOINT unsupported');await db.query('RESET ROLE');
});

test('measurement save separates request, platform policy, historical receipt and current authorized status',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);const ex=executor(db,f);
 await db.query('insert into organization_users(organization,"user",is_admin) values($1,$2,true) on conflict(organization,"user") do update set is_admin=true',[f.org,f.actor]);
 await db.query('SET LOCAL ROLE authenticated');
 const invoke=async(snapshot,analytics,extra={})=>ex.ops.invoke('forms.save',{occasionId:f.occasion,commandId:randomUUID(),form:formPatch(snapshot,{...extra,settings:{analytics}})});
 const configured=await invoke(made.authoring,{enabled:false});assert.equal(configured.ok,true,JSON.stringify(configured));
 assert.equal(configured.data.current_measurement_status.requested_enabled,false);assert.equal(configured.data.current_measurement_status.organization_allowed,false);
 const args={occasionId:f.occasion,commandId:randomUUID(),form:formPatch(configured.data.authoring,{settings:{analytics:{enabled:true}}})};
 const enabled=await ex.ops.invoke('forms.save',args);assert.equal(enabled.ok,true,JSON.stringify(enabled));assert.equal(enabled.data.measurement_status_is_historical,true);
 assert.equal(enabled.data.current_measurement_status.requested_enabled,true);assert.equal(enabled.data.current_measurement_status.eligible,false);
 await db.query('RESET ROLE');await db.query("insert into analytics.organization_policy(organization,enabled,revision,operator,reason) values($1,true,2,'fixture','local test')",[f.org]);await db.query('SET LOCAL ROLE authenticated');
 const replay=await ex.ops.invoke('forms.save',args);assert.equal(replay.ok,true,JSON.stringify(replay));assert.deepEqual(replay.data.authoring,enabled.data.authoring);
 assert.equal(replay.data.authoring.form.measurement_status.organization_allowed,false);assert.equal(replay.data.current_measurement_status.organization_allowed,true);assert.equal(replay.data.current_measurement_status.policy_revision,2);
 const off=await invoke(replay.data.authoring,{enabled:false});assert.equal(off.ok,true,JSON.stringify(off));assert.equal(off.data.authoring.form.data.analytics.gtm_container,undefined);
 const reset=await invoke(off.data.authoring,{enabled:null});assert.equal(reset.ok,true,JSON.stringify(reset));assert.equal(reset.data.current_measurement_status.requested_enabled,false);
 const cleared=await invoke(reset.data.authoring,null);assert.equal(cleared.ok,true,JSON.stringify(cleared));assert.equal(cleared.data.authoring.form.data.analytics,undefined);
 await denied(db,"insert into analytics.organization_policy(organization,enabled,revision,operator,reason) values($1,true,1,'bad','bad')",[f.org+1]);
});


test('Global MCP form creation, copy and payment options have no bank fallback before hosted onboarding',options,async t=>{
 const {db,f}=await setup(t);
 await db.query("update eshop.organization_payment_method_policies set enabled=false where organization_id=$1",[f.org]);
 await db.query("insert into eshop.organization_payment_method_policies(organization_id,method,enabled) values($1,'stripe',true) on conflict(organization_id,method) do update set enabled=true",[f.org]);
 await db.query("update eshop.payment_method_policy_scopes set preferred_method='stripe' where organization_id=$1",[f.org]);
 const made=await create(db,f,'Global registrace');
 assert.equal(made.authoring.form.data.payments.bankEnabled,false);
 const bank=(await db.query("insert into eshop.bank_accounts(title,type,account_number) values('Historický účet','FIO','123456/0800') returning id")).rows[0].id;
 await db.query('insert into eshop.unit_bank_accounts(unit,bank_account) values($1,$2)',[f.unit,bank]);
 const opts=await executor(db,f).ops.invoke('forms.paymentOptions',{occasionId:f.occasion,formId:made.formId,livemode:true});
 assert.equal(opts.ok,true,JSON.stringify(opts));assert.deepEqual(opts.data.bankAccounts,[]);
 assert.deepEqual(opts.data.availability.available,[]);
 assert.equal(opts.data.paymentMethodPolicy.preferredMethod,'stripe');
 assert.equal(opts.data.paymentMethodPolicy.methods.bank.policyEnabled,false);
 const target=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);
 const copy=(await db.query("select manage_form($1,$2,$3,'duplicate',$4,$5) value",[target,f.org,f.unit,{source_form_id:made.formId,source_occasion_id:f.occasion,source_unit_id:f.unit,locale:'en'},randomUUID()])).rows[0].value;
 assert.equal(copy.code,200,JSON.stringify(copy));
 assert.equal(copy.data.authoring.form.data.payments.bankEnabled,false);
});
