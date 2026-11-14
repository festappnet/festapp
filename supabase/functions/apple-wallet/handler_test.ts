import {assertEquals,assert} from 'jsr:@std/assert@1';
import {appleWalletHandler} from './handler.ts';
import {sealEmail} from '../_shared/emailPayload.ts';
import {walletHash} from '../_shared/wallet/identity.ts';
import type {AppleWallet} from '../_shared/appleWallet.ts';
const origin='https://api.festapp.net/functions/v1/apple-wallet/v1/';
const serial='festapp_'+'a'.repeat(64),device='device-library-identifier',passType='pass.net.festapp.test',token='c'.repeat(64);
Deno.test('Apple service authenticates pass reads and registrations; device polls are scoped and native statuses preserved',async()=>{
 const calls:any[]=[];
 const handler=appleWalletHandler(async(name,p)=>{calls.push([name,p]);if(name==='allow_apple_wallet_request')return true;if(name==='register_apple_wallet_device')return p?.p_auth_hash===await walletHash(token)?p?.p_remove?200:201:401;if(name==='list_apple_wallet_updates')return p?.p_device===device?{serialNumbers:[serial],lastUpdated:'9'}:null;return null;},async()=>{throw new Error('must not sign');});
 const register=origin+'devices/'+device+'/registrations/'+passType+'/'+serial;
 assertEquals((await handler(new Request(register,{method:'POST',body:JSON.stringify({pushToken:'d'.repeat(64)})}))).status,401);
 assertEquals((await handler(new Request(register,{method:'POST',headers:{authorization:'ApplePass '+token},body:JSON.stringify({pushToken:'d'.repeat(64)})}))).status,201);
 assertEquals((await handler(new Request(register,{method:'DELETE',headers:{authorization:'ApplePass '+token}}))).status,200);
 const poll=await handler(new Request(origin+'devices/'+device+'/registrations/'+passType+'?passesUpdatedSince=3'));
 assertEquals(poll.status,200);assertEquals((await poll.json()).serialNumbers,[serial]);
 assertEquals((await handler(new Request(origin+'devices/foreign-device-123/registrations/'+passType))).status,204);
 assertEquals((await handler(new Request(origin+'passes/'+passType+'/'+serial))).status,401);
 assert(calls.some(([name,p])=>name==='list_apple_wallet_updates'&&p.p_since==='3'));
});
Deno.test('Apple update serves authenticated voided pass with stable auth and supports conditional GET',async()=>{
 Deno.env.set('EMAIL_PAYLOAD_KEY',btoa('a'.repeat(32)));
 try {
  const context={serial,ticketId:1,environment:'test',organization:1,occasion:2,passTypeIdentifier:passType,teamIdentifier:'TESTTEAM01',updateTag:'9',updatedAt:'2026-11-13T12:00:00Z',projection:{state:'INACTIVE'},authHash:await walletHash(token),authSealed:await sealEmail({purpose:'apple_wallet_auth',serial,passTypeIdentifier:passType,token})};
  const apple={credentials:{passTypeIdentifier:passType,teamIdentifier:'TESTTEAM01'},issue:async(_id:any,p:any,options:any)=>{assertEquals(p.state,'INACTIVE');assertEquals(options.authenticationToken,token);return new Uint8Array([80,75]);}} as unknown as AppleWallet;
  const handler=appleWalletHandler(async(name,p)=>name==='allow_apple_wallet_request'?true:name==='get_apple_ticket_wallet'&&p?.p_auth_hash===context.authHash?context:null,async()=>apple);
  const url=origin+'passes/'+passType+'/'+serial;
  const res=await handler(new Request(url,{headers:{authorization:'ApplePass '+token}}));assertEquals(res.status,200);assertEquals(res.headers.get('content-type'),'application/vnd.apple.pkpass');assertEquals(res.headers.get('etag'),'"9"');
  assertEquals((await handler(new Request(url,{headers:{authorization:'ApplePass '+token,'If-None-Match':'"9"'}}))).status,304);
  assertEquals((await handler(new Request(url,{headers:{authorization:'ApplePass '+token,'If-Modified-Since':context.updatedAt}}))).status,304);
 }finally{Deno.env.delete('EMAIL_PAYLOAD_KEY');}
});
Deno.test('Apple service bounds incoming logs, malformed encoding and source rate before ticket lookup',async()=>{
 const handler=appleWalletHandler(async()=>true,async()=>{throw new Error('must not sign');});
 assertEquals((await handler(new Request(origin+'log',{method:'POST',body:JSON.stringify({logs:['x'.repeat(17000)]})}))).status,400);
 assertEquals((await handler(new Request(origin+'passes/%ZZ/x'))).status,400);
 const limited=appleWalletHandler(async()=>false,async()=>{throw new Error();});assertEquals((await limited(new Request(origin+'passes/'+passType+'/'+serial))).status,429);
});
