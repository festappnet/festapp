import {z} from 'zod';
import {operatorAccess} from './access.mjs';
import {CONSENT_PROVIDERS,parseFormConsentExport} from './form-embed.mjs';
import {check,upstream,OperationError} from '../errors.mjs';
const id=z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const origin=z.string().max(2048);
// Rows are not count-limited in SQL (bindings survive removal of a website), so
// snapshots are read without a count limit and outputs keep at most LIMIT entries.
const LIMIT=100;
const rawOrigins=z.array(origin);
const origins=z.array(origin).max(LIMIT);
const bounded=values=>values.slice(0,LIMIT);
const revision=z.string().regex(/^[a-f0-9]{32}$/);
const object=value=>typeof value==='object'&&value!==null&&!Array.isArray(value);
// SQL owns these snapshots and may add internal fields before this adapter is
// redeployed. Read only the listed keys; never forward or fail on unknown ones.
const projected=shape=>z.preprocess(value=>object(value)?Object.fromEntries(Object.entries(value).filter(([key])=>Object.hasOwn(shape,key))):value,z.strictObject(shape));
// A newer server value is reported as unknown (never ready) rather than failing the read.
const known=(value,values,fallback)=>values.includes(value)?value:fallback;
const BINDING_STATES=['draft','disabled','confirmation_required','ready','unavailable'];
const PLATFORMS=['wordpress','joomla','wix','html'];
const REQUEST_STATES=['not_requested','requested','retry_available'];
const bindingSnapshot=projected({organization:id,unit:id,consentRevision:revision,saved_origins:rawOrigins,
 bindings:z.array(projected({id:z.uuid(),websiteOrigin:origin,platform:z.string().max(64),providerConfig:projected({provider:z.string().max(64)}),
  version:id,state:z.string().max(64)}))});
const timestamp=z.iso.datetime({offset:true}).nullable();
const measurementSnapshot=projected({approved:z.boolean(),runtime_supported:z.boolean(),requested_at:timestamp,approved_origins:rawOrigins,
 saved_origins:rawOrigins,requested_origins:rawOrigins,request_state:z.string().max(64),can_request:z.boolean()});
const metaSnapshot=projected({approved:z.boolean(),requested_at:timestamp,request_state:z.string().max(64),can_request:z.boolean()});

const binding=z.strictObject({id:z.uuid(),websiteOrigin:origin,platform:z.enum([...PLATFORMS,'unknown']),provider:z.enum([...CONSENT_PROVIDERS,'unknown']),
 version:id,state:z.enum([...BINDING_STATES,'unknown'])});
const websiteConsent=z.strictObject({unitId:id,organizationId:id,consentRevision:revision,savedOrigins:origins,bindings:z.array(binding).max(LIMIT),truncated:z.boolean()});
const requestState=z.enum([...REQUEST_STATES,'unavailable']);
// Organization platform policy is deliberately not projected: demo organizers
// must not learn it. approved/runtimeSupported describe only this organizer.
const measurementApproval=z.strictObject({unitId:id,approved:z.boolean(),runtimeSupported:z.boolean(),requestState,canRequest:z.boolean(),
 requestedAt:timestamp,approvedOrigins:origins,savedOrigins:origins,requestedOrigins:origins,truncated:z.boolean()});
const metaCapiApproval=z.strictObject({unitId:id,organizationId:id,approved:z.boolean(),requestState,canRequest:z.boolean(),requestedAt:timestamp});
const consentExport=z.strictObject({unitId:id,bindingId:z.uuid(),bindingVersion:id,websiteOrigin:origin,provider:z.enum(CONSENT_PROVIDERS),consentExport:z.string().max(16384)});
export const measurementSetupDataSchemas={
 'units.websiteConsent.inspect':websiteConsent,'units.websiteConsent.export':consentExport,
 'units.measurementApproval.inspect':measurementApproval,'units.measurementApproval.request':measurementApproval,
 'units.metaCapiApproval.inspect':metaCapiApproval,'units.metaCapiApproval.request':metaCapiApproval,
};
const unitInput=z.strictObject({unitId:id});
const reconfirm='Confirmation of a binding is the organizer\'s own statement about its website banner and happens only in organizer administration; MCP cannot confirm, change or disable bindings.';
const request=(what,content)=>`Sends ${what} approval request email to every administrator of the organization who has a deliverable address, with ${content} and a link to organization settings; the platform then confirms the approval. Approve the exact change first: name the organizer and that all organization administrators will be emailed. Uses the administration request owner; there is no commandId. While a request is active, after approval or for a demo organizer nothing is sent and the current status is returned, so an uncertain response can be repeated. retry_available means the earlier emails are no longer active and a repeat sends a new request. APPROVAL_REQUEST_LIMITED means nothing was sent; when retryable, its message states the seconds to wait. APPROVAL_REQUEST_NO_RECIPIENT means no administrator has a deliverable email address; nothing was sent and the request stays available. Requires whole-organizer consent and its live manager role.`;
export const measurementSetupDescriptors=[
 {id:'units.websiteConsent.inspect',name:'festapp_units_website_consent_inspect',domainReadOnly:true,input:unitInput,description:'Read the state of website consent bindings (the organizer\'s cookie banner on its own websites passed to embedded forms) and the current consentRevision. ready means the binding is used; confirmation_required means the consent notice changed after confirmation (see festapp_units_settings_save) and the website is treated as unbound until reconfirmed; unavailable means the consent bridge is off, the website is no longer saved or the organizer is a demo; draft/disabled are not used; unknown is a newer server state and is never ready. Bindings of saved websites are listed first; truncated means more than 100 bindings or saved websites exist and the rest are omitted. Returns platform and banner provider only, no provider configuration. '+reconfirm+' Requires whole-organizer consent and its live manager role.'},
 {id:'units.websiteConsent.export',name:'festapp_units_website_consent_export',domainReadOnly:true,input:z.strictObject({unitId:id,bindingId:z.uuid(),expectedVersion:id}),description:'Read the consent import text of one ready website consent binding, exactly as the organizer administration copies it. Pass consentExport unchanged to festapp_forms_embed_code for an HTML embed on that website. It contains public identifiers that become part of the website code, no credentials. Use bindingId and version from festapp_units_website_consent_inspect; a changed binding returns WEBSITE_CONSENT_CHANGED_RELOAD_REQUIRED and a binding that is not ready returns WEBSITE_CONSENT_NOT_READY. Requires whole-organizer consent and its live manager role.'},
 {id:'units.measurementApproval.inspect',name:'festapp_units_measurement_approval_inspect',domainReadOnly:true,input:unitInput,description:'Read the platform approval of the form dataLayer and measurement runtime for this organizer: approved, runtimeSupported, request state and time, approved, saved and requested website origins (truncated when a list exceeds 100). Platform approval is independent of the organization, organizer and form switches. canRequest says whether festapp_units_measurement_approval_request would send a request for this account and connection: it is false without the live manager role or the festapp:unit-approvals:request permission. Requires whole-organizer consent and its organizer administration read or manager role.'},
 {id:'units.measurementApproval.request',name:'festapp_units_measurement_approval_request',domainReadOnly:false,idempotent:true,destructive:false,input:unitInput,description:'Ask the platform to approve the form dataLayer and measurement runtime for this organizer and its currently saved websites. When the platform then provisions or changes the measurement runtime, consentRevision changes: every enabled website consent binding becomes confirmation_required and must be reconfirmed in organizer administration (see festapp_units_website_consent_inspect). Mention this when asking for approval. '+request('a measurement','the organizer, organization and saved websites')},
 {id:'units.metaCapiApproval.inspect',name:'festapp_units_meta_capi_approval_inspect',domainReadOnly:true,input:unitInput,description:'Read the platform approval of Meta Conversions API. The approval and the pending request belong to the whole organization, not only this organizer: a request from any organizer shows here. approved is always false for demo organizers. canRequest is false without the live manager role or the festapp:unit-approvals:request permission. Connector settings and tokens are not exposed. Requires whole-organizer consent and its organizer administration read or manager role.'},
 {id:'units.metaCapiApproval.request',name:'festapp_units_meta_capi_approval_request',domainReadOnly:false,idempotent:true,destructive:false,input:unitInput,description:'Ask the platform to approve Meta Conversions API for the whole organization; the request is shared by all its organizers and the latest requesting organizer is named. '+request('a Meta Conversions API','the organizer and organization')},
];
const writes=new Set(['units.measurementApproval.request','units.metaCapiApproval.request']);
const requestErrors=new Map([['measurement_request_no_recipient','APPROVAL_REQUEST_NO_RECIPIENT'],['meta_capi_request_no_recipient','APPROVAL_REQUEST_NO_RECIPIENT'],
 ['measurement_notification_origin_missing','APPROVAL_REQUEST_REJECTED'],['meta_capi_notification_origin_missing','APPROVAL_REQUEST_REJECTED']]);
// Email admission raises PT429 with {retryAfterSeconds,needsPolicyChange}. The
// transaction is rolled back, so nothing was sent and the request stays available.
export function approvalRequestError(error){
 if(error?.code==='PT429'){
  let detail;try{detail=JSON.parse(error.details);}catch{detail=null;}
  // A hard cap is not resolved by waiting; otherwise use the queue's 60 s default.
  if(detail?.needsPolicyChange===true)return new OperationError('APPROVAL_REQUEST_LIMITED');
  const seconds=detail?.retryAfterSeconds;
  const limited=new OperationError('APPROVAL_REQUEST_LIMITED',true);
  limited.retryAfter=Number.isSafeInteger(seconds)&&seconds>0?Math.min(seconds,86400):60;
  return limited;
 }
 if(error?.code==='P0001'&&requestErrors.has(error.message))return new OperationError(requestErrors.get(error.message));
 if(error?.code==='22023')return new OperationError('APPROVAL_REQUEST_REJECTED');
 return null;
}
const approval=(operation,value,unitId,organizationId,mayRequest)=>{
 const state=known(value.request_state,REQUEST_STATES,'unavailable');
 const common={unitId,approved:value.approved,requestState:state,canRequest:mayRequest&&value.can_request&&['not_requested','retry_available'].includes(state),requestedAt:value.requested_at};
 if(operation.startsWith('units.metaCapiApproval.'))return {...common,organizationId};
 const lists=[value.approved_origins,value.saved_origins,value.requested_origins];
 return {...common,runtimeSupported:value.runtime_supported,approvedOrigins:bounded(lists[0]),savedOrigins:bounded(lists[1]),requestedOrigins:bounded(lists[2]),truncated:lists.some(list=>list.length>LIMIT)};
};
// get_unit_measurement_approval reports can_request without the caller's rights.
// Use the same live check as the request owner and the connection's own scopes.
async function mayRequest(owner,client,operation,unitId){
 const request=operation.replace(/\.inspect$/,'.request');
 if(owner.allowedOperations&&!owner.allowedOperations.includes(request))return false;
 const {data,error}=await client.rpc('can_manage_unit_configuration',{p_unit:unitId});
 upstream(error);
 check(typeof data==='boolean');
 return data;
}
async function bindings(client,args,bound){
 const {data,error}=await client.rpc('get_unit_website_consent_bindings',{p_unit:args.unitId});
 upstream(error);
 const parsed=bindingSnapshot.safeParse(data);
 check(parsed.success&&parsed.data.unit===args.unitId&&parsed.data.organization===bound.organizationId);
 return parsed.data;
}
export async function invokeMeasurementSetupOperation(owner,client,operation,args){
 const bound=await owner.delegatedUnitContext(client,args.unitId);
 // These native RPCs take a Unit only; establish its live tenant binding first.
 const available=await operatorAccess(client,bound,{unitId:args.unitId});
 check(available.units.some(unit=>unit.id===args.unitId),'FORBIDDEN');
 const schema=measurementSetupDataSchemas[operation];
 if(operation.startsWith('units.websiteConsent.')){
  const snapshot=await bindings(client,args,bound);
  if(operation==='units.websiteConsent.inspect'){
   const saved=new Set(snapshot.saved_origins);
   // Stable partition: bindings of currently saved websites first, SQL order otherwise.
   const ordered=[...snapshot.bindings.filter(b=>saved.has(b.websiteOrigin)),...snapshot.bindings.filter(b=>!saved.has(b.websiteOrigin))];
   return schema.parse({unitId:args.unitId,organizationId:snapshot.organization,consentRevision:snapshot.consentRevision,savedOrigins:bounded(snapshot.saved_origins),
    bindings:bounded(ordered).map(b=>({id:b.id,websiteOrigin:b.websiteOrigin,platform:known(b.platform,PLATFORMS,'unknown'),provider:known(b.providerConfig.provider,CONSENT_PROVIDERS,'unknown'),version:b.version,state:known(b.state,BINDING_STATES,'unknown')})),
    truncated:ordered.length>LIMIT||snapshot.saved_origins.length>LIMIT});
  }
  // The export RPC takes only a binding ID: prove it belongs to this consented organizer.
  const current=snapshot.bindings.find(b=>b.id===args.bindingId);
  check(current,'NOT_FOUND_OR_INACCESSIBLE');
  check(current.version===args.expectedVersion,'WEBSITE_CONSENT_CHANGED_RELOAD_REQUIRED');
  check(current.state==='ready','WEBSITE_CONSENT_NOT_READY');
  const {data,error}=await client.rpc('export_unit_website_consent_binding',{p_binding:args.bindingId,p_expected_version:args.expectedVersion});
  if(error?.code==='40001')throw new OperationError('WEBSITE_CONSENT_CHANGED_RELOAD_REQUIRED');
  if(error?.code==='22023')throw new OperationError(error.message==='website_consent_not_ready'?'WEBSITE_CONSENT_NOT_READY':'WEBSITE_CONSENT_REJECTED');
  upstream(error);
  const text=JSON.stringify(data,null,2);
  const parsed=typeof data?.serviceOrigin==='string'?parseFormConsentExport(text,data.serviceOrigin):null;
  check(parsed&&parsed.binding.id===args.bindingId&&parsed.binding.version===args.expectedVersion&&parsed.websiteOrigin===current.websiteOrigin&&
   parsed.providerConfig.unit===args.unitId&&parsed.providerConfig.organization===bound.organizationId);
  return schema.parse({unitId:args.unitId,bindingId:args.bindingId,bindingVersion:args.expectedVersion,websiteOrigin:parsed.websiteOrigin,provider:parsed.providerConfig.provider,consentExport:text});
 }
 const meta=operation.startsWith('units.metaCapiApproval.');
 const rpc=`${writes.has(operation)?'request':'get'}_unit_${meta?'meta_capi':'measurement'}_approval`;
 const {data,error}=await client.rpc(rpc,{p_unit:args.unitId});
 if(writes.has(operation)){const mapped=approvalRequestError(error);if(mapped)throw mapped;}
 upstream(error);
 const parsed=(meta?metaSnapshot:measurementSnapshot).safeParse(data);
 check(parsed.success);
 // A request result already comes from the authorized owner; reads must not offer a request the caller cannot make.
 const may=writes.has(operation)||!parsed.data.can_request?true:await mayRequest(owner,client,operation,args.unitId);
 return schema.parse(approval(operation,parsed.data,args.unitId,bound.organizationId,may));
}
