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

Deno.test('native delivery failures provide readable instructions without leaking provider errors or capability',async()=>{
 const registry=new WalletRegistry([['third',()=>({...connector('third'),issue:async()=>{throw new Error('private provider failure');}})]],'third');
 const handler=walletHandler(registry,['https://tenant.invalid']);
 const res=await handler(new Request('https://api.invalid',{method:'POST',headers:{origin:'https://tenant.invalid','Content-Type':'application/x-www-form-urlencoded','Accept-Language':'cs-CZ'},body:new URLSearchParams({provider:'third',token:'a'.repeat(64)})}));
 assertEquals(res.status,503);assertEquals(res.headers.get('content-type'),'text/html; charset=utf-8');
 const text=await res.text();assertEquals(text.includes('Vstupenku se nepodařilo připravit'),true);assertEquals(text.includes('private provider failure'),false);assertEquals(text.includes('a'.repeat(64)),false);assertEquals(text.includes('wallet_retry'),false);
});

import { AuthError } from '../authError.ts';
import { syncTicketWalletHandler } from '../../sync-ticket-wallet/handler.ts';

const request = () => new Request('https://api.invalid/sync-ticket-wallet', {
  method: 'POST', body: JSON.stringify({requestSecret: 'private-secret'}),
});

Deno.test('wallet synchronization records the failed stage without leaking secrets or error messages', async () => {
  for (const stage of ['authorize', 'reconcile'] as const) {
    const logs: unknown[] = [];
    let reconciled = false;
    const handler = syncTicketWalletHandler({
      authorize: async () => { if (stage === 'authorize') throw new AuthError('private-secret', 403); },
      reconcile: async () => { reconciled = true; throw new TypeError('private provider URL and token'); },
      report: failure => logs.push(failure),
    });
    const response = await handler(request());
    assertEquals(response.status, 503);
    assertEquals(await response.json(), {error: 'wallet_sync_unavailable'});
    assertEquals(logs, [{stage, kind: stage === 'authorize' ? 'authorization' : 'type_error'}]);
    assertEquals(reconciled, stage === 'reconcile');
  }
});

Deno.test('wallet sync diagnostics cannot alter the response or replay an uncertain operation', async () => {
  let calls = 0;
  const handler = syncTicketWalletHandler({
    authorize: async () => {},
    reconcile: async () => { calls++; throw {name: 'private-secret', code: 'private-token'}; },
    report: () => { throw new Error('log sink failed'); },
  });
  const response = await handler(request());
  assertEquals(response.status, 503);
  assertEquals(calls, 1);
});

Deno.test('wallet sync keeps method, missing secret, malformed JSON and success behavior', async () => {
  const logs: unknown[] = [];
  let calls = 0;
  const handler = syncTicketWalletHandler({
    authorize: async () => {},
    reconcile: async () => { calls++; return {apple: {synced: 3, failed: 0}}; },
    report: failure => logs.push(failure),
  });
  assertEquals((await handler(new Request('https://api.invalid'))).status, 405);
  assertEquals((await handler(new Request('https://api.invalid', {method: 'POST', body: '{}'}))).status, 401);
  const malformed = await handler(new Request('https://api.invalid', {method: 'POST', body: '{'}));
  assertEquals(malformed.status, 503);
  assertEquals(logs, [{stage: 'parse', kind: 'syntax_error'}]);
  const success = await handler(request());
  assertEquals(success.status, 200);
  assertEquals(success.headers.get('cache-control'), 'no-store');
  assertEquals(await success.json(), {apple: {synced: 3, failed: 0}});
  assertEquals(calls, 1);
});
