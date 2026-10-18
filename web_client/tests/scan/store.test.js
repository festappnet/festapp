import test from 'node:test';import assert from 'node:assert/strict';import { indexedDB } from 'fake-indexeddb';
import { ScannerStore, offlineGrantValid } from '../../src/services/scanner_store.js';
const make=async(now)=>new ScannerStore({indexedDB,name:crypto.randomUUID(),now}).open();
const payload=id=>({operation_id:crypto.randomUUID(),ticket_id:id,origin_session_id:'s'});
test('C02/C03/C10/C16 durable enqueue survives close/reopen; duplicate ticket stays one operation',async()=>{
 const s=await make();const p=payload(1);await s.enqueue('p',p);const duplicate=await s.enqueue('p',payload(1));assert.equal(duplicate.key,p.operation_id);const name=s.name;s.close();const r=await new ScannerStore({indexedDB,name}).open();assert.equal((await r.list('outbox','p'))[0].payload.operation_id,p.operation_id);r.close();
});
test('C10 storage failure rejects, never reports a memory-backed commit',async()=>{const s=new ScannerStore({indexedDB:null});await assert.rejects(s.open(),/storage_unavailable/);await assert.rejects(s.enqueue('p',payload(1)),/storage_unavailable/);});
test('C15 expired lease takeover fences stale sender and terminal states',async()=>{
 let now=100;const s=await make(()=>now);const p=payload(2);await s.enqueue('p',p);const a=await s.claimLease('p','a',10);assert.equal(await s.claimLease('p','b'),null);now=111;const b=await s.claimLease('p','b');assert.equal(await s.updateOperation(p.operation_id,{state:'accepted'},a),false);await s.updateOperation(p.operation_id,{state:'accepted',receipt:{outcome:'accepted'}},b);await s.updateOperation(p.operation_id,{state:'sending'},b);assert.equal((await s.get('outbox',p.operation_id)).state,'accepted');s.close();
});
test('C09/C07 interrupted or corrupt snapshot preserves pointer; receipts never apply stale used overlay',async()=>{
 const s=await make();const raw=JSON.stringify([{ticket_id:1,symbol:'A',state:'sent'}]),digest=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw))).toString('hex');
 const m={schema_version:1,snapshot_id:'snapshot1',ticket_count:1,byte_count:new TextEncoder().encode(raw).length,expires_at:new Date(Date.now()+3600000).toISOString(),pages:[{index:0,digest}]};const page={page_index:0,payload_text:raw,digest};await s.activateSnapshot('p',m,[page]);await assert.rejects(s.activateSnapshot('p',{...m,snapshot_id:'broken'},[{...page,payload_text:'[]'}]),/digest/);assert.equal((await s.snapshot('p')).snapshot_id,'snapshot1');assert.equal((await s.lookup('p','A')).state,'sent');s.close();
});
test('C11 clock rollback and grant expiry fail closed without clearing queue',()=>{const row={serverAt:1000,wallAt:1000,session:{offline_until:new Date(5000).toISOString()}};assert.equal(offlineGrantValid(row,2000),true);assert.equal(offlineGrantValid(row,-1000),false);assert.equal(offlineGrantValid(row,6000),false);});
test('C07 matching receipt blocks old snapshot reuse, but never overlays a newer unused generation',async()=>{
 const s=await make();const partition='p';const activate=async(id,fingerprint,time)=>{const raw=JSON.stringify([{ticket_id:1,symbol:'A',state:'sent',admission_allowed:true,eligibility_fingerprint:fingerprint}]),digest=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw))).toString('hex');return s.activateSnapshot(partition,{schema_version:1,snapshot_id:id,server_time:time,expires_at:new Date(Date.now()+3600000).toISOString(),ticket_count:1,byte_count:new TextEncoder().encode(raw).length,pages:[{index:0,digest}]},[{page_index:0,payload_text:raw,digest}]);};
 await activate('old','f','2026-10-18T10:00:00Z');await s.put('outbox',{key:'op',partition,state:'accepted',payload:{ticket_id:1},receipt:{eligibility_fingerprint:'f',committed_at:'2026-10-18T11:00:00Z'}});assert.equal((await s.lookup(partition,'A')).state,'used');await activate('new','g','2026-10-18T12:00:00Z');assert.equal((await s.lookup(partition,'A')).state,'sent');assert.equal((await s.lookup(partition,'A')).admission_allowed,true);s.close();
});

test('offline guest data is encrypted at rest, survives restart, and rejects tampering',async()=>{
 const store=await make();
 const ticket={ticket_id:55,symbol:'PRIVATE-QR',purchaser_name:'Private purchaser',note:'Private note',state:'sent'};
 const raw=JSON.stringify([ticket]),digest=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw))).toString('hex');
 const manifest={schema_version:1,snapshot_id:'encrypted',ticket_count:1,byte_count:new TextEncoder().encode(raw).length,expires_at:new Date(Date.now()+3600000).toISOString(),pages:[{index:0,digest}]};
 await store.activateSnapshot('p',manifest,[{page_index:0,payload_text:raw,digest}]);
 let encrypted;await store.transaction(['tickets'],'readonly',s=>{s.tickets.getAll().onsuccess=e=>{encrypted=e.target.result[0];};});
 assert.equal(encrypted.ticket,undefined);assert.ok(encrypted.ciphertext instanceof ArrayBuffer);assert.equal((await store.cacheKey()).extractable,false);
 const name=store.name;store.close();const reopened=await new ScannerStore({indexedDB,name}).open();assert.equal((await reopened.lookup('p','PRIVATE-QR')).purchaser_name,'Private purchaser');
 new Uint8Array(encrypted.ciphertext)[0]^=1;
 await reopened.transaction(['tickets'],'readwrite',s=>s.tickets.put(encrypted));
 await assert.rejects(reopened.lookup('p','PRIVATE-QR'),/offline_storage_unavailable/);reopened.close();
});

test('legacy plaintext cache upgrades without removing pending admissions',async()=>{
 const name=crypto.randomUUID();
 const old=await new Promise((resolve,reject)=>{const request=indexedDB.open(name,1);request.onupgradeneeded=()=>{for(const key of ['sessions','snapshots','tickets','outbox','receipts','preferences','sync_leases'])request.result.createObjectStore(key,{keyPath:'key'});};request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});
 await new Promise((resolve,reject)=>{const tx=old.transaction(['tickets','outbox'],'readwrite');tx.objectStore('tickets').put({key:'legacy:1',partition:'legacy',snapshot_id:'old',ticket:{ticket_id:1,symbol:'LEGACY',purchaser_name:'Old private name'}});tx.objectStore('outbox').put({key:'pending',partition:'legacy',state:'pending',payload:{ticket_id:1}});tx.oncomplete=resolve;tx.onerror=reject;});old.close();
 const store=await new ScannerStore({indexedDB,name}).open();let raw;
 await store.transaction(['tickets'],'readonly',s=>{s.tickets.get('legacy:1').onsuccess=e=>{raw=e.target.result;};});
 assert.equal(raw.ticket,undefined);assert.equal(raw.encrypted,1);assert.equal((await store.get('tickets','legacy:1')).ticket.purchaser_name,'Old private name');assert.equal((await store.get('outbox','pending')).state,'pending');store.close();
});
