import test from 'node:test';
import assert from 'node:assert/strict';
import {configurationDescriptors,invokeConfigurationOperation} from '../src/operations/configuration.mjs';
import {scopesForOperation} from '../../../packages/festapp_contracts/mcp-permissions.mjs';
import {OperationError,safeError} from '../src/errors.mjs';
import {setup,connect,apiRequest} from './api-fixture.mjs';
import {reply} from './fixture.mjs';
function fixture({canManage=true,current=10,enabled=true,unitAllowed=true}={}){
 const calls=[];
 const owner={delegatedUnitContext:async(_client,unitId)=>{assert.equal(unitId,7);return{unitId:7,organizationId:4};}};
 const snapshot=()=>({enabled,occasion_id:current,occasion_title:'Unconsented other organizer title',can_manage:canManage});
 const client={rpc:async(name,args)=>{
  calls.push({name,args});
  if(name==='get_operator_access_v1')return{data:{units:unitAllowed?[{id:7,title:'Organizer',canCreateOccasions:false}]:[],occasions:[]}};
  if(name==='get_unit_app_landing')return{data:snapshot()};
  assert.equal(name,'set_unit_app_landing');
  assert.deepEqual(args,{p_unit:7,p_occasion:null,p_expected_occasion:current});
  current=null;return{data:snapshot()};
 }};
 return{calls,owner,client,run:(op='save',args={})=>invokeConfigurationOperation(owner,client,`units.appLanding.${op}`,{unitId:7,occasionId:null,expectedOccasionId:10,...args})};
}
test('app landing declares explicit scope dependencies, nullable CAS inputs and truthful state idempotence',()=>{
 assert.deepEqual(scopesForOperation('units.appLanding.inspect'),['festapp:ticket-layouts:read','festapp:unit-settings:read']);
 assert.deepEqual(scopesForOperation('units.appLanding.save'),['festapp:ticket-layouts:read','festapp:unit-settings:read','festapp:unit-settings:write']);
 const d=configurationDescriptors.find(d=>d.id==='units.appLanding.save');
 assert.equal(d.idempotent,true);assert.match(d.description,/not a durable command receipt/);
 for(const args of [{unitId:7,occasionId:8},{unitId:7,expectedOccasionId:null},{unitId:7,occasionId:0,expectedOccasionId:null},{unitId:7,occasionId:8,expectedOccasionId:null,commandId:'invented'}])assert.equal(d.input.safeParse(args).success,false);
 assert.equal(d.input.safeParse({unitId:7,occasionId:null,expectedOccasionId:10}).success,true);
});
test('app landing binds whole-unit and tenant access before reading and omits foreign title',async()=>{
 const f=fixture();assert.deepEqual(await f.run('inspect'),{unitId:7,organizationId:4,enabled:true,occasionId:10,canManage:true});
 assert.deepEqual(f.calls[0],{name:'get_operator_access_v1',args:{p_organization:4,p_unit:7,p_occasion:null}});
 const foreign=fixture({unitAllowed:false});await assert.rejects(foreign.run('inspect'),{code:'FORBIDDEN'});assert.equal(foreign.calls.length,1);
 const denied=fixture();denied.owner.delegatedUnitContext=async()=>{throw new OperationError('ORGANIZER_CONSENT_REQUIRED');};await assert.rejects(denied.run(),{code:'ORGANIZER_CONSENT_REQUIRED'});assert.equal(denied.calls.length,0);
});
test('app landing clear and identical retry revalidate through native setter without a receipt',async()=>{
 const f=fixture();assert.equal((await f.run()).status,'applied');assert.equal((await f.run()).status,'unchanged');
 assert.equal(f.calls.filter(c=>c.name==='set_unit_app_landing').length,2);
});
test('already-target never bypasses revoked admin or disabled application',async()=>{
 for(const [setup,code] of [[{current:null,canManage:false},'FORBIDDEN'],[{current:null,enabled:false},'APP_LANDING_REJECTED']]){
  const f=fixture(setup);await assert.rejects(f.run(),{code});assert(!f.calls.some(c=>c.name==='set_unit_app_landing'));
 }
});
test('CAS conflicts and native target rejection are non-retryable reload/rejection errors',async()=>{
 const stale=fixture({current:11});await assert.rejects(stale.run(),{code:'APP_LANDING_CHANGED_RELOAD_REQUIRED',retryable:false});assert(!stale.calls.some(c=>c.name==='set_unit_app_landing'));
 for(const [sql,code] of [['40001','APP_LANDING_CHANGED_RELOAD_REQUIRED'],['22023','APP_LANDING_REJECTED'],['42501','FORBIDDEN']]){
  const f=fixture(),rpc=f.client.rpc;f.client.rpc=async(name,args)=>name==='set_unit_app_landing'?{error:{code:sql}}:rpc(name,args);
  await assert.rejects(f.run(),error=>{assert.equal(error.code,code);assert.equal(safeError(error).retryable,false);return true;});
 }
});
test('response loss is recovered only by current state readback and native revalidation',async()=>{
 const f=fixture(),rpc=f.client.rpc;let lost=false;
 f.client.rpc=async(name,args)=>{const result=await rpc(name,args);if(name==='set_unit_app_landing'&&!lost){lost=true;return{error:{status:503}};}return result;};
 await assert.rejects(f.run(),{code:'UNAVAILABLE',retryable:true});assert.equal((await f.run()).status,'unchanged');
});

test('canonical HTTP API exposes landing operations with OAuth scopes, whole-unit grant and CAS errors',async t=>{
 let current=7,canManage=true,writes=0;
 const f=await setup(t,{apiPolicy:{allowedScopes:['festapp:ticket-layouts:read','festapp:unit-settings:read','festapp:unit-settings:write'],allowedOperations:['units.appLanding.inspect','units.appLanding.save']},fetchImpl:async(url,init)=>{
  const name=url.pathname.split('/').at(-1);
  if(!['get_unit_app_landing','set_unit_app_landing'].includes(name))return;
  if(name==='set_unit_app_landing'){
   const args=JSON.parse(init.body);writes++;
   if(!canManage)return reply({code:'42501'},403);
   if(args.p_expected_occasion!==current)return reply({code:'40001'},400);
   current=args.p_occasion;
  }
  return reply({enabled:true,occasion_id:current,occasion_title:'Private title',can_manage:canManage});
 }});
 const scope='festapp:ticket-layouts:read festapp:unit-settings:read festapp:unit-settings:write';
 const {tokens}=await connect(f,{unitId:3,scope});
 let response=await apiRequest(f,tokens,'units.appLanding.inspect',{unitId:3});assert.equal(response.status,200,await response.clone().text());assert.equal((await response.json()).data.occasionId,7);
 const args={unitId:3,occasionId:null,expectedOccasionId:7};
 response=await apiRequest(f,tokens,'units.appLanding.save',args);assert.equal(response.status,200,await response.clone().text());assert.equal((await response.json()).data.status,'applied');
 response=await apiRequest(f,tokens,'units.appLanding.save',args);assert.equal(response.status,200);assert.equal((await response.json()).data.status,'unchanged');
 response=await apiRequest(f,tokens,'units.appLanding.save',{unitId:3,occasionId:8,expectedOccasionId:7});assert.equal(response.status,409);assert.equal((await response.json()).code,'APP_LANDING_CHANGED_RELOAD_REQUIRED');
 canManage=false;response=await apiRequest(f,tokens,'units.appLanding.save',args);assert.equal(response.status,403);assert.equal(writes,2);
 canManage=true;
 const read=await connect(f,{unitId:3,scope:'festapp:ticket-layouts:read festapp:unit-settings:read'});
 response=await apiRequest(f,read.tokens,'units.appLanding.save',args);assert.equal(response.status,403);assert.equal(writes,2);
 const eventOnly=await connect(f,{occasionIds:[7],scope});
 response=await apiRequest(f,eventOnly.tokens,'units.appLanding.inspect',{unitId:3});assert.equal(response.status,403);assert.equal(writes,2);
});
