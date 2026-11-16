import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Client,InMemoryTransport} from '@modelcontextprotocol/client';
import {Operations} from '../src/operations/catalog.mjs';
import {createServer} from '../src/mcp/server.mjs';
import {informationDescriptors,invokeInformationOperation} from '../src/operations/information.mjs';
import {scopesForOperation} from '../../../packages/festapp_contracts/mcp-permissions.mjs';
import {setup,connect,apiRequest} from './api-fixture.mjs';
import {reply} from './fixture.mjs';
const information={id:12,title:'Fotogalerie z minulých let',description:'<p>Existing galleries</p>',type:null,isHidden:false,order:4,data:{style:'default'}};
const snapshot={information,aggregateVersion:2};
const scope='festapp:ticket-layouts:read festapp:information:read festapp:information:write';
function fixture(){
 const calls=[];
 const client={rpc:async(name,args)=>{
  calls.push({name,args});assert.equal(name,'manage_information_authoring');
  if(args.p_action==='list')return{data:{items:[{id:12,title:information.title,isHidden:false,order:4,aggregateVersion:2}]}};
  if(args.p_action==='inspect')return{data:snapshot};
  return{data:{code:200,status:'applied',mutation:{commandId:args.p_command_id,receiptId:args.p_command_id},data:{...snapshot,information:args.p_payload.information,aggregateVersion:3}}};
 }};
 const owner={root:'/tmp/information-sdk',profile:{name:'fixture',tenantId:'fixture',organizationId:1},allowedOperations:informationDescriptors.map(d=>d.id),delegatedContext:async()=>({organizationId:1,unitId:3}),authorized:action=>action(client)};
 return{owner,client,calls};
}
test('information consent is explicit and full editor payload excludes game/hidden fields',()=>{
 assert.deepEqual(scopesForOperation('information.save'),['festapp:ticket-layouts:read','festapp:information:read','festapp:information:write']);
 const schema=informationDescriptors.find(d=>d.id==='information.save').input;
 const args={occasionId:7,commandId:randomUUID(),expectedVersion:2,information};
 assert(schema.safeParse(args).success);
 for(const value of [{...args,expectedVersion:null},{...args,information:{...information,type:'game'}},{...args,information:{...information,hiddenData:{answer:'secret'}}},{...args,information:{id:12,title:'Incomplete',description:'Lost metadata'}}])assert.equal(schema.safeParse(value).success,false);
});
test('MCP SDK lists and invokes canonical information operations with exact scope and editor metadata',async t=>{
 const f=fixture(),server=createServer(new Operations(f.owner)),sdk=new Client({name:'information-fixture',version:'1'});
 const[a,b]=InMemoryTransport.createLinkedPair();await server.connect(a);await sdk.connect(b);t.after(async()=>{await sdk.close();await server.close();});
 assert.equal((await sdk.listTools()).tools.length,3);
 const read=await sdk.callTool({name:'festapp_information_inspect',arguments:{occasionId:7,informationId:12}});assert.equal(read.structuredContent.ok,true);assert.deepEqual(read.structuredContent.data,snapshot);
 const commandId=randomUUID(),args={occasionId:7,commandId,expectedVersion:2,information:{...information,description:'<p>2025 gallery</p>'}};
 const saved=await sdk.callTool({name:'festapp_information_save',arguments:args});assert.equal(saved.structuredContent.ok,true,JSON.stringify(saved));
 assert.deepEqual(f.calls.at(-1).args,{p_occasion:7,p_organization:1,p_unit:3,p_action:'save',p_payload:{expectedVersion:2,information:args.information},p_command_id:commandId});
});
test('native conflicts and stale receipt/foreign scope are not reported as successful saves',async()=>{
 const f=fixture(),args={occasionId:7,commandId:randomUUID(),expectedVersion:2,information};
 for(const[code,error]of[[409,'INFORMATION_CHANGED_RELOAD_REQUIRED'],[410,'COMMAND_EXPIRED_DO_NOT_REPLAY'],[404,'NOT_FOUND_OR_INACCESSIBLE']]){
  f.client.rpc=async()=>({data:{code}});await assert.rejects(invokeInformationOperation(f.owner,f.client,'information.save',args),{code:error});
 }
 f.client.rpc=async()=>({error:{code:'42501',status:403}});await assert.rejects(invokeInformationOperation(f.owner,f.client,'information.save',args),{code:'FORBIDDEN'});
 f.client.rpc=async()=>({data:{code:200,status:'applied',mutation:{commandId:randomUUID()},data:snapshot}});await assert.rejects(invokeInformationOperation(f.owner,f.client,'information.save',args),{code:'INFORMATION_REJECTED'});
});
test('HTTP API shares the canonical information owner, permission checks and conflict response',async t=>{
 let calls=0,conflict=false;
 const f=await setup(t,{apiPolicy:{allowedScopes:scope.split(' '),allowedOperations:informationDescriptors.map(d=>d.id)},fetchImpl:async(url,init)=>{
  if(!url.pathname.endsWith('/rpc/manage_information_authoring'))return;
  const args=JSON.parse(init.body);calls++;assert.equal(args.p_occasion,7);assert.equal(args.p_organization,1);
  if(args.p_action==='inspect')return reply(snapshot);
  if(conflict)return reply({code:409});
  return reply({code:200,status:'applied',mutation:{commandId:args.p_command_id,receiptId:args.p_command_id},data:{information:args.p_payload.information,aggregateVersion:3}});
 }});
 const{tokens}=await connect(f,{occasionIds:[7],scope});
 let response=await apiRequest(f,tokens,'information.inspect',{occasionId:7,informationId:12});assert.equal(response.status,200,await response.clone().text());assert.deepEqual((await response.json()).data,snapshot);
 const args={occasionId:7,commandId:randomUUID(),expectedVersion:2,information};
 response=await apiRequest(f,tokens,'information.save',args);assert.equal(response.status,200,await response.clone().text());
 conflict=true;response=await apiRequest(f,tokens,'information.save',{...args,commandId:randomUUID()});assert.equal(response.status,409);assert.equal((await response.json()).code,'INFORMATION_CHANGED_RELOAD_REQUIRED');
 const before=calls;
 response=await apiRequest(f,tokens,'information.inspect',{occasionId:8,informationId:12});assert.equal(response.status,403);assert.equal(calls,before);
 const read=await connect(f,{occasionIds:[7],scope:'festapp:ticket-layouts:read festapp:information:read'});
 response=await apiRequest(f,read.tokens,'information.save',args);assert.equal(response.status,403);assert.equal(calls,before);
});
