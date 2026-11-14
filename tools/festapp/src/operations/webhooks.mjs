import { z } from 'zod';
import { randomUUID } from 'node:crypto';
import { check, upstream, OperationError } from '../errors.mjs';
import { digest } from '../context/profile.mjs';
import { connectionDeadline } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { WEBHOOK_TYPES, generateWebhookSecret } from '../remote/webhook-protocol.mjs';
import { validateWebhookUrl } from '../remote/webhook-delivery.mjs';
const numericId=z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const base={occasionId:numericId}, target={...base,subscriptionId:z.uuid()};
const command={...target,commandId:z.uuid()}, versioned={...command,expectedVersion:z.number().int().positive()};
const subscription=z.strictObject({id:z.uuid(),occasionId:numericId,formId:numericId.nullable(),version:z.number().int().positive(),state:z.enum(['active','paused','deleted','disabled']),expiresAt:z.iso.datetime({offset:true}),destinationHost:z.string().optional()});
const history=z.strictObject({at:z.iso.datetime({offset:true}),series:z.number().int(),attempt:z.number().int(),status:z.number().int().nullable(),error:z.string().nullable()});
const delivery=z.strictObject({id:z.uuid(),eventId:z.uuid(),state:z.enum(['pending','leased','succeeded','exhausted','blocked']),attempts:z.number().int(),series:z.number().int(),httpStatus:z.number().int().nullable(),errorCategory:z.string().nullable(),history:z.array(history).max(16)});
const signingSecret=z.string().regex(/^whsec_[A-Za-z0-9+/]{43}=$/);
const receipt={commandId:z.uuid(),replayed:z.boolean()};
export const webhookDataSchemas={
 'webhooks.list':z.strictObject({subscriptions:z.array(subscription).max(10)}),
 'webhooks.deliveries':z.strictObject({deliveries:z.array(delivery).max(50)}),
 'webhooks.create':z.strictObject({...receipt,subscription,signingSecret}),
 'webhooks.rotate_secret':z.strictObject({...receipt,subscription,signingSecret}),
 'webhooks.update':z.strictObject({...receipt,subscription}),
 'webhooks.delete':z.strictObject({...receipt,subscription}),
 'webhooks.test':z.strictObject({...receipt,deliveryId:z.uuid()}),
 'webhooks.redeliver':z.strictObject({...receipt,deliveryId:z.uuid()}),
};
const description='Manage this connection\'s order-created webhook subscriptions for one consented occasion. Requires live order access; order-summary clients are excluded. Commands must preserve commandId and identical arguments on timeout. Signing secrets are returned only for create/rotate, including authorized command replay. Delivery is asynchronous, at least once, with no ordering guarantee. For agent-driven management, obtain explicit user approval of the destination URL, occasion/form and disclosed data before creating or changing an endpoint or redelivering a real event.';
export const webhookDescriptors=[
 {id:'webhooks.list',input:z.strictObject(base),domainReadOnly:true},
 {id:'webhooks.create',input:z.strictObject({...base,commandId:z.uuid(),expectedContractVersion:z.literal(1),eventTypes:z.tuple([z.literal(WEBHOOK_TYPES.orderCreated)]),url:z.string().max(2048),formId:numericId.optional()}),domainReadOnly:false,idempotent:true},
 {id:'webhooks.update',input:z.strictObject({...versioned,url:z.string().max(2048).optional(),state:z.enum(['active','paused']).optional()}).refine(v=>v.url!==undefined||v.state!==undefined),domainReadOnly:false,idempotent:true},
 {id:'webhooks.delete',input:z.strictObject(versioned),domainReadOnly:false,idempotent:true},
 {id:'webhooks.rotate_secret',input:z.strictObject(versioned),domainReadOnly:false,idempotent:true},
 {id:'webhooks.test',input:z.strictObject(command),domainReadOnly:false,idempotent:true},
 {id:'webhooks.deliveries',input:z.strictObject({...target,before:z.uuid().optional()}),domainReadOnly:true},
 {id:'webhooks.redeliver',input:z.strictObject({...command,deliveryId:z.uuid()}),domainReadOnly:false,idempotent:true},
].map(d=>({...d,...(!d.domainReadOnly?{destructive:true}:{}),name:'festapp_'+d.id.replaceAll('.','_'),description}));

export function webhookBinding(owner){
 const g=owner.current();
 return digest(JSON.stringify(['webhook',g.id,g.clientId,g.userId,g.resource,g.profileBinding]));
}
export async function webhookRpc(owner,client,occasionId,action,input={}){
 const scope=await owner.delegatedContext(client,occasionId);
 const {data,error,status}=await client.rpc('integration_webhook_api_v1',{p_occasion:occasionId,p_organization:scope.organizationId,p_unit:scope.unitId,p_binding:webhookBinding(owner),p_action:action,p_input:input});
 if(['22023','23514','54000'].includes(error?.code))throw new OperationError('INVALID_INPUT');
 if(error?.code==='PT409')throw new OperationError('WEBHOOK_VERSION_CONFLICT');
 if(['40001','40P01'].includes(error?.code))throw new OperationError('WEBHOOK_CHANGED_RETRY_SAME_COMMAND',true);
 upstream(error&&{...error,status:error.status??status});return data;
}
export async function invokeWebhookOperation(owner,client,operation,args){
 check(owner.storage&&owner.current&&!owner.orderSummaryOnly,'FORBIDDEN');
 const grant=owner.current(),binding=webhookBinding(owner),store=owner.storage;
 const expiry=connectionDeadline(grant),action=operation.slice('webhooks.'.length);
 const key=id=>binding+':'+id;
 const decorate=s=>{const local=store.get('WebhookSubscription',key(s.id));return {...s,...(local?{destinationHost:new URL(local.url).hostname}:{})};};
 if(action==='list'){
  const response=await webhookRpc(owner,client,args.occasionId,action);
  return {subscriptions:response.subscriptions.map(decorate)};
 }
 if(action==='deliveries'){
  const local=store.get('WebhookSubscription',key(args.subscriptionId));
  check(local&&local.occasionId===args.occasionId,'FORBIDDEN');
  return webhookRpc(owner,client,args.occasionId,action,{subscriptionId:args.subscriptionId,before:args.before});
 }
 if(args.url!==undefined)validateWebhookUrl(args.url);
 // One encrypted intent record durably retains the key BEFORE SQL registration.
 // The same command lock serializes create/replay before a subscription exists.
 return store.runSessionExclusive('webhook-command:'+key(args.commandId),async()=>{
  const requestHash=digest(JSON.stringify([operation,args]));
  let intent=store.get('WebhookCommand',key(args.commandId));
  check(!intent||intent.requestHash===requestHash,'INVALID_INPUT');
  const sid=intent?.subscriptionId??args.subscriptionId??randomUUID();
  return store.runSessionExclusive('webhook-subscription:'+key(sid),async()=>{
   let local=store.get('WebhookSubscription',key(sid));
   check(action==='create'||local&&local.occasionId===args.occasionId,'FORBIDDEN');
   check(!local||local.state!=='deleted'||action==='delete','FORBIDDEN');
   check(!local?.pendingCommand||local.pendingCommand===args.commandId,'WEBHOOK_CHANGED_RETRY_SAME_COMMAND');
   if(!intent){
    const current=local;
    if(args.expectedVersion)check(current.version===args.expectedVersion,'WEBHOOK_VERSION_CONFLICT');
    if(action==='rotate_secret')check(!current.secrets.some(k=>k.expiresAt&&k.expiresAt>Date.now()),'WEBHOOK_CHANGED_RETRY_SAME_COMMAND');
    const config=action==='create'?{id:sid,occasionId:args.occasionId,formId:args.formId??null,url:new URL(args.url).href,state:'active',version:0,
      secrets:[{key:generateWebhookSecret()}],grantId:grant.id,binding,expiresAt:expiry}:
      {...current,...(args.url?{url:new URL(args.url).href}:{}),...(args.state?{state:args.state}:{}),
        ...(action==='delete'?{state:'deleted'}:{}),
        ...(action==='rotate_secret'?{secrets:[{key:generateWebhookSecret()},{key:current.secrets[0].key,expiresAt:Date.now()+3600000}]}:{})};
    const sql={subscriptionId:sid,commandId:args.commandId,
      ...(action==='create'?{formId:args.formId??null,expiresAt:new Date(expiry).toISOString()}:{}),
      ...(args.expectedVersion?{expectedVersion:args.expectedVersion}:{}),
      ...(action==='update'?{state:config.state}:{}),...(args.deliveryId?{deliveryId:args.deliveryId}:{})};
    intent={requestHash,operation,args,subscriptionId:sid,config,previous:current,sql,grantId:grant.id,phase:'pending'};
    store.stageWebhookCommand(key(args.commandId),intent,key(sid),{...config,pendingCommand:args.commandId},expiry);
   }
   if(intent.phase==='rejected'){
    intent={...intent,phase:'pending'};
    store.stageWebhookCommand(key(args.commandId),intent,key(sid),{...intent.config,pendingCommand:args.commandId},expiry);
   }
   let response;
   try{response=await webhookRpc(owner,client,args.occasionId,action,intent.sql);}
   catch(error){
    if(['INVALID_INPUT','WEBHOOK_VERSION_CONFLICT','WEBHOOK_CHANGED_RETRY_SAME_COMMAND'].includes(error.code)&&intent.phase!=='completed')
     store.rejectWebhookCommand(key(args.commandId),{...intent,phase:'rejected'},key(sid),intent.previous,expiry);
    throw error;
   }
   owner.current();
   const config={...intent.config,...(response.subscription?{version:response.subscription.version,state:response.subscription.state}:{})};
   delete config.pendingCommand;
   const output={...response,...(response.subscription?{subscription:decorate(response.subscription)}:{}),
     ...(['create','rotate_secret'].includes(action)?{signingSecret:config.secrets[0].key}:{})};
   store.finishWebhookCommand(key(args.commandId),{...intent,phase:'completed'},key(sid),config,expiry);
   return output;
  });
 });
}
