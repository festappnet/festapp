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
 const value={occasionId:7,formId:42,livemode:true,paymentMethodPolicy:{organizationId:3,unitId:8,revision:1,preferredMethod:'bank',methods:{bank:{id:'bank',supported:true,policyEnabled:true,revision:'1:0',organizationEnabled:true,mode:'inherit',inheritedFrom:'organization',reason:null}}},bankAccounts:[],stripeRecipient:null,providerEditorFields:{stripe:{stripeRecipient:null},barion:{}},policy,
  availability:{bank:{configured:true,available:true},providers:{stripe:provider,barion:{...provider,providerId:'barion',reason:{code:'sandbox_only'}}},policy,
   configured:{bank:true,stripe:false},available:['bank'],stripeUnavailableReason:'not_configured',reservationSeconds:1860,supportedSurfaces:[],recipient:null}};
 assert.equal((await fixture(value).ops.invoke('forms.paymentOptions',{occasionId:7,formId:42,livemode:true})).ok,true);
 for(const extra of [{paymentMethodPolicy:undefined},{paymentMethodPolicy:{...value.paymentMethodPolicy,unitId:99}},{paymentMethodPolicy:{...value.paymentMethodPolicy,methods:{bank:{...value.paymentMethodPolicy.methods.bank,policyEnabled:false}}}},{bankAccounts:[{id:1,account_number:null,account_number_human_readable:null,title:null,supported_currencies:null,type:null,bank_sync_warning:null,secret:'unexpected-credential'}]},{stripeRecipient:{connectionId:'00000000-0000-4000-8000-000000000099',name:null,state:'connected',paused:false,modelVerified:true,chargesEnabled:true,payoutsEnabled:false,cardPaymentsActive:true,checkedAt:null,unsupportedReason:null,account_id:'unexpected-credential'}},
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

test('organizer consent bridge configuration accepts only explicit booleans and preserves omission', async () => {
 const {configurationDescriptors,configurationDataSchemas} = await import('../src/operations/configuration.mjs');
 const input = configurationDescriptors.find(d => d.id === 'units.settings.save').input;
 const args = {unitId:8,commandId:'00000000-0000-4000-8000-000000000099',expectedVersion:0};
 for (const value of [true,false]) {
  assert.equal(input.parse({...args,changes:{settings:{measurement_consent_bridge:value}}}).changes.settings.measurement_consent_bridge,value);
  assert.equal(configurationDataSchemas['units.settings.inspect'].parse({entityType:'unit',entityId:8,aggregateVersion:0,title:'Pořadatel',settings:{measurement_consent_bridge:value}}).settings.measurement_consent_bridge,value);
 }
 assert.deepEqual(input.parse({...args,changes:{settings:{}}}).changes.settings,{});
 for (const value of [null,'true',1]) assert.equal(input.safeParse({...args,changes:{settings:{measurement_consent_bridge:value}}}).success,false);
});

test('inspect projects future snapshot/envelope keys but validates known values',async()=>{
 const f=fixture({occasionId:7,private_extra:'do-not-return',authoring:{...state,private_extra:'do-not-return'}});
 const result=await f.ops.invoke('forms.inspect',{occasionId:7,formId:42});
 assert.equal(result.ok,true);assert(!JSON.stringify(result).includes('do-not-return'));
 const invalid=fixture({occasionId:7,authoring:{...state,products:'private-invalid-value'}});
 const lines=[],original=console.error;console.error=line=>lines.push(line);
 try{
  assert.equal((await invalid.ops.invoke('forms.inspect',{occasionId:7,formId:42})).ok,false);
  assert.equal((await f.ops.invoke('forms.inspect',{occasionId:7,formId:43})).ok,false);
 }
 finally{console.error=original;}
 assert(lines.map(JSON.parse).some(entry=>entry.issues?.some(issue=>issue.path==='authoring.products'&&issue.code==='invalid_type')));
 assert(lines.map(JSON.parse).some(entry=>entry.phase==='identity'));
 assert(!lines.join('').includes('private-invalid-value'));
});

const commandId='00000000-0000-4000-8000-000000000099';
const writeArgs=operation=>({occasionId:7,commandId,...(operation==='forms.save'?{form:{id:42,expected_aggregate_version:0,expected_product_versions:{},expected_product_type_versions:{}}}
 :operation==='forms.duplicate'?{sourceOccasionId:7,sourceFormId:42,locale:'en'}:operation==='forms.delete'?{formId:42,expectedVersion:0}
 :operation==='forms.setPublicLink'?{formId:42,expectedVersion:0,slug:'evening'}:{title:'Evening'})});
// The fake SQL owner replays the same committed receipt for the same command, like client_mutation_receipts.
function writeFixture(operation,write,read){
 const calls=[];
 const owner={root:'/tmp/form-boundary',profile:{name:'fixture',organizationId:3,tenantId:'fixture'},allowedOperations:[operation],
  delegatedContext:async()=>({organizationId:3,unitId:8}),authorized:fn=>fn({rpc:async(name,params)=>{
   calls.push(name);
   if(name==='manage_form')return{error:null,data:write(params)};
   return read();
  }},{})};
 return{ops:new Operations(owner),calls};
}
const committed=(data,status='applied')=>({code:200,status,mutation:{commandId,receiptId:commandId},data});

test('committed form writes retain command identity when readback fails; replay returns the same outcome from SQL',async()=>{
 for(const operation of ['forms.create','forms.save','forms.duplicate','forms.delete'])for(const failure of ['network','invalid','snapshot']){
  if(operation==='forms.delete'&&failure!=='snapshot')continue;
  let replay=false;
  // forms.delete has no follow-up read; its readback failure is an invalid receipt.
  const authoring=operation==='forms.delete'?{...state}:failure==='snapshot'?{...state,products:false}:state;
  const f=writeFixture(operation,()=>committed({occasionId:7,formId:42,authoring},replay?'unchanged':'applied'),()=>{
   if(failure==='network')throw new Error('PRIVATE server failure');
   return{error:null,data:{occasionId:7,authoring:{...state,form:{...state.form,measurement_status:{private:'secret'}}}}};
  });
  const args=writeArgs(operation);
  const first=await f.ops.invoke(operation,args);replay=true;
  const second=await f.ops.invoke(operation,args);
  assert.equal(first.error?.code,'COMMITTED_READBACK_FAILED',JSON.stringify(first));
  assert.equal(first.error.retryable,false);assert.match(first.error.message,new RegExp(commandId));
  assert.deepEqual(second.error,first.error);assert(!JSON.stringify(first).includes('PRIVATE'));
  assert.equal(f.calls.filter(name=>name==='manage_form').length,2,'replay is admitted by SQL again');
  assert(f.ops.catalog.find(d=>d.id===operation).output.safeParse(first).success);
 }
});

test('replay after a committed readback failure reports SQL conflict, expiry or the recovered result',async()=>{
 for(const [reply,expected] of [[{code:409,status:'conflict'},'FORM_CHANGED_RELOAD_REQUIRED'],[{code:410,status:'expired'},'COMMAND_EXPIRED_DO_NOT_REPLAY'],[null,null]]){
  let replay=false;
  const f=writeFixture('forms.create',()=>replay&&reply?reply:committed({occasionId:7,formId:42,authoring:state},replay?'unchanged':'applied'),
   ()=>replay?{error:null,data:{occasionId:7,authoring:state}}:{error:{message:'PRIVATE readback failure'},data:null});
  const args=writeArgs('forms.create');
  assert.equal((await f.ops.invoke('forms.create',args)).error.code,'COMMITTED_READBACK_FAILED');
  replay=true;
  const second=await f.ops.invoke('forms.create',args);
  if(expected)assert.equal(second.error?.code,expected,JSON.stringify(second));
  else{assert.equal(second.ok,true,JSON.stringify(second));assert.equal(second.data.status,'unchanged');assert.equal(second.data.formId,42);}
 }
});

test('form write receipts and public links project away unknown upstream keys before strict validation',async()=>{
 for(const operation of ['forms.create','forms.save','forms.duplicate','forms.delete','forms.setPublicLink']){
  const authoring=operation==='forms.delete'?null:{...state,private_extra:'do-not-return'};
  const f=writeFixture(operation,()=>operation==='forms.setPublicLink'
   ?{code:200,status:'applied',mutation:{commandId,receiptId:commandId},publicLink:{occasionId:7,formId:42,slug:'evening',private_extra:'do-not-return'}}
   :committed({occasionId:7,formId:42,authoring,private_extra:'do-not-return'}),
   ()=>({error:null,data:{occasionId:7,authoring:state}}));
  const result=await f.ops.invoke(operation,writeArgs(operation));
  assert.equal(result.ok,true,operation+' '+JSON.stringify(result));
  assert(!JSON.stringify(result).includes('do-not-return'),operation);
  assert.equal(result.data.commandId,commandId);
 }
 const link=fixture({occasionId:7,formId:42,slug:'evening',private_extra:'do-not-return'});
 const owner=link.ops.owner;owner.allowedOperations.push('forms.publicLink');
 const read=await link.ops.invoke('forms.publicLink',{occasionId:7,formId:42});
 assert.equal(read.ok,true,JSON.stringify(read));assert.equal(read.data.publicPath,'/form/evening');assert(!JSON.stringify(read).includes('do-not-return'));
});

test('setPublicLink: readback failure after commit, and SQL conflict or expiry on replay',async()=>{
 const link=(extra={})=>({code:200,status:'applied',mutation:{commandId,receiptId:commandId},publicLink:{occasionId:7,formId:42,slug:'evening',...extra}});
 const broken=writeFixture('forms.setPublicLink',()=>link({slug:null}),()=>{throw new Error('unexpected read');});
 const first=await broken.ops.invoke('forms.setPublicLink',writeArgs('forms.setPublicLink'));
 assert.equal(first.error?.code,'COMMITTED_READBACK_FAILED',JSON.stringify(first));assert.match(first.error.message,new RegExp(commandId));
 for(const [reply,expected] of [[{code:409},'FORM_CHANGED_RELOAD_REQUIRED'],[{code:410,mutation:{expired:true}},'COMMAND_EXPIRED_DO_NOT_REPLAY'],[{code:422,status:'rejected'},'FORM_CHANGE_REJECTED']]){
  const f=writeFixture('forms.setPublicLink',()=>reply,()=>{throw new Error('unexpected read');});
  assert.equal((await f.ops.invoke('forms.setPublicLink',writeArgs('forms.setPublicLink'))).error?.code,expected);
 }
});
