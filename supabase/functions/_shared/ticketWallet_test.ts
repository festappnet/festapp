import {assertEquals,assert,assertRejects} from 'jsr:@std/assert@1';
import {issueTicketWallet,reconcileTicketWallet} from './wallet/connectors/google.ts';
import {GoogleWallet} from './googleWallet.ts';
import {WalletRegistry} from './wallet/registry.ts';
import {googleWalletConnector} from './wallet/connectors/google.ts';
import {walletHandler} from '../ticket-wallet/handler.ts';
Deno.test('endpoint rejects GET, foreign origin and arbitrary ticket ID before Google I/O',async()=>{
 let calls=0;const handler=walletHandler(new WalletRegistry([['google',()=>googleWalletConnector(async()=>{calls++;},async()=>{throw new Error('unexpected');})]],'google'),['https://tenant.invalid']);
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
Deno.test('first issuance drains approved class work before claiming the object and signing Save',async()=>{
 const context={issuer:'1234',environment:'test',organization:1,occasion:2,ticketId:3,webOrigin:'https://tenant.invalid',projection:{state:'ACTIVE'}};
 const order:string[]=[];let claims=0;
 const google={synchronizeClass:async()=>{order.push('class');},synchronize:async()=>{order.push('object');},saveUrl:async()=>{order.push('save');return 'url';}} as unknown as GoogleWallet;
 const rpc=async(name:string)=>{
  if(name==='resolve_ticket_wallet')return context;
  if(name==='claim_ticket_wallet')return {...context,kind:claims++===0?'class':'object',objectId:'1234.o',classId:'1234.c',lease:crypto.randomUUID()};
  if(name==='finish_ticket_wallet')return true;
 };
 assertEquals((await issueTicketWallet('a'.repeat(64),'ip',context.webOrigin,rpc,google))?.url,'url');
 assertEquals(order,['class','object','save']);
});

Deno.test('Google collections partition actual URL length, synchronize only planned members and fence late revocation',async()=>{
 const items=Array.from({length:5},(_,i)=>({issuer:'1234',environment:'test',organization:1,occasion:2,ticketId:i+1,projection:{state:'ACTIVE'}}));
 const scope={...items[0],kind:'collection',webOrigin:'https://tenant.invalid',providers:{google:true},state:'ACTIVE',revision:'b'.repeat(64),tickets:items,ticketCount:5,originalCount:5};
 const claims:number[]=[],saved:string[][]=[];let changed=false;
 const google={saveUrl:async(ids:string|string[])=>{const all=Array.isArray(ids)?ids:[ids];if(all.length>2)throw new Error('wallet_link_length');saved.push(all);return 'https://pay.google.com/gp/v/save/a.b.c';},synchronize:async()=>{}} as unknown as GoogleWallet;
 const rpc=async(name:string,p:any)=>{
  if(name==='resolve_ticket_wallet')return changed?{...scope,revision:'c'.repeat(64)}:scope;
  if(name==='get_ticket_wallet_projections')return items.filter(item=>p.p_tickets.includes(item.ticketId));
  if(name==='claim_ticket_wallet'){claims.push(p.p_ticket);return {...items[p.p_ticket-1],objectId:'1234.o'+p.p_ticket,classId:'1234.c',lease:'lease'};}
  if(name==='finish_ticket_wallet')return true;
 };
 const connector=googleWalletConnector(rpc,async()=>google);const input={token:'a'.repeat(64),source:'ip',origin:scope.webOrigin};
 const plan=await connector.plan!(input);assertEquals(plan?.parts,[2,2,1]);assertEquals(claims,[]);
 assertEquals(await connector.issue(input),null);
 const result=await connector.issue({...input,revision:plan!.revision,part:1});assert(result?.kind==='redirect');assertEquals(claims,[3,4]);assertEquals(saved.at(-1),['1234.o3','1234.o4']);
 google.synchronize=async()=>{changed=true;};assertEquals(await connector.issue({...input,revision:plan!.revision,part:2}),null);
});
Deno.test('HTTP collection planning validates part/revision/action and duplicate form fields before provider work',async()=>{
 let calls=0;
 const connector:any={id:'apple',delivery:'file',plan:async()=>{calls++;return {kind:'collection',revision:'b'.repeat(64),ticketCount:2,originalCount:2,parts:[2],state:'ACTIVE'};},issue:async()=>{calls++;return null;}};
 const handler=walletHandler(new WalletRegistry([['apple',()=>connector]],'apple'),['https://tenant.invalid']);
 for(const extra of [{part:-1},{part:1.2},{part:'1'},{revision:'short'},{action:'other'},{ticketIds:[1,2]}]){
  const response=await handler(new Request('https://api.invalid',{method:'POST',headers:{origin:'https://tenant.invalid'},body:JSON.stringify({token:'a'.repeat(64),...extra})}));assertEquals(response.status,400);
 }
 const duplicate=new URLSearchParams({token:'a'.repeat(64),provider:'apple',part:'0'});duplicate.append('part','1');
 assertEquals((await handler(new Request('https://api.invalid',{method:'POST',headers:{origin:'https://tenant.invalid','Content-Type':'application/x-www-form-urlencoded'},body:duplicate}))).status,400);assertEquals(calls,0);
 const response=await handler(new Request('https://api.invalid',{method:'POST',headers:{origin:'https://tenant.invalid'},body:JSON.stringify({token:'a'.repeat(64),action:'plan'})}));assertEquals(response.status,200);assertEquals((await response.json()).parts,[2]);assertEquals(calls,1);
});
