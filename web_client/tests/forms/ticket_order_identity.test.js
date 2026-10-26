import test from 'node:test';
import assert from 'node:assert/strict';
import {claimTicketOrderIdentity,terminalOrderResponse} from '../../src/components/eshop/ticket_order_identity.js';
function storage(){const data=new Map();return {data,getItem:k=>data.get(k),setItem:(k,v)=>data.set(k,v),removeItem:k=>data.delete(k)};}
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
