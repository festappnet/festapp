import test from 'node:test';
import assert from 'node:assert/strict';
import { createWebhookEvent, WEBHOOK_TYPES } from '../src/remote/webhook-protocol.mjs';
import { validateWebhookEvent } from '../src/remote/webhook-events.mjs';
const eventId='11111111-1111-4111-8111-111111111111';
const event=()=>createWebhookEvent({eventId,organizationId:3,orderId:7,type:WEBHOOK_TYPES.orderCreated,occurredAt:'2026-11-14T12:00:00Z',data:{
 orderId:7,occasionId:8,formId:9,customer:{name:'Jana',surname:null,email:'jana@example.invalid',phone:null},
 responses:[{'10':true},{'11':['A','B']}],formFields:[{id:10,title:'Souhlas',type:'checkbox'}],tickets:[{id:12,responses:[{'13':'Bezlepková strava'}]}],
}});
test('outgoing event contract preserves typed answers and rejects additional disclosures before dispatch',()=>{
 assert.deepEqual(validateWebhookEvent(event(),8),event());
 for(const changed of [
  {...event(),data:{...event().data,paymentSecret:'private'}},
  {...event(),data:{...event().data,customer:{...event().data.customer,password:'private'}}},
  {...event(),data:{...event().data,tickets:[{id:12,responses:[],ticket_symbol:'private'}]}},
  {...event(),data:{...event().data,responses:[{internal_token:'private'}]}},
  {...event(),data:{...event().data,orderId:99}},
 ])assert.throws(()=>validateWebhookEvent(changed,8));
 assert.throws(()=>validateWebhookEvent(event(),99));
});
test('synthetic event contract cannot be used to transport real customer data',()=>{
 const test=createWebhookEvent({eventId,organizationId:3,type:WEBHOOK_TYPES.test,occurredAt:'2026-11-14T12:00:00Z',data:{test:true,occasionId:8}});
 assert.equal(validateWebhookEvent(test,8).data.test,true);
 assert.throws(()=>validateWebhookEvent({...test,data:{...test.data,customer:{email:'private'}}},8));
});

test('published operator projections describe both signed outgoing events; summary profiles advertise neither data nor signatures',async()=>{
 const {readFileSync}=await import('node:fs');
 const {PUBLIC_API_FACADES,API_DATA_PROFILES,API_PROOF_PROFILES,apiProjectionDirectory}=await import('../src/remote/endpoints.mjs');
 for(const endpoint of PUBLIC_API_FACADES)for(const profile of API_DATA_PROFILES)for(const proof of API_PROOF_PROFILES){
  const spec=JSON.parse(readFileSync(new URL('../contracts/api-v1/'+apiProjectionDirectory(endpoint.endpointId,profile,proof)+'/openapi.json',import.meta.url)));
  if(profile==='order-summary'){assert.equal(spec.webhooks,undefined);assert.equal(spec.components.securitySchemes.webhookSignature,undefined);continue;}
  assert.deepEqual(Object.keys(spec.webhooks).sort(),Object.values(WEBHOOK_TYPES).sort());
  for(const type of Object.values(WEBHOOK_TYPES)){
   const op=spec.webhooks[type].post;
   assert.deepEqual(op.security,[{webhookSignature:[]}]);
   assert.deepEqual(op.parameters.filter(p=>p.required).map(p=>p.name).sort(),['webhook-id','webhook-signature','webhook-timestamp']);
   const ref=op.requestBody.content['application/cloudevents+json'].schema.$ref;
   const schema=spec.components.schemas[ref.split('/').at(-1)];
   assert.equal(schema.properties.data.additionalProperties,false);
  }
 }
});
