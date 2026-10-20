import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {ReservationCapabilityStore} from '../../src/components/forms/reservation_capability_store.js';
import {FormSession} from '../../src/components/forms/form_session.js';
import {DbForms} from '../../src/components/forms/db_forms.js';
import {createBrowserStorage} from '../../src/services/browser_storage.js';
const dom=new JSDOM('<html><body></body></html>',{url:'http://localhost'});
globalThis.window=dom.window;globalThis.document=dom.window.document;
const memory=()=>{const rows=new Map();return {getItem:key=>rows.get(key)??null,setItem:(key,value)=>rows.set(key,value),removeItem:key=>rows.delete(key),rows};};
const model=(secret='initial')=>({key:'form',secret,visibleFields:[],relatedFields:[{type:'ticket',data:{max_tickets:5}}]});
test('capability scopes backend/form, stores no draft and retains unknown server expiry',()=>{
 const storage=memory();const first=new ReservationCapabilityStore('http://backend','form',{storage});first.restore();
 const held=first.save('buyer',null);
 const recovered=new ReservationCapabilityStore('http://backend','form',{storage}).restore();
 assert.equal(recovered.secret,'buyer');assert.equal(recovered.expiresAt,null);
 assert.deepEqual(Object.keys(held).sort(),['expiresAt','generation','secret']);
 assert.equal(new ReservationCapabilityStore('http://other','form',{storage}).restore(),null);
 assert.equal(new ReservationCapabilityStore('http://backend','other',{storage}).restore(),null);
});
test('expiry clears without a new timeout and newer generations survive late completion',()=>{
 const storage=memory();const first=new ReservationCapabilityStore('backend','form',{storage,now:()=>1000});first.restore();
 first.save('expired','1970-01-01T00:00:00.500Z');
 const fresh=new ReservationCapabilityStore('backend','form',{storage,now:()=>1000});
 assert.equal(fresh.restore(),null);assert.equal(storage.rows.size,0);
 const submitted=fresh.save('buyer',null);const newer=fresh.save('buyer','2099-01-01T00:00:00Z');
 assert.equal(fresh.clear(submitted),false);
 assert.equal(new ReservationCapabilityStore('backend','form',{storage}).restore().generation,newer.generation);
 assert.equal(first.save('obsolete',null),null);
});
test('blocked sessionStorage uses existing memory fallback',()=>{
 const storage=createBrowserStorage(()=>{throw new Error('blocked');});
 const store=new ReservationCapabilityStore('backend','form',{storage});store.restore();store.save('buyer',null);
 assert.equal(new ReservationCapabilityStore('backend','form',{storage}).restore().secret,'buyer');
});
test('lost first hold response survives reload and authority restores payload and actual expiry',async t=>{
 const storage=memory();const first=new FormSession(model(),{backend:'backend',reservationStorage:storage});
 let reject;t.mock.method(DbForms,'selectSpot',()=>new Promise((_,fail)=>reject=fail));
 const pending=first.toggleSpotUnit([{id:11,title:'A',product:{price:100}}],true);await Promise.resolve();
 const reloaded=new FormSession(model('newly-generated'),{backend:'backend',reservationStorage:storage});
 assert.equal(reloaded.formModel.secret,'initial');assert.equal(reloaded.payload.ticket.length,0);
 reloaded.reconcileReservations([{id:11,title:'A',state:'selected_by_me',productModel:{price:100}}],{expiresAt:'2099-01-01T00:00:00Z'});
 assert.deepEqual(reloaded.payload.ticket.map(ticket=>ticket.spot),[11]);assert.equal(reloaded.reservationExpiresAt,'2099-01-01T00:00:00Z');
 reject(new Error('lost'));await assert.rejects(pending,/lost/);
 first.completeReservation(first.captureReservationCapability());
 assert.equal(new ReservationCapabilityStore('backend','form',{storage}).restore().expiresAt,'2099-01-01T00:00:00Z');
 reloaded.completeReservation(reloaded.captureReservationCapability());assert.equal(new ReservationCapabilityStore('backend','form',{storage}).restore(),null);
});
test('authoritative no-own-holds read retires cached capability and stale seat payload',()=>{
 const storage=memory();const form=new FormSession(model(),{backend:'backend',reservationStorage:storage});form.addTicket({spot:11,spotPrice:100});
 form.reconcileReservations([{id:11,state:'available'}],{});assert.equal(form.payload.ticket.length,0);assert.equal(storage.rows.size,0);
});

test('physical reload automatically reads authority before checkout and restores no stored seat state',async t=>{
 const storage=memory();const first=new FormSession(model(),{backend:'backend',reservationStorage:storage});
 let finish;
 t.mock.method(DbForms,'getBlueprint',async(secret,key,id)=>{assert.equal(secret,'initial');assert.equal(id,4);return new Promise(resolve=>finish=resolve);});
 const reloaded=new FormSession({...model('other'),blueprint:4},{backend:'backend',reservationStorage:storage});
 let ready=false;const checkout=reloaded.awaitPendingReservations().then(()=>ready=true);
 await Promise.resolve();assert.equal(ready,false);assert.equal(reloaded.payload.ticket.length,0);
 finish({layout:{nodes:[]},seatBindings:[{nodeId:'a',spotId:11,productId:7,title:'A'}],spots:[{id:11,state:'selected_by_me'}],products:[{id:7,price:100,currency_code:'CZK'}],expiresAt:'2099-01-01T00:00:00Z'});
 await checkout;assert.deepEqual(reloaded.payload.ticket.map(ticket=>ticket.spot),[11]);assert.equal(reloaded.reservationExpiresAt,'2099-01-01T00:00:00Z');
});
