import test from 'node:test';
import assert from 'node:assert/strict';
import {Operations} from '../src/operations/catalog.mjs';
function fixture(response){const calls=[];const client={functions:{invoke:async(name,args)=>{calls.push({name,...args});return{data:response,error:null};}},rpc:async()=>{throw new Error('Preview must not read another domain or mutate SQL');}};
 const owner={profile:{name:'fixture',tenantId:'fixture',organizationId:3},root:'/tmp/email-preview-boundary',allowedOperations:['email_templates.preview'],delegatedContext:async()=>({organizationId:3,unitId:8}),authorized:fn=>fn(client,{userId:'00000000-0000-4000-8000-000000000001'})};return{calls,ops:new Operations(owner)};}
const args={entityType:'occasion',entityId:42,code:'TICKET_ORDER_CONFIRMATION',scenario:'zero'};
const reply={...args,locale:'cs',tone:'formal',synthetic:true,senderAddress:'preview@festapp.net',subject:'Synthetic',html:'<p>Example</p>'};
test('preview executor sends only consent-bound scope and synthetic scenario to the production renderer action',async()=>{
 const f=fixture(reply);const result=await f.ops.invoke('email_templates.preview',args);assert.equal(result.ok,true,JSON.stringify(result));
 assert.deepEqual(f.calls,[{name:'send-custom-email',body:{action:'authoringPreview',entityType:'occasion',entityId:42,organizationId:3,unitId:8,code:args.code,scenario:'zero',locale:'cs',tone:'formal'}}]);
 assert.equal((await f.ops.invoke('email_templates.preview',{...args,orderId:99})).error.code,'INVALID_INPUT');
});
test('preview executor rejects an unexpected scope instead of returning its content',async()=>{
 const f=fixture({...reply,entityId:43});const result=await f.ops.invoke('email_templates.preview',args);assert.equal(result.ok,false);assert.equal(result.error.code,'UPSTREAM_CONTRACT_FAILURE');assert.equal(result.data,undefined);
});
