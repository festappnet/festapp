import {assertEquals,assert,assertRejects} from 'jsr:@std/assert@1';
import {issueTicketWallet,reconcileTicketWallet} from './ticketWallet.ts';
import {GoogleWallet} from './googleWallet.ts';
import {walletHandler} from '../ticket-wallet/handler.ts';
Deno.test('endpoint rejects GET, foreign origin and arbitrary ticket ID before Google I/O',async()=>{
 let calls=0;const handler=walletHandler(async()=>{calls++;},async()=>{throw new Error('unexpected');},['https://tenant.invalid']);
 for(const [method,origin,body,status] of [['GET','https://tenant.invalid',null,405],['POST','https://foreign.invalid',{token:'a'.repeat(64)},403],['POST','https://tenant.invalid',{ticketId:9},400],['POST','https://tenant.invalid',{token:'a'.repeat(2048)},400]] as const){
  const res=await handler(new Request('https://backend.invalid',{method,headers:{origin},...(body?{body:JSON.stringify(body)}:{})}));assertEquals(res.status,status);assertEquals(res.headers.get('cache-control'),'no-store');
 }assertEquals(calls,0);
});
Deno.test('invalid payment and cross-origin capability never claim or expose ticket details',async()=>{
 const google={} as GoogleWallet;
 for(const resolved of [null,{webOrigin:'https://tenant.invalid',projection:{state:'INACTIVE'}},{webOrigin:'https://foreign.invalid',projection:{state:'ACTIVE'}}]) {
  let calls=0;const result=await issueTicketWallet('a'.repeat(64),'ip','https://tenant.invalid',async name=>{assertEquals(name,'resolve_ticket_wallet');calls++;return resolved;},google);assertEquals(result,null);assertEquals(calls,1);
 }
});
Deno.test('worker progresses over all pages, catches transport failure and conditionally completes claims',async()=>{
 let next=0;const finishes:any[]=[];const claims=[{ticketId:1,lease:'a',projection:{state:'ACTIVE'}},{ticketId:2,lease:'b',projection:{state:'INACTIVE'}},{ticketId:3,lease:'c',projection:{state:'COMPLETED'}}];
 const google={synchronize:async(_ids:any,p:any,before:any)=>{await before();if(p.state==='ACTIVE')throw new Error('timeout_after_remote_write');}} as GoogleWallet;
 const rpc=async(name:string,params:any)=>{
  if(name==='claim_ticket_wallet')return claims[next++]??null;
  if(name==='reserve_ticket_wallet_request')return 0;
  if(name==='finish_ticket_wallet'){finishes.push(params);return true;}
 };
 assertEquals(await reconcileTicketWallet(rpc,google,10),{synced:2,failed:1});assertEquals(finishes.map(x=>x.p_ok),[false,true,true]);
 assertEquals(finishes.map(x=>x.p_ticket),[1,2,3]);
});
Deno.test('a stale completion never returns a Save JWT',async()=>{
 let saved=false;
 const google={synchronize:async()=>{},saveUrl:async()=>{saved=true;return 'x';}} as unknown as GoogleWallet;
 const context={issuer:'1234',environment:'test',organization:1,occasion:2,ticketId:3,webOrigin:'https://tenant.invalid',projection:{state:'ACTIVE'}};
 await assertRejects(()=>issueTicketWallet('a'.repeat(64),'ip',context.webOrigin,async name=>name==='resolve_ticket_wallet'?context:name==='claim_ticket_wallet'?{...context,objectId:'1234.x',classId:'1234.c',lease:'lease'}:false,google));assert(!saved);
});
