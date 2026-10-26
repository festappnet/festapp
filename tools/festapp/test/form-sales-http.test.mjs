import test from'node:test';import assert from'node:assert/strict';import{createClient}from'@supabase/supabase-js';
import{invokeFormSalesOperation}from'../src/operations/form-sales.mjs';
import{executeWaitlistOperation}from'../../../supabase/functions/waitlist-commands/executeOperation.ts';
const actor='00000000-0000-4000-8000-000000000001',commandId='00000000-0000-4000-8000-000000000002',offerId='00000000-0000-4000-8000-000000000003';
const scope={occasionId:7,formId:42},input={email:'fixture@example.invalid',ticket:[{fields:[{product_type:4}]}]},quote={newOrder:{amount:'12.00',currencyCode:'CZK',state:'ordered',paymentMethod:'bank',bankAccountId:2,bankAccountNumber:'123/0800',bankAccountDisplay:'123/0800',ticketCount:1}};
const owner={delegatedContext:async()=>({organizationId:3,unitId:8})},order={...scope,input,actorId:actor,confirmationHash:'a'.repeat(64),commandId};
const acknowledged={code:200,status:'applied',mutation:{commandId,receiptId:commandId},data:{orderId:88,orderSymbol:'SYNTHETIC88',quote,adminScope:{...scope,actorId:actor}},fulfillment:{status:'ready'}};
for(const operation of ['forms.createOrder','waitlist.accept','waitlist.send'])for(const failure of ['network','http503','relay200','http401','relay403'])test('actual Supabase '+operation+' transport preserves intent after '+failure,async()=>{
 let failing=true;const bodies=[];const client=createClient('https://fixture.invalid','synthetic-key',{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:async(url,options)=>{
  assert.equal(new URL(url).pathname,operation==='waitlist.send'?'/functions/v1/waitlist-commands':'/functions/v1/send-ticket-order');bodies.push(JSON.parse(options.body));if(failing){if(failure==='network')throw TypeError('Synthetic lost reply');if(failure.startsWith('relay'))return Response.json({},{status:Number(failure.slice(5)),headers:{'x-relay-error':'true'}});return Response.json({},{status:Number(failure.slice(4))});}
  return Response.json(operation==='waitlist.send'?{...acknowledged,data:{offers:[{orderId:8,offerId,count:1,expiresAt:'2030-01-01T00:00:00Z',email:{status:'queued'}}]}}:acknowledged);
 }}});
 const args=operation==='waitlist.send'?{...scope,revision:1,expiresAt:'2030-01-01T00:00:00Z',recipients:[{orderId:8,count:1}],commandId}:operation==='waitlist.accept'?{...order,offerId,ticketIds:[5],input:{...input,ticket:[{ticketId:5,fields:[{product_type:4}]}]}}:order;
 const call=()=>invokeFormSalesOperation(owner,client,operation,args,{userId:actor});const expected=failure.endsWith('401')?'AUTHENTICATION_REQUIRED':failure.endsWith('403')?'FORBIDDEN':'TEMPORARY_FAILURE_RETRY_SAME_COMMAND';await assert.rejects(call(),e=>e.code===expected&&e.retryable===!['AUTHENTICATION_REQUIRED','FORBIDDEN'].includes(expected));failing=false;const done=await call();assert.equal(done.commandId,commandId);assert.deepEqual(bodies[0],bodies[1]);await client.auth.stopAutoRefresh();
});

test('a committed pending invoice stays attached to the same confirmed form/acceptance intent',async()=>{
 for(const operation of ['forms.createOrder','waitlist.accept']){const client={functions:{invoke:async()=>({error:null,data:{code:503,committed:{...acknowledged,fulfillment:{status:'pending'}}}})}};const args=operation==='waitlist.accept'?{...order,offerId,ticketIds:[5]}:order;const result=await invokeFormSalesOperation(owner,client,operation,args,{userId:actor});assert.equal(result.orderId,88);assert.equal(result.fulfillmentStatus,'pending');assert.equal(result.retrySameCommand,true);}
});

test('administrative waitlist scope rejection precedes capability preparation and service mutation',async()=>{
 let effects=0;const result=await executeWaitlistOperation({operation:'send',payload:{formId:42},commandId,clientId:commandId,actor,administration:{...scope,organizationId:3,unitId:8},userRpc:async()=>({data:null,error:{code:'42501'}}),serviceRpc:async()=>{effects++;return{data:null,error:null};},prepareDelivery:async()=>{effects++;return{};}});assert(result.error);assert.equal(effects,0);
});
