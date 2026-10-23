import test from 'node:test';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {invokeSeatOrderOperation} from '../src/operations/seat-orders.mjs';
const actor='00000000-0000-4000-8000-000000000001',commandId='00000000-0000-4000-8000-000000000002';
const args={occasionId:1,blueprintId:2,spotIds:[3],actorId:actor,inputData:{email:'http@example.invalid',form_key:actor},targetSpotIds:[3],affectedSpotIds:[3],blueprints:[{id:2,revision:4}],confirmationHash:'a'.repeat(64),commandId};
const acknowledgement={code:200,status:'applied',mutation:{commandId,receiptId:commandId},data:{code:200,orderId:7,orderSymbol:'LOCAL7',quote:{spotIds:[3],affectedSpotIds:[3],releasedSpotIds:[],blueprints:[{id:2,revision:4}],formKey:actor,orders:[],newOrder:{amount:'100.00',currencyCode:'CZK',state:'ordered',paymentMethod:'bank',ticketCount:1}}},fulfillment:{status:'ready'}};
for(const failure of ['network','http503','relay200','http401','http403','relay401','relay403'])test('actual JS Supabase seat-order HTTP boundary preserves intent after '+failure,async()=>{
 let fail=true;const bodies=[];
 const client=createClient('https://fixture.invalid','synthetic-fixture-key',{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:async(url,options)=>{
  assert.equal(new URL(url).origin,'https://fixture.invalid');assert.equal(new URL(url).pathname,'/functions/v1/send-ticket-order');bodies.push(JSON.parse(options.body));
  if(fail){if(failure==='network')throw new TypeError('Synthetic lost response');if(failure.startsWith('relay'))return Response.json({},{status:Number(failure.slice(5)),headers:{'x-relay-error':'true'}});return Response.json({},{status:Number(failure.slice(4))});}
  return Response.json(acknowledgement);
 }}});
 const owner={profile:{binding:'local-session'},delegatedContext:async()=>({organizationId:1,unitId:4})};
 const call=()=>invokeSeatOrderOperation(owner,client,'seats.create_order',args,{userId:actor});
 const unauthorized=failure.endsWith('401'),forbidden=failure.endsWith('403'),denied=unauthorized||forbidden;
 await assert.rejects(call(),error=>error.code===(unauthorized?'AUTHENTICATION_REQUIRED':forbidden?'FORBIDDEN':'TEMPORARY_FAILURE_RETRY_SAME_COMMAND')&&error.retryable===!denied);
 fail=false;const result=await call();assert.equal(result.commandId,commandId);assert.equal(result.orderId,7);assert.equal(result.fulfillmentStatus,'ready');
 assert.equal(bodies.length,2);assert.deepEqual(bodies[1],bodies[0]);assert.equal(bodies[0].commandId,commandId);assert.equal(bodies[0].replacement.confirmation.actorId,actor);
 await client.auth.stopAutoRefresh();
});

test('actual MCP SDK publishes the confirmed order schema and invokes the same HTTP owner without PDF readiness',async t=>{
 const [{Operations},{createServer},{Client:McpClient,InMemoryTransport}]=await Promise.all([
  import('../src/operations/catalog.mjs'),import('../src/mcp/server.mjs'),import('@modelcontextprotocol/client')]);
 let writes=0;
 const client=createClient('https://fixture.invalid','synthetic-fixture-key',{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:async(url,options)=>{
  assert.equal(new URL(url).origin,'https://fixture.invalid');assert.equal(new URL(url).pathname,'/functions/v1/send-ticket-order');
  const body=JSON.parse(options.body);assert.equal(body.commandId,commandId);assert.equal(body.replacement.confirmation.editor,false);writes++;return Response.json(acknowledgement);
 }}});
 const owner={root:'/tmp/festapp-seat-order-protocol',profile:{binding:'protocol-fixture',name:'fixture',tenantId:'fixture',organizationId:1,backendOrigin:'https://fixture.invalid'},allowedOperations:['seats.preview_order','seats.create_order'],
  delegatedContext:async()=>({organizationId:1,unitId:4}),authorized:callback=>callback(client,{userId:actor})};
 const operations=new Operations(owner),server=createServer(operations),sdk=new McpClient({name:'seat-order-fixture',version:'1'});
 const [one,two]=InMemoryTransport.createLinkedPair();await server.connect(one);await sdk.connect(two);
 t.after(async()=>{await sdk.close();await server.close();await client.auth.stopAutoRefresh();});
 const listing=await sdk.listTools();assert.deepEqual(listing.tools.map(tool=>tool.name),['festapp_seats_preview_order','festapp_seats_create_order']);
 const tool=listing.tools.find(tool=>tool.name==='festapp_seats_create_order');assert.equal(tool.inputSchema.additionalProperties,false);assert(tool.inputSchema.required.includes('actorId'));assert.equal(tool.annotations.destructiveHint,true);assert.equal(tool.annotations.idempotentHint,true);
 const result=await sdk.callTool({name:tool.name,arguments:args});assert(!result.isError);assert.equal(result.structuredContent.ok,true);assert.equal(result.structuredContent.data.orderId,7);assert.equal(writes,1);assert.equal(operations.writeReady,false,'seat operations do not activate or bypass the PDF writer family');
});
