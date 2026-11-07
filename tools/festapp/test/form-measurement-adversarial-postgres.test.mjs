import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {options,setup,executor,create,formPatch,save,denied} from './form-fixtures.mjs';
import {formDescriptors} from '../src/operations/forms.mjs';

async function admin(db,f){await db.query('insert into organization_users(organization,"user",is_admin) values($1,$2,true)',[f.org,f.actor]);}

test('actual API roles cannot write measurement policy, conversion facts or forms and cannot call private helpers',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);await admin(db,f);
 for(const role of ['anon','authenticated','service_role']){
  await db.query('SET LOCAL ROLE '+role);
  for(const sql of [
   "insert into analytics.organization_policy(organization,enabled,revision,operator,reason) values($1,true,1,'injected','injected')",
   'update analytics.organization_policy set enabled=true where organization=$1',
   'delete from analytics.organization_policy where organization=$1',
   'select * from analytics.organization_policy where organization=$1',
  ])await denied(db,sql,[f.org]);
  await denied(db,'truncate analytics.organization_policy',[]);
  await denied(db,"update forms set data='{\"analytics\":{\"enabled\":true}}' where id=$1",[made.formId]);
  await denied(db,'select * from analytics.conversion_facts',[]);
  for(const sql of ['select form_measurement_status_internal($1)','select form_measurement_runtime_internal($1)',
"select form_conversion_datalayer_internal($1,'purchase')",'select record_form_conversion_internal($1)',
   'select get_effective_form_data($1)'])await denied(db,sql,[made.formId]);
  await db.query('RESET ROLE');
 }
});

test('saved receipts and fresh inspection stop exposing measurement after every authoring role is revoked',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);await admin(db,f);
 await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);
 const args={occasionId:f.occasion,commandId:randomUUID(),form:formPatch(made.authoring,{settings:{analytics:{enabled:true}}})};
 const saved=await ex.ops.invoke('forms.save',args);assert.equal(saved.ok,true,JSON.stringify(saved));
 await db.query('RESET ROLE');
 await db.query('delete from organization_users where "user"=$1',[f.actor]);
 await db.query('delete from unit_users where "user"=$1',[f.actor]);
 await db.query('delete from occasion_users where "user"=$1',[f.actor]);
 await db.query('SET LOCAL ROLE authenticated');
 for(const [operation,payload] of [['forms.inspect',{occasionId:f.occasion,formId:made.formId}],['forms.save',args]]){
  const result=await ex.ops.invoke(operation,payload);assert.equal(result.ok,false,JSON.stringify(result));assert.equal(result.error.code,'FORBIDDEN');assert.equal(result.data,undefined);
 }
 await denied(db,'select get_form_for_authoring($1,$2,$3,$4)',[f.occasion,f.org,f.unit,made.formId]);
});

test('invalid booleans and attempted derived-state injection roll back the complete save, including versions',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);await admin(db,f);await db.query('SET LOCAL ROLE authenticated');
 const before=(await db.query('select title,data from forms where id=$1',[made.formId])).rows[0];
 const schema=formDescriptors.find(d=>d.id==='forms.save').input;
 for(const invalid of ['true',1,0,[],{}]){
  const payload=formPatch(made.authoring,{title:'Must roll back',settings:{analytics:{enabled:invalid}}});
  assert.equal(schema.safeParse({occasionId:f.occasion,commandId:randomUUID(),form:payload}).success,false);
  await denied(db,"select manage_form($1,$2,$3,'save',$4,$5)",[f.occasion,f.org,f.unit,payload,randomUUID()],'22023');
 }
 for(const key of ['organization_allowed','measurement_status','runtime_supported','consent_required','policy_revision']){
  const payload=formPatch(made.authoring,{title:'Must roll back',settings:{analytics:{enabled:true,[key]:true}}});
  assert.equal(schema.safeParse({occasionId:f.occasion,commandId:randomUUID(),form:payload}).success,false);
  await denied(db,"select manage_form($1,$2,$3,'save',$4,$5)",[f.occasion,f.org,f.unit,payload,randomUUID()],'22023');
 }
 assert.deepEqual((await db.query('select title,data from forms where id=$1',[made.formId])).rows[0],before);
 const inspected=(await db.query('select get_form_for_authoring($1,$2,$3,$4) value',[f.occasion,f.org,f.unit,made.formId])).rows[0].value;
 assert.equal(inspected.authoring.form.aggregate_version,made.authoring.form.aggregate_version);
 const preserved=await save(db,f,formPatch(made.authoring,{settings:{analytics:{enabled:true}}}));assert.equal(preserved.code,200);
});

test('stored form ownership defeats forged scope; public open and closed bundles never expose organizer code or enhanced settings',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);await admin(db,f);
 const foreign=(await db.query("insert into organizations(title) values('Unrelated tenant') returning id")).rows[0].id;
 await db.query("insert into analytics.organization_policy(organization,enabled,revision,operator,reason) values($1,true,8,'fixture','foreign permission')",[foreign]);
 await db.query("update forms set is_open=true,data='{\"analytics\":{\"enabled\":true,\"gtm_container\":\"GTM-AB12\",\"scripts\":\"<script>CODE_SENTINEL_733</script>\",\"enhanced_conversions\":true}}' where id=$1",[made.formId]);
 const scope=(await db.query('select form_measurement_status_internal($1) value',[made.formId])).rows[0].value;assert.equal(scope.organization_allowed,false);
 await db.query('SET LOCAL ROLE authenticated');
 await denied(db,'select get_form_for_authoring($1,$2,$3,$4)',[f.occasion,foreign,f.unit,made.formId]);
 const otherOcc=(await db.query('select id from occasions where organization=$1 and id<>$2 limit 1',[f.org,f.occasion])).rows[0].id;
 await denied(db,'select get_form_for_authoring($1,$2,$3,$4)',[otherOcc,f.org,f.unit,made.formId]);
 await db.query('RESET ROLE');
 const link=(await db.query('select link from forms where id=$1',[made.formId])).rows[0].link;
 await db.query("select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','anon',true)");
 await db.query('SET LOCAL ROLE anon');
 const publicBundle=(await db.query('select get_form_by_link($1) value',[link])).rows[0].value;
 assert.equal(publicBundle.code,200,JSON.stringify(publicBundle));assert(!JSON.stringify(publicBundle).includes('CODE_SENTINEL_733'));assert(!JSON.stringify(publicBundle).includes('GTM-AB12'));assert.equal(publicBundle.data.data.analytics.enhanced_conversions_unavailable,false);assert.equal(Object.hasOwn(publicBundle.data.data.analytics,'enhanced_conversions'),false);
 await db.query('RESET ROLE');
 await db.query('update forms set is_open=false where id=$1',[made.formId]);
 const closedPreview=(await db.query('select get_form_bundle_internal($1,true) value',[made.formId])).rows[0].value;
 assert(!JSON.stringify(closedPreview).includes('CODE_SENTINEL_733'));assert(!JSON.stringify(closedPreview).includes('GTM-AB12'));
});

test('public app/catalog Unit projections redact destination code while authorized Unit manager can edit it',options,async t=>{
 const {db,f}=await setup(t);await db.query("update units set data=coalesce(data,'{}')||'{\"measurement_gtm_container\":\"GTM-AB12\",\"measurement_scripts\":\"UNIT_CODE_SENTINEL_733\"}' where id=$1",[f.unit]);
 await db.query("select set_config('request.jwt.claim.sub','',true)");await db.query('SET LOCAL ROLE anon');
 for(const [query,args] of [['select get_app_config_v218($1) value',[{organization:f.org,unit_id:f.unit,platform:{platform:'web'}}]],['select get_public_occasions($1,$2) value',[f.org,f.unit]]]){
  const response=(await db.query(query,args)).rows[0].value;assert(!JSON.stringify(response).includes('UNIT_CODE_SENTINEL_733'));assert(!JSON.stringify(response).includes('GTM-AB12'));
 }
 await db.query('RESET ROLE');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');
 const editable=(await db.query('select get_unit_for_edit($1) value',[f.unit])).rows[0].value;
 assert(JSON.stringify(editable).includes('UNIT_CODE_SENTINEL_733'));
});
