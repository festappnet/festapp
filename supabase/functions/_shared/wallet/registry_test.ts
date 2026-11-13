import {assertEquals,assertThrows,assertRejects} from 'jsr:@std/assert@1';
import {WalletRegistry} from './registry.ts';
import type {WalletConnector} from './contracts.ts';
import {walletHandler} from '../../ticket-wallet/handler.ts';
const connector=(id:string):WalletConnector=>({id,delivery:'file',issue:async()=>({kind:'file',bytes:new Uint8Array([80,75]),contentType:'application/vnd.apple.pkpass',filename:'ticket.pkpass'}),reconcile:async()=>({synced:1,failed:0})});
Deno.test('Wallet registry rejects unknown/mismatched/duplicate bindings without implicit provider fallback',()=>{
 assertThrows(()=>new WalletRegistry([['test',()=>connector('test')],['test',()=>connector('test')]],'test'));
 assertThrows(()=>new WalletRegistry([['test',()=>connector('test')]],'missing'));
 const registry=new WalletRegistry([['test',()=>connector('other')]],'test');assertThrows(()=>registry.resolve('test'));assertThrows(()=>registry.resolve('unknown'));
});
Deno.test('a registered connector works through the common HTTP contract without provider branches',async()=>{
 let calls=0;
 const registry=new WalletRegistry([['third',()=>({...connector('third'),issue:async input=>{calls++;assertEquals(input.token,'a'.repeat(64));return {kind:'file',bytes:new Uint8Array([80,75]),contentType:'application/vnd.apple.pkpass',filename:'ticket.pkpass'};}})]],'third');
 const handler=walletHandler(registry,['https://tenant.invalid']);
 const res=await handler(new Request('https://api.invalid',{method:'POST',headers:{origin:'https://tenant.invalid','Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({provider:'third',token:'a'.repeat(64)})}));
 assertEquals(res.status,200);assertEquals(new Uint8Array(await res.arrayBuffer()),new Uint8Array([80,75]));assertEquals(calls,1);
 const rejected=await handler(new Request('https://api.invalid',{method:'POST',headers:{origin:'https://tenant.invalid'},body:JSON.stringify({provider:'unknown',token:'a'.repeat(64)})}));assertEquals(rejected.status,400);assertEquals(calls,1);
});
Deno.test('one unavailable provider cannot stop another providers reconciliation',async()=>{
 const bad=()=>({...connector('bad'),reconcile:async()=>{throw new Error('unconfigured');}});
 const registry=new WalletRegistry([['bad',bad],['healthy',()=>connector('healthy')]],'healthy');
 assertEquals(await registry.reconcile(),{bad:{error:'wallet_sync_unavailable'},healthy:{synced:1,failed:0}});
 await assertRejects(()=>new WalletRegistry([['bad',bad]],'bad').reconcile());
});
