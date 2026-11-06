import test from 'node:test';
import assert from 'node:assert/strict';
import {Operations} from '../src/operations/catalog.mjs';
import {invokeFormOperation} from '../src/operations/forms.mjs';
function fixture(data){let calls=0;const owner={root:'/tmp/form-boundary',profile:{name:'fixture',organizationId:3,tenantId:'fixture'},allowedOperations:['forms.inspect','forms.list','forms.save','forms.paymentOptions'],delegatedContext:async()=>({organizationId:3,unitId:8}),authorized:fn=>fn({rpc:async()=>{calls++;return{data,error:null};}},{userId:'00000000-0000-4000-8000-000000000001'})};return{ops:new Operations(owner),calls:()=>calls};}
const state={form:{id:42,occasion:7,aggregate_version:0},fields:[],products:[],productTypes:[],productVersions:{},productTypeVersions:{}};
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
 for(const settings of [{unknown:true},{analytics:{gtm_container:'GTM-AB12'}},{analytics:{scripts:'<script>old form configuration</script>'}},{analytics:{enhanced_conversions:true}},{schedule:{sale_preparation:false}},{schedule:{start_time:'2030-01-01T00:00:00'}},{design:{background_mode:'pattern'}},{payments:{account_id:'acct_fake'}},{variable_symbol:{starting_number:10000000000}}]){
  const result=await f.ops.invoke('forms.save',{occasionId:7,commandId:'00000000-0000-4000-8000-000000000099',form:{id:42,expected_aggregate_version:0,expected_product_versions:{},expected_product_type_versions:{},settings}});assert.equal(result.error.code,'INVALID_INPUT',JSON.stringify(result));
 }assert.equal(f.calls(),0);
});

test('payment selection output rejects unexpected credentials in bank or Stripe projection',async()=>{
 const value={occasionId:7,formId:42,livemode:true,bankAccounts:[],stripeRecipient:null,availability:{configured:{bank:true,stripe:false},available:['bank'],stripeUnavailableReason:'not_configured',reservationSeconds:1860,supportedSurfaces:[],recipient:null}};
 assert.equal((await fixture(value).ops.invoke('forms.paymentOptions',{occasionId:7,formId:42,livemode:true})).ok,true);
 for(const extra of [{bankAccounts:[{id:1,account_number:null,account_number_human_readable:null,title:null,supported_currencies:null,type:null,bank_sync_warning:null,secret:'unexpected-credential'}]},{stripeRecipient:{connectionId:'00000000-0000-4000-8000-000000000099',name:null,state:'connected',paused:false,modelVerified:true,chargesEnabled:true,payoutsEnabled:false,cardPaymentsActive:true,checkedAt:null,unsupportedReason:null,account_id:'unexpected-credential'}}]){
  const result=await fixture({...value,...extra}).ops.invoke('forms.paymentOptions',{occasionId:7,formId:42,livemode:true});assert.equal(result.ok,false);assert(!JSON.stringify(result).includes('unexpected-credential'));
 }
});

const measurementStatus={requested_enabled:false,organization_allowed:false,organization_enabled:false,unit_enabled:false,
 runtime_supported:true,eligible:false,blocked_reasons:['disabled'],policy_revision:1,
 consent_required:true,enhanced_conversions_unavailable:true};
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
