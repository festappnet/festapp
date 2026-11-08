import test from 'node:test';
import assert from 'node:assert/strict';
import {Operations} from '../src/operations/catalog.mjs';
import {invokeFormOperation} from '../src/operations/forms.mjs';
function fixture(data,error=null){let calls=0;const owner={root:'/tmp/form-boundary',profile:{name:'fixture',organizationId:3,tenantId:'fixture'},allowedOperations:['forms.inspect','forms.list','forms.save','forms.paymentOptions'],delegatedContext:async()=>({organizationId:3,unitId:8}),authorized:fn=>fn({rpc:async()=>{calls++;return{data,error};}},{userId:'00000000-0000-4000-8000-000000000001'})};return{ops:new Operations(owner),calls:()=>calls};}
const state={form:{id:42,occasion:7,aggregate_version:0},fields:[],products:[],productTypes:[],productVersions:{},productTypeVersions:{}};
test('form save explains missing account permission without exposing upstream details',async()=>{
 const args={occasionId:7,commandId:'00000000-0000-4000-8000-000000000099',form:{id:42,expected_aggregate_version:0,expected_product_versions:{},expected_product_type_versions:{}}};
 for(const message of ['form operation denied','form editor required','foreign form','unrecognized private server text']){
  const f=fixture(null,{code:'42501',message,details:'private-upstream-detail'});
  const result=await f.ops.invoke('forms.save',args);
  assert.equal(result.error.code,'FORBIDDEN');
  assert.match(result.error.message,/account.*form editor/i);
  assert.match(result.error.message,/organizer.*verify your role/i);
  assert.match(result.error.message,/OAuth.*does not/i);
  assert.equal(result.error.retryable,false);assert.equal(f.calls(),1);
  assert(!JSON.stringify(result).includes('private-upstream-detail'));
 }
});
test('form projection omits internal fields while catalog output rejects unexpected keys',async()=>{
 for(const name of ['key','link']){
  const f=fixture({occasionId:7,authoring:{...state,form:{...state.form,[name]:'private-public-capability'}}});
  const result=await f.ops.invoke('forms.inspect',{occasionId:7,formId:42});assert.equal(result.ok,true);assert(!Object.hasOwn(result.data.authoring.form,name));assert(!JSON.stringify(result).includes('private-public-capability'));
  const list=fixture({occasionId:7,forms:[{id:42,occasion:7,aggregate_version:0,[name]:'private-public-capability'}],nextCursor:null});assert.equal((await list.ops.invoke('forms.list',{occasionId:7})).ok,false);
 }
});
test('form inspect rejects the wrong object and save does not accept arbitrary form data or public URL patches',async()=>{
 const wrong=fixture({occasionId:7,authoring:{...state,form:{...state.form,id:43}}});assert.equal((await wrong.ops.invoke('forms.inspect',{occasionId:7,formId:42})).ok,false);
 const f=fixture(null);for(const extra of [{data:{arbitrary:'setting'}},{link:'new-link'},{key:'new-key'}]){
  const result=await f.ops.invoke('forms.save',{occasionId:7,commandId:'00000000-0000-4000-8000-000000000099',form:{id:42,expected_aggregate_version:0,expected_product_versions:{},expected_product_type_versions:{},...extra}});assert.equal(result.error.code,'INVALID_INPUT');
 }assert.equal(f.calls(),0);
});

test('settings input rejects arbitrary subkeys, lifecycle flags and timezone-free dates before RPC',async()=>{
 const f=fixture(null);
 for(const settings of [{payments:{providerConnections:{stripe:'invalid'}}},{payments:{providerConnections:{'bad provider':'00000000-0000-4000-8000-000000000099'}}},{unknown:true},{analytics:{gtm_container:'GTM-AB12'}},{analytics:{scripts:'<script>old form configuration</script>'}},{analytics:{enhanced_conversions:true}},{schedule:{sale_preparation:false}},{schedule:{start_time:'2030-01-01T00:00:00'}},{design:{background_mode:'pattern'}},{payments:{account_id:'acct_fake'}},{variable_symbol:{starting_number:10000000000}}]){
  const result=await f.ops.invoke('forms.save',{occasionId:7,commandId:'00000000-0000-4000-8000-000000000099',form:{id:42,expected_aggregate_version:0,expected_product_versions:{},expected_product_type_versions:{},settings}});assert.equal(result.error.code,'INVALID_INPUT',JSON.stringify(result));
 }assert.equal(f.calls(),0);
});

test('payment selection output rejects unexpected credentials in bank or Stripe projection',async()=>{
 const policy={reservationSeconds:1860,fullPaymentOnly:true,depositsSupported:false,surchargesSupported:false};
 const provider={providerId:'stripe',configured:false,available:false,recipient:null,supportedSurfaces:[],reason:{code:'not_configured'},policy};
 const value={occasionId:7,formId:42,livemode:true,bankAccounts:[],stripeRecipient:null,providerEditorFields:{stripe:{stripeRecipient:null},barion:{}},policy,
  availability:{bank:{configured:true,available:true},providers:{stripe:provider,barion:{...provider,providerId:'barion',reason:{code:'sandbox_only'}}},policy,
   configured:{bank:true,stripe:false},available:['bank'],stripeUnavailableReason:'not_configured',reservationSeconds:1860,supportedSurfaces:[],recipient:null}};
 assert.equal((await fixture(value).ops.invoke('forms.paymentOptions',{occasionId:7,formId:42,livemode:true})).ok,true);
 for(const extra of [{bankAccounts:[{id:1,account_number:null,account_number_human_readable:null,title:null,supported_currencies:null,type:null,bank_sync_warning:null,secret:'unexpected-credential'}]},{stripeRecipient:{connectionId:'00000000-0000-4000-8000-000000000099',name:null,state:'connected',paused:false,modelVerified:true,chargesEnabled:true,payoutsEnabled:false,cardPaymentsActive:true,checkedAt:null,unsupportedReason:null,account_id:'unexpected-credential'}},
  {providerEditorFields:{barion:{secret:'unexpected-credential'}}},
  {availability:{...value.availability,providers:{...value.availability.providers,stripe:{...provider,recipient:{connectionId:'00000000-0000-4000-8000-000000000099',name:null,secret:'unexpected-credential'}}}}}]){
  const result=await fixture({...value,...extra}).ops.invoke('forms.paymentOptions',{occasionId:7,formId:42,livemode:true});assert.equal(result.ok,false);assert(!JSON.stringify(result).includes('unexpected-credential'));
 }
});

const measurementStatus={requested_enabled:false,organization_allowed:false,organization_enabled:false,unit_enabled:false,
 runtime_supported:true,eligible:false,blocked_reasons:['disabled'],policy_revision:1,
 consent_required:true,enhanced_conversions_unavailable:false};
test('form inspect tolerates missing status and future internal fields without inventing a measurement policy',async()=>{
 for(const status of [undefined,null,measurementStatus]){
  const form={...state.form,...(status===undefined?{}:{measurement_status:status}),future_internal_flag:'internal-only'};
  const f=fixture({occasionId:7,authoring:{...state,form}});
  const result=await f.ops.invoke('forms.inspect',{occasionId:7,formId:42});
  assert.equal(result.ok,true,JSON.stringify(result));
  assert.deepEqual(result.data.authoring.form.measurement_status,status??null);
  assert.equal(Object.hasOwn(result.data.authoring.form,'future_internal_flag'),false);
  assert(!JSON.stringify(result).includes('internal-only'));
 }
 for(const invalid of [true,{}, {...measurementStatus,eligible:'yes'}]){
  const f=fixture({occasionId:7,authoring:{...state,form:{...state.form,measurement_status:invalid}}});
  assert.equal((await f.ops.invoke('forms.inspect',{occasionId:7,formId:42})).ok,false);
 }
});

test('form mutation readback defaults a missing measurement status to unknown',async()=>{
 const commandId='00000000-0000-4000-8000-000000000099',calls=[];
 const owner={delegatedContext:async()=>({organizationId:3,unitId:8})};
 const client={rpc:async(name)=>{
  calls.push(name);
  if(name==='manage_form')return{error:null,data:{code:200,status:'applied',mutation:{commandId,receiptId:commandId},
   data:{occasionId:7,formId:42,authoring:state}}};
  assert.equal(name,'get_form_for_authoring');return{error:null,data:{occasionId:7,authoring:state}};
 }};
 const result=await invokeFormOperation(owner,client,'forms.save',{occasionId:7,form:{id:42},commandId});
 assert.equal(result.authoring.form.measurement_status,null);
 assert.equal(result.current_measurement_status,null);
 assert.equal(result.measurement_status_is_historical,true);
 assert.deepEqual(calls,['manage_form','get_form_for_authoring']);
});

test('form status is truthful now and durable receipts keep the earlier value',async()=>{
 for(const enhanced_conversions_unavailable of [false,true]){
  const status={...measurementStatus,enhanced_conversions_unavailable};
  const f=fixture({occasionId:7,authoring:{...state,form:{...state.form,measurement_status:status}}});
  const result=await f.ops.invoke('forms.inspect',{occasionId:7,formId:42});
  assert.equal(result.ok,true,JSON.stringify(result));assert.deepEqual(result.data.authoring.form.measurement_status,status);
 }
 const {enhanced_conversions_unavailable,...base}=measurementStatus;
 for(const invalid of [{...base,enhanced_conversions_unavailable:'true'},base]){
  const f=fixture({occasionId:7,authoring:{...state,form:{...state.form,measurement_status:invalid}}});
  assert.equal((await f.ops.invoke('forms.inspect',{occasionId:7,formId:42})).ok,false,JSON.stringify(invalid));
 }
});

test('form inspect accepts the canonical no_privacy_policy measurement block',async()=>{
 const measurement_status={requested_enabled:true,organization_allowed:true,organization_enabled:true,unit_enabled:true,
  runtime_supported:true,eligible:false,blocked_reasons:['no_privacy_policy'],policy_revision:1,consent_required:true,enhanced_conversions_unavailable:false};
 const f=fixture({occasionId:7,authoring:{...state,form:{...state.form,measurement_status}}});
 const result=await f.ops.invoke('forms.inspect',{occasionId:7,formId:42});
 assert.equal(result.ok,true,JSON.stringify(result));
 assert.deepEqual(result.data.authoring.form.measurement_status.blocked_reasons,['no_privacy_policy']);
});
