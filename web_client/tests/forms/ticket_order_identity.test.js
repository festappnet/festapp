import test from 'node:test';
import assert from 'node:assert/strict';
import {canonicalCommandPayload,claimTicketOrderIdentity,terminalOrderResponse} from '../../src/components/eshop/ticket_order_identity.js';
function storage(){const data=new Map();return {data,getItem:k=>data.get(k),keys:prefix=>[...data.keys()].filter(key=>key.startsWith(prefix)),setItem:(k,v)=>data.set(k,v),removeItem:k=>data.delete(k)};}
test('same semantic order replays opaque identity without persisting customer input',async()=>{
 const s=storage(),a=await claimTicketOrderIdentity('https://one',{form:'f',email:'person@example.invalid',ticket:[{b:2,a:1}]},null,s);
 const b=await claimTicketOrderIdentity('https://one',{ticket:[{a:1,b:2}],email:'person@example.invalid',form:'f'},null,s);
 assert.equal(a.commandId,b.commandId);assert.equal(a.clientId,b.clientId);
 assert.ok(!JSON.stringify([...s.data]).includes('person@example.invalid'));
 assert.notEqual((await claimTicketOrderIdentity('https://two',{form:'f',email:'person@example.invalid',ticket:[{b:2,a:1}]},null,s)).commandId,a.commandId);
 await assert.rejects(claimTicketOrderIdentity('https://one',{form:'f',email:'person@example.invalid',ticket:[{b:2,a:1}]},'new-user',s),/PRINCIPAL_CHANGED/);
 a.complete();assert.equal(s.data.size,1);
});
test('missing domain response, throttling and server errors do not release identity',()=>{
 for(const value of [null,{}, {code:202},{code:408},{code:429},{code:500},{code:503}])assert.equal(terminalOrderResponse(value),false);
 for(const code of [200,400,409,1013,1017])assert.equal(terminalOrderResponse({code}),true);
});
test('renewed checkout provenance replays the original payload until the outcome is terminal',async()=>{
 const s=storage(),purchase={form:'f',email:'person@example.invalid',ticket:[]};
 const first=await claimTicketOrderIdentity('https://one',{...purchase,checkoutOrigin:'original-proof'},null,s);
 const retry=await claimTicketOrderIdentity('https://one',{...purchase,checkoutOrigin:'renewed-proof'},null,s);
 assert.equal(retry.commandId,first.commandId);
 assert.deepEqual(retry.orderDetails,first.orderDetails);
 assert.equal(retry.orderDetails.checkoutOrigin,'original-proof');
 assert.ok(!JSON.stringify([...s.data]).includes(purchase.email));
 retry.complete();
 const next=await claimTicketOrderIdentity('https://one',{...purchase,checkoutOrigin:'renewed-proof'},null,s);
 assert.notEqual(next.commandId,first.commandId);
 assert.equal(next.orderDetails.checkoutOrigin,'renewed-proof');
});
test('an uncertain ordinary purchase cannot acquire a new origin on retry',async()=>{
 const s=storage(),purchase={form:'f',ticket:[]};
 const first=await claimTicketOrderIdentity('https://one',purchase,null,s);
 const retry=await claimTicketOrderIdentity('https://one',{...purchase,checkoutOrigin:'new-proof'},null,s);
 assert.equal(retry.commandId,first.commandId);
 assert.deepEqual(retry.orderDetails,purchase);
});

test('discount recovery requires the original pending identity and never allocates a replacement',async()=>{
 const s=storage(),payload={form:'f',ticket:[],discount:{code:'LAST',fingerprint:'a'.repeat(64)}};
 const first=await claimTicketOrderIdentity('https://one',payload,'buyer',s);
 const retry=await claimTicketOrderIdentity('https://one',payload,'buyer',s,{requirePending:true});
 assert.equal(retry.commandId,first.commandId);assert.equal(retry.clientId,first.clientId);
 await assert.rejects(claimTicketOrderIdentity('https://one',{...payload,discount:{code:'OTHER',fingerprint:'b'.repeat(64)}},'buyer',s,{requirePending:true}),/RECOVERY_REQUIRED/);
 assert.equal(s.data.size,1);
 first.complete();await assert.rejects(claimTicketOrderIdentity('https://one',payload,'buyer',s,{requirePending:true}),/RECOVERY_REQUIRED/);
 assert.equal(s.data.size,0);
});

test('a reloaded paid checkout recovers the original command even when Meta matching changes',async()=>{
 const s=storage(),purchase={form:'f',ticket:[],metaPurchaseConsent:{source:'klaro',capturedAt:'2026-11-18T00:00:00.000Z'}};
 const before=await claimTicketOrderIdentity('https://one',purchase,null,s);
 const first=await claimTicketOrderIdentity('https://one',{...purchase,metaPurchaseConsent:{...purchase.metaPurchaseConsent,matching:{fbc:'fb.1.1795000000000.sameClick'}}},null,s);
 const retry=await claimTicketOrderIdentity('https://one',{...purchase,metaPurchaseConsent:{...purchase.metaPurchaseConsent,matching:{fbc:'fb.1.1795000001000.sameClick'}}},null,s,{requirePending:true});
 assert.equal(first.commandId,before.commandId,'matching does not change identity for an existing pending order');
 assert.equal(retry.commandId,first.commandId);
 assert.equal(s.data.size,1);
 assert.match(retry.orderDetails.metaPurchaseConsent.matching.fbc,/1795000001000/);
 assert.doesNotMatch(JSON.stringify([...s.data]),/sameClick/);
});

test('same checkout retains its command after Meta consent disappears, changes, or returns',async()=>{
 const s=storage(),purchase={form:'f',ticket:[]};
 const first=await claimTicketOrderIdentity('https://one',{...purchase,metaPurchaseConsent:{timestamp:'original'}},null,s);
 for(const payload of [purchase,{...purchase,metaPurchaseConsent:{capturedAt:'new',decidedAt:'2026-11-18T00:00:00.000Z',transportExpiresAt:2345}},{...purchase,metaPurchaseConsent:null}]) {
  const retry=await claimTicketOrderIdentity('https://one',payload,null,s);
  assert.equal(retry.commandId,first.commandId);
  assert.equal(retry.clientId,first.clientId);
 }
 assert.equal(s.data.size,1);
 assert.doesNotMatch(JSON.stringify([...s.data]),/original/);
});


test('exact legacy consent recovers its old command and an unknown legacy purchase cannot create another',async()=>{
 const s=storage(),endpoint='https://one',purchase={form:'f',ticket:[],metaPurchaseConsent:{timestamp:'original'}};
 const input=JSON.stringify(canonicalCommandPayload([endpoint,purchase.form,purchase]));
 const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(input));
 const key='client_command_pending:ticket_order:'+Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
 s.setItem(key,JSON.stringify({commandId:'older-command',clientId:'older-client',principal:'buyer'}));
 const retry=await claimTicketOrderIdentity(endpoint,purchase,'buyer',s);
 assert.equal(retry.commandId,'older-command');
 await assert.rejects(claimTicketOrderIdentity(endpoint,{form:'f',ticket:[]},'buyer',s),/PAYMENT_RECOVERY_REQUIRED/);
 assert.equal(s.data.size,1);
 retry.complete();
 assert.notEqual((await claimTicketOrderIdentity(endpoint,{form:'f',ticket:[]},'buyer',s)).commandId,'older-command');
});
