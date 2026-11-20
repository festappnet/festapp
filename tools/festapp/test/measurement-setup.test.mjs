import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Client,InMemoryTransport} from '@modelcontextprotocol/client';
import {Operations} from '../src/operations/catalog.mjs';
import {createServer} from '../src/mcp/server.mjs';
import {publicCatalog,readiness} from '../src/remote/api-contract.mjs';
import {measurementSetupDescriptors,approvalRequestError} from '../src/operations/measurement-setup.mjs';
import {configurationDescriptors} from '../src/operations/configuration.mjs';
import {formDescriptors} from '../src/operations/forms.mjs';
import {formEmbedCode,parseFormConsentExport,embedLabels,EMBED_LANGUAGES} from '../src/operations/form-embed.mjs';
import {scopesForOperation,DELEGATED_OPERATIONS,MCP_PERMISSIONS} from '../../../packages/festapp_contracts/mcp-permissions.mjs';
import {operationAuthentication} from '../src/auth/operation-policy.mjs';
import {safeError} from '../src/errors.mjs';
import {setup,connect,apiRequest} from './api-fixture.mjs';
import {reply} from './fixture.mjs';

const root=new URL('../../../',import.meta.url);
const UNIT=3,ORG=1,BINDING='11111111-1111-4111-8111-111111111111',OTHER='22222222-2222-4222-8222-222222222222';
const SITE='https://www.example.com',SERVICE='https://tickets.example.com',REVISION='0123456789abcdef0123456789abcdef';
const READ=['festapp:ticket-layouts:read','festapp:unit-settings:read'];
const exportFor=(changes={})=>({schemaVersion:1,serviceOrigin:SERVICE,websiteOrigin:SITE,binding:{id:BINDING,version:2},
 providerConfig:{provider:'cookiebot',consentValidFrom:'2026-11-13T12:00:00.000Z',maxAgeSeconds:31536000,organization:ORG,unit:UNIT,consentRevision:REVISION,origin:SITE},...changes});
const bindings=(overrides={})=>({organization:ORG,unit:UNIT,consentRevision:REVISION,saved_origins:[SITE],internalFuture:{x:1},
 bindings:[{id:BINDING,websiteOrigin:SITE,platform:'wordpress',providerConfig:{provider:'complianz',policyId:'42'},version:2,confirmedRevision:REVISION,state:'ready',internalFuture:true}],...overrides});

function fixture(handlers={},{allowed=true,manage=true,activationUrl=SERVICE+'/backend-activation.json',ops=[],allowedOperations}={}){
 handlers={can_manage_unit_configuration:args=>{assert.deepEqual(args,{p_unit:UNIT});return{data:manage};},...handlers};
 const calls=[];
 const owner={root:'/tmp/measurement-setup',profile:{name:'fixture',organizationId:ORG,tenantId:'fixture',activationUrl},
  allowedOperations:allowedOperations??[...measurementSetupDescriptors.map(d=>d.id),'forms.embedCode',...ops],
  delegatedUnitContext:async(_client,unitId)=>{assert.equal(unitId,UNIT);return{organizationId:ORG,unitId};},
  delegatedContext:async()=>({organizationId:ORG,unitId:UNIT}),
  authorized:fn=>fn({functions:{invoke:async(name,{body})=>{
   calls.push({name,args:body});
   assert(handlers[name],'unexpected Edge function '+name);
   return handlers[name](body);
  }},rpc:async(name,args)=>{
   calls.push({name,args});
   if(name==='get_operator_access_v1')return{data:{units:allowed?[{id:UNIT,title:'Organizer',canCreateOccasions:false}]:[],occasions:[]}};
   const handler=handlers[name];
   assert(handler,'unexpected RPC '+name);
   return handler(args);
  }},{userId:'00000000-0000-4000-8000-000000000001'})};
 return{calls,ops:new Operations(owner),names:()=>calls.map(c=>c.name)};
}

test('new setup operations use organizer settings scopes, delegated access and no sensitive authentication',()=>{
 const reads=['units.websiteConsent.inspect','units.websiteConsent.export','units.measurementApproval.inspect','units.metaCapiApproval.inspect'];
 const writes=['units.measurementApproval.request','units.metaCapiApproval.request'];
 for(const id of reads)assert.deepEqual(scopesForOperation(id),READ);
 for(const id of writes)assert.deepEqual(scopesForOperation(id),[...READ,'festapp:unit-approvals:request']);
 // Approval emails reach every organization administrator: existing settings grants never include them.
 assert(!MCP_PERMISSIONS['festapp:unit-settings:write'].operations.some(id=>writes.includes(id)));
 const label=MCP_PERMISSIONS['festapp:unit-approvals:request'].label;
 for(const language of EMBED_LANGUAGES){
  const text=JSON.parse(readFileSync(new URL(`assets/translations/${language}.json`,root),'utf8')).McpConnection[label];
  assert(typeof text==='string'&&/Meta CAPI/.test(text),language);
 }
 assert.deepEqual(scopesForOperation('forms.embedCode'),['festapp:ticket-layouts:read','festapp:forms:read','festapp:forms:write']);
 for(const id of [...reads,...writes,'forms.embedCode']){
  assert(DELEGATED_OPERATIONS.includes(id));assert.equal(operationAuthentication(id),null);
  const descriptor=new Operations({profile:{},allowedOperations:[id]}).catalog.find(d=>d.id===id);
  assert(descriptor?.requiresDelegatedAccess,id);assert.equal(descriptor.domainReadOnly,!writes.includes(id),id);
 }
 for(const id of writes){
  const d=measurementSetupDescriptors.find(d=>d.id===id);
  assert.match(d.description,/Approve the exact change first/);assert.match(d.description,/every administrator of the organization/);
  assert.equal(d.destructive,false);assert.equal(d.idempotent,false);
  assert.equal(d.input.safeParse({unitId:UNIT,commandId:BINDING}).success,false);
 }
 assert.match(measurementSetupDescriptors.find(d=>d.id==='units.metaCapiApproval.inspect').description,/whole organization/);
});

test('MCP and the HTTP contract direct uncertain approval requests to inspection without replay',async t=>{
 const timeout=()=>{throw new DOMException('Fixture timeout','TimeoutError');};
 const f=fixture({request_unit_measurement_approval:timeout,request_unit_meta_capi_approval:timeout});
 const server=createServer(f.ops),sdk=new Client({name:'approval-recovery-fixture',version:'1'});
 const [serverTransport,clientTransport]=InMemoryTransport.createLinkedPair();
 await server.connect(serverTransport);
 await sdk.connect(clientTransport);
 t.after(async()=>{await sdk.close();await server.close();});
 const {tools}=await sdk.listTools();
 for(const kind of ['measurement','meta_capi']){
  const name=`festapp_units_${kind}_approval_request`;
  const inspect=`festapp_units_${kind}_approval_inspect`;
  const tool=tools.find(tool=>tool.name===name);
  assert.equal(tool.annotations.idempotentHint,false);
  assert(tool.description.includes(inspect));
  assert.match(tool.description,/wait while requestState is requested/);
  assert.match(tool.description,/retry_available.*Obtain fresh approval/);
  const result=await sdk.callTool({name,arguments:{unitId:UNIT}});
  assert.equal(result.isError,true);
  assert.equal(result.structuredContent.error.code,'TIMEOUT');
  assert.equal(result.structuredContent.error.retryable,false);
  assert(result.structuredContent.error.message.includes(inspect));
  const descriptor=publicCatalog().find(d=>d.name===name);
  const advice=readiness(descriptor).retry;
  assert(advice.includes(descriptor.id.replace(/\.request$/,'.inspect')));
  assert.match(advice,/wait while requestState is requested/);
  assert.match(advice,/retry_available.*Obtain fresh approval/);
  assert.match(advice,/rejected APPROVAL_REQUEST_LIMITED.*Follow Retry-After/);
 }
});

test('units.settings.save names exactly the stored keys and runtime columns that SQL hashes into consentRevision',()=>{
 const sql=readFileSync(new URL('database/functions/eshop_forms/form_measurement_policy.sql',root),'utf8');
 const owner=sql.slice(sql.indexOf('FUNCTION public.unit_measurement_consent_scope_internal'),sql.indexOf('REVOKE ALL ON FUNCTION public.unit_measurement_consent_scope_internal'));
 const hashed=[...new Set([...owner.matchAll(/u\.data->'(measurement_[a-z_]+)'/g)].map(m=>m[1]))].sort();
 const hash=owner.slice(owner.indexOf('md5('),owner.indexOf(' FROM '));
 const runtime=[...new Set([...hash.matchAll(/\br\.([a-z_]+)/g)].map(m=>m[1]))].sort();
 assert.deepEqual([...new Set([...hash.matchAll(/u\.data->'(measurement_[a-z_]+)'/g)].map(m=>m[1]))].sort(),hashed);
 assert.deepEqual(hashed,['measurement_consent_text','measurement_consent_title','measurement_consent_version','measurement_gtm_container','measurement_privacy_url','measurement_scripts']);
 assert.deepEqual(runtime,['collector_origins','runtime_profile']);
 assert.match(owner,/coalesce\(u\.data->'measurement_consent_version','1'::jsonb\)/);
 const description=configurationDescriptors.find(d=>d.id==='units.settings.save').description;
 const sentence=description.slice(description.indexOf('consentRevision hashes the stored'),description.indexOf('together with'));
 assert.deepEqual([...new Set(sentence.match(/measurement_[a-z_]+/g))].sort(),hashed);
 assert.match(description,/together with the platform-owned measurement runtime profile and collector origins/);
 assert.match(description,/explicit measurement_consent_version 1 where none is stored does not/);
 assert.match(description,/Every enabled website consent binding then becomes confirmation_required/);
 assert.match(description,/Platform approval that provisions or changes the measurement runtime has the same effect/);
 assert.match(description,/organizer’s explicit confirmation/);assert.match(description,/festapp_units_website_consent_save/);assert.match(description,/website_ready/);assert.match(description,/festapp_units_website_consent_inspect/);
 assert.doesNotMatch(description,/Other keys/);
 // Only enabled bindings move to confirmation_required.
 const bindingsSql=readFileSync(new URL('database/functions/eshop_forms/website_consent_bindings.sql',root),'utf8');
 assert.match(bindingsSql,/CASE WHEN NOT b\.enabled THEN CASE WHEN b\.confirmed_revision IS NULL THEN 'draft' ELSE 'disabled' END\s+WHEN b\.confirmed_revision IS DISTINCT FROM/);
 assert.match(measurementSetupDescriptors.find(d=>d.id==='units.measurementApproval.request').description,/every enabled website consent binding becomes confirmation_required/);
});

test('website consent inspect projects a narrow state and tolerates newer server fields and values',async()=>{
 const f=fixture({get_unit_website_consent_bindings:()=>({data:bindings({bindings:[...bindings().bindings,
  {id:OTHER,websiteOrigin:'https://shop.example.com',platform:'future-cms',providerConfig:{provider:'future-banner',secret:'never'},version:1,state:'paused'}]})})});
 const result=await f.ops.invoke('units.websiteConsent.inspect',{unitId:UNIT});
 assert.equal(result.ok,true,JSON.stringify(result));
 assert.deepEqual(result.data,{unitId:UNIT,organizationId:ORG,consentRevision:REVISION,savedOrigins:[SITE],bindings:[
  {id:BINDING,websiteOrigin:SITE,platform:'wordpress',provider:'complianz',version:2,state:'ready'},
  {id:OTHER,websiteOrigin:'https://shop.example.com',platform:'unknown',provider:'unknown',version:1,state:'unknown'}],truncated:false});
 assert(!/policyId|never|internalFuture|confirmedRevision/.test(JSON.stringify(result)));
 assert.deepEqual(f.names(),['get_operator_access_v1','get_unit_website_consent_bindings']);
});

test('website consent inspect keeps rows beyond the output limit from failing the read',async()=>{
 const stale=Array.from({length:150},(_,i)=>({id:`00000000-0000-4000-8000-${String(i).padStart(12,'0')}`,websiteOrigin:`https://old${String(i).padStart(3,'0')}.example.com`,platform:'html',providerConfig:{provider:'wix'},version:1,state:'unavailable'}));
 const current={...bindings().bindings[0],websiteOrigin:'https://zz.example.com'};
 const f=fixture({get_unit_website_consent_bindings:()=>({data:bindings({saved_origins:['https://zz.example.com'],bindings:[...stale,current]})})});
 const result=await f.ops.invoke('units.websiteConsent.inspect',{unitId:UNIT});
 assert.equal(result.ok,true,JSON.stringify(result.error));
 assert.equal(result.data.truncated,true);assert.equal(result.data.bindings.length,100);
 // The binding of a currently saved website is never cut off by stale rows.
 assert.equal(result.data.bindings[0].websiteOrigin,'https://zz.example.com');
 const many=fixture({get_unit_measurement_approval:()=>({data:{approved:false,runtime_supported:true,requested_at:null,approved_origins:Array.from({length:120},(_,i)=>`https://a${i}.example.com`),saved_origins:[],requested_origins:[],request_state:'not_requested',can_request:false}})});
 const approval=await many.ops.invoke('units.measurementApproval.inspect',{unitId:UNIT});
 assert.equal(approval.ok,true);assert.equal(approval.data.truncated,true);assert.equal(approval.data.approvedOrigins.length,100);
});

test('setup reads fail closed for a foreign organization, a unit outside live access and denied roles',async()=>{
 const foreign=fixture({get_unit_website_consent_bindings:()=>({data:bindings({organization:99})})});
 assert.equal((await foreign.ops.invoke('units.websiteConsent.inspect',{unitId:UNIT})).error.code,'UPSTREAM_CONTRACT_FAILURE');
 const outside=fixture({},{allowed:false});
 const result=await outside.ops.invoke('units.measurementApproval.inspect',{unitId:UNIT});
 assert.equal(result.error.code,'FORBIDDEN');assert.match(result.error.message,/organizer administration/);assert.deepEqual(outside.names(),['get_operator_access_v1']);
 const denied=fixture({get_unit_website_consent_bindings:()=>({error:{code:'42501',message:'private'}})});
 const error=(await denied.ops.invoke('units.websiteConsent.inspect',{unitId:UNIT})).error;
 assert.equal(error.code,'FORBIDDEN');assert.match(error.message,/manager role/);assert(!error.message.includes('private'));
});

test('website consent changes have their own grant and require original versions',async()=>{
 const ids=['units.websiteConsent.probeComplianz','units.websiteConsent.save','units.websiteConsent.disable'];
 for(const id of ids)assert.deepEqual(scopesForOperation(id),[...READ,'festapp:unit-website-consent:write']);
 for(const lang of EMBED_LANGUAGES){
  const catalog=JSON.parse(readFileSync(new URL(`assets/translations/${lang}.json`,root),'utf8'));
  assert(catalog.McpConnection.unitWebsiteConsentWrite,lang);
 }
 const save={unitId:UNIT,websiteOrigin:SITE,platform:'wordpress',providerConfig:{provider:'complianz',policyId:'42'},
  expectedVersion:2,expectedConsentRevision:REVISION,coverageConfirmed:true};
 const snapshot=()=>({data:bindings()});
 const saved={...bindings().bindings[0],version:3};
 const f=fixture({get_unit_website_consent_bindings:snapshot,
  save_unit_website_consent_binding:args=>{
   assert.deepEqual(args,{p_unit:UNIT,p_website_origin:SITE,p_platform:'wordpress',p_provider_config:save.providerConfig,
    p_expected_version:2,p_expected_consent_revision:REVISION,p_confirm:false});
   return {data:bindings({bindings:[{...saved,state:'draft'}]})};
  },
  disable_unit_website_consent_binding:args=>{
   assert.deepEqual(args,{p_binding:BINDING,p_expected_version:2});
   return {data:bindings({bindings:[{...saved,state:'disabled'}]})};
  },
  'probe-complianz':args=>{
   if(!args.confirm){assert.deepEqual(args,{unitId:UNIT,origin:SITE});return {data:{policyId:'42'}};}
   assert.deepEqual(args,{unitId:UNIT,origin:SITE,confirm:true,platform:'wordpress',expectedPolicyId:'42',version:2,revision:REVISION});
   return {data:bindings({bindings:[saved]})};
  }});
 const probed=await f.ops.invoke(ids[0],{unitId:UNIT,websiteOrigin:SITE});
 assert.deepEqual(probed.data,{unitId:UNIT,websiteOrigin:SITE,policyId:'42'});
 const draft=await f.ops.invoke(ids[1],{...save,coverageConfirmed:false});
 assert.equal(draft.data.bindings[0].state,'draft');assert.equal(draft.data.bindings[0].version,3);
 assert(!JSON.stringify(draft).includes('policyId'));
 const confirmed=await f.ops.invoke(ids[1],{...save,verifyComplianz:true});
 assert.equal(confirmed.data.bindings[0].state,'ready');assert.equal(confirmed.data.bindings[0].version,3);
 const disabled=await f.ops.invoke(ids[2],{unitId:UNIT,bindingId:BINDING,expectedVersion:2});
 assert.equal(disabled.data.bindings[0].state,'disabled');
 for(const [id,args,expected] of [
  [ids[0],{unitId:UNIT,websiteOrigin:'https://other.example.com'},'WEBSITE_CONSENT_CHANGE_REJECTED'],
  [ids[1],{...save,expectedVersion:1},'WEBSITE_CONSENT_CHANGED_RELOAD_REQUIRED'],
  [ids[1],{...save,expectedConsentRevision:'0'.repeat(32)},'WEBSITE_CONSENT_CHANGED_RELOAD_REQUIRED'],
  [ids[1],{...save,verifyComplianz:true,coverageConfirmed:false},'INVALID_INPUT'],
  [ids[2],{unitId:UNIT,bindingId:OTHER,expectedVersion:2},'NOT_FOUND_OR_INACCESSIBLE'],
 ]){
  const attempt=fixture({get_unit_website_consent_bindings:snapshot});
  assert.equal((await attempt.ops.invoke(id,args)).error.code,expected);
  assert(!attempt.names().some(name=>name==='probe-complianz'||/^(save|disable)_/.test(name)));
 }
 const conflict=fixture({get_unit_website_consent_bindings:snapshot,'probe-complianz':()=>({error:{context:{status:409}}})});
 const changed=await conflict.ops.invoke(ids[1],{...save,verifyComplianz:true});
 assert.equal(changed.error.code,'WEBSITE_CONSENT_CHANGED_RELOAD_REQUIRED');
 const timeout=fixture({get_unit_website_consent_bindings:snapshot,save_unit_website_consent_binding:()=>{throw new DOMException('Timeout','TimeoutError');}});
 const uncertain=await timeout.ops.invoke(ids[1],save);
 assert.equal(uncertain.error.retryable,false);assert.match(uncertain.error.message,/festapp_units_website_consent_inspect/);
});

test('form measurement details project current purchase timing and Meta CAPI state only',async()=>{
 const occasionId=5,formId=6;
 const status={requested_enabled:true,organization_allowed:true,organization_enabled:true,unit_enabled:true,
  runtime_supported:true,eligible:true,blocked_reasons:[],policy_revision:1,consent_required:true,enhanced_conversions_unavailable:false};
 const f=fixture({get_form_for_authoring:args=>{
  assert.deepEqual(args,{p_occasion:occasionId,p_organization:ORG,p_unit:UNIT,p_form:formId});
  return {data:{occasionId,authoring:{form:{id:formId,occasion:occasionId,
   measurement_status:{...status,purchase_timing:'paid',meta_purchase_enabled:true,unknownInternal:'private'}}}}};
 }},{ops:['forms.measurement.inspect']});
 const result=await f.ops.invoke('forms.measurement.inspect',{occasionId,formId});
 assert.deepEqual(result.data,{occasionId,formId,status,purchaseTiming:'paid',metaPurchaseEnabled:true});
 assert.deepEqual(scopesForOperation('forms.measurement.inspect'),['festapp:ticket-layouts:read','festapp:forms:read']);
});

test('consent export proves binding ownership, version and readiness before reading it',async()=>{
 const exported=exportFor();
 const ok=fixture({get_unit_website_consent_bindings:()=>({data:bindings({bindings:[{...bindings().bindings[0],providerConfig:{provider:'cookiebot'}}]})}),
  export_unit_website_consent_binding:args=>{assert.deepEqual(args,{p_binding:BINDING,p_expected_version:2});return{data:exported};}});
 const result=await ok.ops.invoke('units.websiteConsent.export',{unitId:UNIT,bindingId:BINDING,expectedVersion:2});
 assert.equal(result.ok,true,JSON.stringify(result));
 assert.deepEqual(JSON.parse(result.data.consentExport),exported);
 assert.deepEqual({...result.data,consentExport:undefined},{unitId:UNIT,bindingId:BINDING,bindingVersion:2,websiteOrigin:SITE,provider:'cookiebot',consentExport:undefined});
 for(const [args,state,code] of [[{bindingId:OTHER,expectedVersion:2},'ready','NOT_FOUND_OR_INACCESSIBLE'],[{bindingId:BINDING,expectedVersion:1},'ready','WEBSITE_CONSENT_CHANGED_RELOAD_REQUIRED'],
  [{bindingId:BINDING,expectedVersion:2},'confirmation_required','WEBSITE_CONSENT_NOT_READY']]){
  const f=fixture({get_unit_website_consent_bindings:()=>({data:bindings({bindings:[{...bindings().bindings[0],state}]})})});
  const failed=await f.ops.invoke('units.websiteConsent.export',{unitId:UNIT,...args});
  assert.equal(failed.error.code,code);assert(!f.names().includes('export_unit_website_consent_binding'));
 }
 for(const [error,code] of [[{code:'40001',message:'website_consent_conflict'},'WEBSITE_CONSENT_CHANGED_RELOAD_REQUIRED'],[{code:'22023',message:'website_consent_not_ready'},'WEBSITE_CONSENT_NOT_READY'],
  [{code:'22023',message:'website_consent_service_origin_missing'},'WEBSITE_CONSENT_REJECTED']]){
  const f=fixture({get_unit_website_consent_bindings:()=>({data:bindings()}),export_unit_website_consent_binding:()=>({error})});
  const failed=await f.ops.invoke('units.websiteConsent.export',{unitId:UNIT,bindingId:BINDING,expectedVersion:2});
  assert.equal(failed.error.code,code);assert.equal(failed.error.retryable,false);
 }
 const providerConfig=exportFor().providerConfig;
 for(const data of [exportFor({providerConfig:{...providerConfig,unit:4}}),exportFor({binding:{id:OTHER,version:2}}),exportFor({providerConfig:{...providerConfig,origin:'https://other.example.com'}})]){
  const f=fixture({get_unit_website_consent_bindings:()=>({data:bindings()}),export_unit_website_consent_binding:()=>({data})});
  assert.equal((await f.ops.invoke('units.websiteConsent.export',{unitId:UNIT,bindingId:BINDING,expectedVersion:2})).error.code,'UPSTREAM_CONTRACT_FAILURE');
 }
});

test('approval reads omit organization policy, keep new fields out and never offer an unknown request state',async()=>{
 const measurement={approved:false,organization_allowed:true,runtime_supported:true,requested_at:'2026-11-20T10:11:12.123456+00:00',approved_origins:[SERVICE],
  saved_origins:[SITE],requested_origins:[SITE],request_state:'retry_available',can_request:true,future_internal:'x'};
 const f=fixture({get_unit_measurement_approval:()=>({data:measurement}),get_unit_meta_capi_approval:()=>({data:{approved:false,requested_at:null,request_state:'not_requested',can_request:true,future:1}})});
 let result=await f.ops.invoke('units.measurementApproval.inspect',{unitId:UNIT});
 assert.equal(result.ok,true,JSON.stringify(result));
 assert.deepEqual(result.data,{unitId:UNIT,approved:false,runtimeSupported:true,requestState:'retry_available',canRequest:true,requestedAt:measurement.requested_at,approvedOrigins:[SERVICE],savedOrigins:[SITE],requestedOrigins:[SITE],truncated:false});
 assert(!/organization_allowed|organizationAllowed|future/.test(JSON.stringify(result)));
 result=await f.ops.invoke('units.metaCapiApproval.inspect',{unitId:UNIT});
 assert.deepEqual(result.data,{unitId:UNIT,organizationId:ORG,approved:false,requestState:'not_requested',canRequest:true,requestedAt:null});
 const future=fixture({get_unit_meta_capi_approval:()=>({data:{approved:false,requested_at:null,request_state:'escalated',can_request:true}})});
 result=await future.ops.invoke('units.metaCapiApproval.inspect',{unitId:UNIT});
 assert.equal(result.data.requestState,'unavailable');assert.equal(result.data.canRequest,false);
 const active=fixture({get_unit_measurement_approval:()=>({data:{...measurement,request_state:'requested',can_request:true}})});
 assert.equal((await active.ops.invoke('units.measurementApproval.inspect',{unitId:UNIT})).data.canRequest,false);
});

test('canRequest follows the live manager check and the connection scopes, not the SQL flag alone',async()=>{
 const measurement={approved:false,runtime_supported:true,requested_at:null,approved_origins:[],saved_origins:[SITE],requested_origins:[],request_state:'not_requested',can_request:true};
 // get_unit_measurement_approval returns can_request:true to administration readers too.
 const reader=fixture({get_unit_measurement_approval:()=>({data:measurement})},{manage:false});
 assert.equal((await reader.ops.invoke('units.measurementApproval.inspect',{unitId:UNIT})).data.canRequest,false);
 assert(reader.names().includes('can_manage_unit_configuration'));
 const withoutScope=fixture({get_unit_measurement_approval:()=>({data:measurement})},{allowedOperations:['units.measurementApproval.inspect']});
 assert.equal((await withoutScope.ops.invoke('units.measurementApproval.inspect',{unitId:UNIT})).data.canRequest,false);
 assert(!withoutScope.names().includes('can_manage_unit_configuration'));
 const manager=fixture({get_unit_measurement_approval:()=>({data:measurement})});
 assert.equal((await manager.ops.invoke('units.measurementApproval.inspect',{unitId:UNIT})).data.canRequest,true);
 const denied=fixture({get_unit_measurement_approval:()=>({data:measurement}),can_manage_unit_configuration:()=>({error:{code:'42501',message:'x'}})});
 assert.equal((await denied.ops.invoke('units.measurementApproval.inspect',{unitId:UNIT})).error.code,'FORBIDDEN');
});

test('approval requests return the request owner status and map undelivered outcomes explicitly',async()=>{
 const status={approved:false,requested_at:'2026-11-20T10:11:12+00:00',request_state:'requested',can_request:false};
 const f=fixture({request_unit_meta_capi_approval:args=>{assert.deepEqual(args,{p_unit:UNIT});return{data:status};}});
 const result=await f.ops.invoke('units.metaCapiApproval.request',{unitId:UNIT});
 assert.equal(result.ok,true,JSON.stringify(result));assert.equal(result.data.requestState,'requested');
 for(const [rpc,message] of [['request_unit_measurement_approval','measurement_request_no_recipient'],['request_unit_meta_capi_approval','meta_capi_request_no_recipient']]){
  const op=rpc.includes('meta')?'units.metaCapiApproval.request':'units.measurementApproval.request';
  const failed=await fixture({[rpc]:()=>({error:{code:'P0001',message}})}).ops.invoke(op,{unitId:UNIT});
  assert.equal(failed.error.code,'APPROVAL_REQUEST_NO_RECIPIENT');assert.equal(failed.error.retryable,false);assert.match(failed.error.message,/Nothing was sent/);
 }
 for(const message of ['measurement_notification_origin_missing','meta_capi_notification_origin_missing'])
  assert.equal(approvalRequestError({code:'P0001',message}).code,'APPROVAL_REQUEST_REJECTED');
 assert.equal(approvalRequestError({code:'22023',message:'invalid'}).code,'APPROVAL_REQUEST_REJECTED');
 // Unlisted server text is never interpreted.
 assert.equal(approvalRequestError({code:'P0001',message:'measurement_request_no_recipient!'}),null);
 const other=await fixture({request_unit_measurement_approval:()=>({error:{code:'P0001',message:'other'}})}).ops.invoke('units.measurementApproval.request',{unitId:UNIT});
 assert.equal(other.error.code,'UNAVAILABLE');
});

test('email admission 429 becomes APPROVAL_REQUEST_LIMITED with the wait, not UNAVAILABLE',async()=>{
 const limit=(detail)=>({code:'PT429',message:'abuse_limit_exceeded',details:detail,hint:'Capacity is limited.'});
 let seconds;
 const f=fixture({request_unit_measurement_approval:()=>({error:limit(JSON.stringify({retryAfterSeconds:120,needsPolicyChange:false,ruleKey:'email.recipient'}))})});
 const result=await f.ops.invoke('units.measurementApproval.request',{unitId:UNIT},{onRetryAfter:value=>{seconds=value;}});
 assert.deepEqual({code:result.error.code,retryable:result.error.retryable},{code:'APPROVAL_REQUEST_LIMITED',retryable:true});
 assert.match(result.error.message,/retry after 120 seconds/);assert.equal(seconds,120);
 const hard=approvalRequestError(limit(JSON.stringify({retryAfterSeconds:null,needsPolicyChange:true})));
 assert.equal(hard.retryable,false);assert.equal(hard.retryAfter,undefined);assert.match(safeError(hard).message,/waiting does not resolve/);
 for(const detail of [null,'not json',JSON.stringify({retryAfterSeconds:-5}),JSON.stringify({retryAfterSeconds:1.5})])
  assert.equal(approvalRequestError(limit(detail)).retryAfter,60);
 assert.equal(approvalRequestError(limit(JSON.stringify({retryAfterSeconds:999999}))).retryAfter,86400);
});

test('embed generator matches the shared administration cases',()=>{
 const shared=JSON.parse(readFileSync(new URL('packages/festapp_contracts/form-embed-code-cases.json',root),'utf8'));
 assert(shared.cases.some(c=>c.error)&&shared.cases.some(c=>c.input.consentExport));
 for(const item of shared.cases){
  if('expected' in item)assert.equal(formEmbedCode(item.input),item.expected,item.name);
  else assert.throws(()=>formEmbedCode(item.input),error=>error.message===item.error,item.name);
 }
 for(const language of EMBED_LANGUAGES){
  const strings=JSON.parse(readFileSync(new URL(`assets/translations/${language}.json`,root),'utf8')).FeatureFormSettings;
  assert.deepEqual(embedLabels(language),{title:strings.embedTitle,fallbackLabel:strings.embedFallback});
 }
 // JSON.stringify would reorder integer-like keys or reformat numbers; such exports fail closed.
 for(const changes of [{providerConfig:{...exportFor().providerConfig,0:'x'}},{extra:1.5}])
  assert.equal(parseFormConsentExport(JSON.stringify(exportFor(changes)),SERVICE),null);
 assert.equal(parseFormConsentExport(JSON.stringify(exportFor()).replace('"schemaVersion":1','"schemaVersion":1,"extra":-0'),SERVICE),null);
 assert.deepEqual(parseFormConsentExport(JSON.stringify(exportFor()),SERVICE),exportFor());
});

test('forms.embedCode uses the saved slug, tenant web address and explicit language',async()=>{
 const link=slug=>({get_form_public_link:args=>{assert.deepEqual(args,{p_occasion:7,p_organization:ORG,p_unit:UNIT,p_form:42});return{data:{occasionId:7,formId:42,slug}};}});
 const f=fixture(link('summer-festival'));
 const args={occasionId:7,formId:42,language:'cs'};
 const result=await f.ops.invoke('forms.embedCode',args);
 assert.equal(result.ok,true,JSON.stringify(result));
 assert.equal(result.data.embedCode,formEmbedCode({tenantUrl:SERVICE,savedLink:'summer-festival',...embedLabels('cs')}));
 assert.equal(result.data.publicUrl,SERVICE+'/form/summer-festival');
 const fixed=await f.ops.invoke('forms.embedCode',{...args,height:'fixed',hostDataLayer:false,consentExport:JSON.stringify(exportFor())});
 assert.equal(fixed.data.embedCode,formEmbedCode({tenantUrl:SERVICE,savedLink:'summer-festival',...embedLabels('cs'),automatic:false,hostDataLayer:false,consentExport:JSON.stringify(exportFor())}));
 assert.match(fixed.data.embedCode,/data-festapp-height="fixed"/);assert.match(fixed.data.embedCode,/data-cookieconsent="ignore"/);assert.doesNotMatch(fixed.data.embedCode,/data-festapp-datalayer/);
 const before=f.calls.length;
 for(const invalid of [{occasionId:7,formId:42},{...args,language:'fr'},{...args,height:'auto'},{...args,consentExport:''}])assert.equal((await f.ops.invoke('forms.embedCode',invalid)).error.code,'INVALID_INPUT');
 assert.equal(f.calls.length,before);
 const altered=await f.ops.invoke('forms.embedCode',{...args,consentExport:JSON.stringify(exportFor({websiteOrigin:'https://other.example.com'}))});
 assert.equal(altered.error.code,'CONSENT_EXPORT_REJECTED');assert.match(altered.error.message,/selected organizer/);
 for(const identity of [{unit:UNIT+1},{organization:ORG+1}]){
  const foreign=JSON.stringify(exportFor({providerConfig:{...exportFor().providerConfig,...identity}}));
  assert.equal((await f.ops.invoke('forms.embedCode',{...args,consentExport:foreign})).error.code,'CONSENT_EXPORT_REJECTED');
 }
 for(const slug of ['',null])assert.equal((await fixture(link(slug)).ops.invoke('forms.embedCode',args)).error.code,'FORM_PUBLIC_LINK_REQUIRED');
 // A maximal export of characters that expand when escaped still fits the output contract.
 const base=JSON.stringify(exportFor({filler:''}));
 const huge=base.replace('"filler":""','"filler":"'+'&'.repeat(16384-base.length)+'"');
 assert.equal(huge.length,16384);
 const large=await f.ops.invoke('forms.embedCode',{...args,consentExport:huge});
 assert.equal(large.ok,true,JSON.stringify(large.error));assert(large.data.embedCode.length>65536);
 const mismatch=await f.ops.invoke('forms.embedCode',{...args,consentExport:JSON.stringify(exportFor({serviceOrigin:'https://other.example.com'}))});
 assert.equal(mismatch.error.code,'CONSENT_EXPORT_SERVICE_MISMATCH');assert.match(mismatch.error.message,/platform operator/);assert.equal(mismatch.error.retryable,false);
 const wrong=await fixture({get_form_public_link:()=>({data:{occasionId:7,formId:43,slug:'x'}})}).ops.invoke('forms.embedCode',args);
 assert.equal(wrong.error.code,'UPSTREAM_CONTRACT_FAILURE');
 assert(formDescriptors.find(d=>d.id==='forms.embedCode').description.includes('nothing is saved or published'));
});

test('embed labels load lazily, fail only the embed tool and ship in the image',()=>{
 assert.throws(()=>embedLabels('fr'),{code:'EMBED_LABELS_UNAVAILABLE'});
 const docker=readFileSync(new URL('tools/festapp/Dockerfile.remote',root),'utf8');
 for(const stage of docker.split(/^FROM /m).slice(1))assert.match(stage,/^COPY assets\/translations \.\/assets\/translations$/m);
});

test('HTTP API requires whole-organizer consent, the approval request scope and exposes Retry-After for limited requests',async t=>{
 let requests=0,requestError;
 const scopes=[...READ,'festapp:unit-approvals:request'];
 const f=await setup(t,{apiPolicy:{allowedScopes:[...scopes,'festapp:unit-settings:write','festapp:unit-website-consent:write'],allowedOperations:measurementSetupDescriptors.map(d=>d.id)},fetchImpl:async url=>{
  const name=url.pathname.split('/').at(-1);
  if(name==='can_manage_unit_configuration')return reply(true);
  if(name==='get_unit_measurement_approval')return reply({approved:false,runtime_supported:true,requested_at:null,approved_origins:[],saved_origins:[SITE],requested_origins:[],request_state:'not_requested',can_request:true});
  if(name!=='request_unit_measurement_approval')return;
  requests++;
  if(requestError==='limited')return reply({code:'PT429',message:'abuse_limit_exceeded',details:JSON.stringify({retryAfterSeconds:90,needsPolicyChange:false}),hint:null},429);
  if(requestError==='unavailable')return reply({code:'PGRST000',message:'Fixture unavailable',details:null,hint:null},503);
  return reply({approved:false,runtime_supported:true,requested_at:'2026-11-20T10:11:12+00:00',approved_origins:[],saved_origins:[SITE],requested_origins:[SITE],request_state:'requested',can_request:false});
 }});
 const {tokens}=await connect(f,{unitId:3,scope:scopes.join(' ')});
 let response=await apiRequest(f,tokens,'units.measurementApproval.inspect',{unitId:3});
 assert.equal(response.status,200,await response.clone().text());assert.equal((await response.json()).data.canRequest,true);
 response=await apiRequest(f,tokens,'units.measurementApproval.request',{unitId:3});
 assert.equal(response.status,200,await response.clone().text());assert.equal((await response.json()).data.requestState,'requested');
 requestError='limited';response=await apiRequest(f,tokens,'units.measurementApproval.request',{unitId:3});
 assert.equal(response.status,429);assert.equal(response.headers.get('retry-after'),'90');
 const problem=await response.json();assert.equal(problem.code,'APPROVAL_REQUEST_LIMITED');assert.equal(problem.retryable,true);
 // The request transaction was rolled back: the outcome is definite, unlike other uncertain writes.
 assert.equal(problem.outcome,'rejected');
 requestError='unavailable';
 response=await apiRequest(f,tokens,'units.measurementApproval.request',{unitId:3});
 assert.equal(response.status,503);
 assert.equal(response.headers.get('retry-after'),null);
 const uncertain=await response.json();
 assert.equal(uncertain.outcome,'unknown');assert.equal(uncertain.retryable,false);
 const read=await connect(f,{unitId:3,scope:READ.join(' ')});
 response=await apiRequest(f,read.tokens,'units.measurementApproval.request',{unitId:3});assert.equal(response.status,403);
 // Organizer settings write alone does not authorize administrator emails.
 const settings=await connect(f,{unitId:3,scope:[...READ,'festapp:unit-settings:write'].join(' ')});
 response=await apiRequest(f,settings.tokens,'units.measurementApproval.request',{unitId:3});assert.equal(response.status,403);
 response=await apiRequest(f,settings.tokens,'units.measurementApproval.inspect',{unitId:3});
 assert.equal(response.status,200);assert.equal((await response.json()).data.canRequest,false);
 const eventOnly=await connect(f,{occasionIds:[7],scope:scopes.join(' ')});
 response=await apiRequest(f,eventOnly.tokens,'units.measurementApproval.inspect',{unitId:3});
 assert.equal(response.status,403);assert.equal((await response.json()).code,'ORGANIZER_CONSENT_REQUIRED');
 assert.equal(requests,3);
});
