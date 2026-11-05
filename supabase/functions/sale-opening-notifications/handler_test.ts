import assert from 'node:assert/strict';
import {saleOpeningHandler as protectedHandler, saleOpeningHash} from './handler.ts';
const saleOpeningHandler = (rpc: Parameters<typeof protectedHandler>[0], seal?: Parameters<typeof protectedHandler>[1]) => protectedHandler(rpc,seal,{publicConfig:()=>({siteKey:'fixture',action:'sale_opening_subscribe'}),verify:async()=>true});
Deno.test('scanner GET and oversized streamed POST never reach a mutation',async()=>{
 let calls=0;
 const handler=saleOpeningHandler(async()=>{calls++;return {data:{ok:true},error:null};});
 assert.equal((await handler(new Request('https://local.test',{method:'GET'}))).status,405);
 assert.equal((await handler(new Request('https://local.test',{method:'POST',body:'x'.repeat(4097)}))).status,413);
 assert.equal(calls,0);
});
Deno.test('subscribe accepts only explicit contact shape; SQL receives encrypted sources and hashes',async()=>{
 let mutation: Record<string,any>|null=null;
 const handler=saleOpeningHandler(async(name,args)=>{if(name==='sale_opening_notification_command')mutation=args;return {data:{ok:true},error:null};},async()=>({v:'1',iv:'fixture',ciphertext:'cipher'.repeat(10)}));
 const request=(value: unknown)=>new Request('https://local.test',{method:'POST',body:JSON.stringify(value)});
 assert.equal((await handler(request({operation:'subscribe',formLink:'ples',email:'jana@example.com',lang:'cs'}))).status,200);
 assert.ok(mutation);
 const payload=(mutation as Record<string,any>).p_payload;
 assert.match(payload.unsubscribe.hash,/^[0-9a-f]{64}$/);assert.equal(payload.confirm,undefined);
 assert.equal(payload.unsubscribe.envelope.ciphertext,'cipher'.repeat(10));assert.equal(JSON.stringify(payload).includes('token"'),false);
 assert.equal((await handler(request({operation:'subscribe',formLink:'ples',email:'bad',lang:'cs'}))).status,400);
 assert.equal((await handler(request({operation:'destroy',token:'a'.repeat(64)}))).status,400);
});
Deno.test('explicit POST hashes capability and reports controlled rate errors without echoing tokens',async()=>{
 const token='a'.repeat(64);
 const handler=saleOpeningHandler(async(name,args)=>{
  if(name==='sale_opening_notification_command'){assert.equal(args.p_operation,'unsubscribe');assert.deepEqual(args.p_payload,{tokenHash:await saleOpeningHash(token)});}
  return {data:null,error:{code:'PT429'}};
 });
 const result=await handler(new Request('https://local.test',{method:'POST',body:JSON.stringify({operation:'unsubscribe',token})}));
 assert.equal(result.status,429);assert.equal((await result.text()).includes(token),false);
});
Deno.test('encryption failure prevents subscription transaction',async()=>{
 let calls=0;
 const handler=saleOpeningHandler(async()=>{calls++;return {data:{ok:true},error:null};},async()=>{throw new Error('key missing');});
 const result=await handler(new Request('https://local.test',{method:'POST',body:JSON.stringify({operation:'subscribe',formLink:'ples',email:'jana@example.com',lang:'cs'})}));
 assert.equal(result.status,503);assert.equal(calls,0);
});
Deno.test('invalid and expired capabilities expose only the controlled invalid-link state',async()=>{
 const handler=saleOpeningHandler(async()=>({data:null,error:{code:'22023'}}));
 const result=await handler(new Request('https://local.test',{method:'POST',body:JSON.stringify({operation:'unsubscribe',token:'a'.repeat(64)})}));
 assert.equal(result.status,400);assert.deepEqual(await result.json(),{error:'invalid_link'});
});

Deno.test('public commands never wake the shared worker and removed confirmation is rejected',async()=>{
 const calls: string[]=[];
 const handler=saleOpeningHandler(async(name)=>{calls.push(name);return {data:{ok:true},error:null};},async()=>({v:'1',ciphertext:'x'.repeat(48)}));
 for (const body of [{operation:'subscribe',formLink:'ples',email:'jana@example.com',lang:'cs'},{operation:'unsubscribe',token:'a'.repeat(64)}]) {
  assert.equal((await handler(new Request('https://local.test',{method:'POST',body:JSON.stringify(body)}))).status,200);
 }
 assert.deepEqual(calls,['sale_opening_notification_command','sale_opening_notification_command']);
 assert.equal((await handler(new Request('https://local.test',{method:'POST',body:JSON.stringify({operation:'confirm',token:'a'.repeat(64)})}))).status,400);
 assert.equal(calls.length,2);
});

Deno.test('bot rejection and verifier outage cannot mutate contacts; config exposes no secret',async()=>{
 let calls=0;
 const rpc=async()=>{calls++;return {data:{ok:true},error:null};};
 const request=(body:unknown)=>new Request('https://local.test',{method:'POST',body:JSON.stringify(body)});
 const body={operation:'subscribe',formLink:'ples',email:'jana@example.com',lang:'cs'};
 const guard={publicConfig:()=>({siteKey:'public',action:'sale_opening_subscribe'}),verify:async()=>false};
 assert.equal((await protectedHandler(rpc,undefined,guard)(request(body))).status,400);
 assert.equal(calls,0);
 const unavailable={...guard,verify:async()=>{throw new Error('offline');}};
 assert.equal((await protectedHandler(rpc,undefined,unavailable)(request(body))).status,503);
 assert.equal(calls,0);
 const config=await protectedHandler(rpc,undefined,guard)(request({operation:'protection'}));
 assert.deepEqual(await config.json(),{ok:true,siteKey:'public',action:'sale_opening_subscribe'});
 assert.equal(calls,0);
});
