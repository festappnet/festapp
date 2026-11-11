import test from 'node:test';import assert from 'node:assert/strict';import { indexedDB } from 'fake-indexeddb';
import { ScannerStore } from '../../src/services/scanner_store.js';import { ScannerController } from '../../src/components/scan/scanner_controller.js';
const setup=async(api={lookup:async()=>({ticket_id:1,admission_allowed:true,source:'online',settings_revision:1,eligibility_fingerprint:'f'.repeat(64)})})=>{const store=await new ScannerStore({indexedDB,name:crypto.randomUUID()}).open();const row={partition:'p',session:{session_id:'s',offline_until:new Date(Date.now()+3600000).toISOString()},serverAt:Date.now(),wallAt:Date.now()};return new ScannerController({api,store,row,sync:{run:async()=>{}},online:()=>false});};
test('C01/C02 HID and all inputs only lookup; double click persists exactly once',async()=>{
 const c=await setup();c.online=()=>true;await c.loadCode('CODE');assert.equal((await c.store.list('outbox')).length,0);await Promise.all([c.confirm(),c.confirm()]);assert.equal((await c.store.list('outbox')).length,1);c.store.close();
});
test('stale lookup cannot overwrite a newer UI generation',async()=>{let resolve;const c=await setup({lookup:()=>new Promise(r=>{resolve=r;})});c.online=()=>true;const load=c.loadCode('A');c.dispose();resolve({ticket_id:1});await load;assert.equal(c.ticket,undefined);c.store.close();});
test('C17 reception payload and arbitrary URLs are never ticket inputs',async()=>{let called=false;const c=await setup({lookup:async()=>{called=true;}});await c.loadCode('festapp-login:v1:1:SECRET');await c.loadCode('https://external.invalid/');assert.equal(called,false);assert.equal(c.error,'wrong_mode');c.store.close();});
test('runtime quota failure never produces local pending success',async()=>{const c=await setup();c.online=()=>true;await c.loadCode('A');c.store.enqueue=async()=>{throw new Error('QuotaExceededError');};await c.confirm();assert.equal(c.state,'error');assert.equal(c.operation,null);c.store.close();});
test('network hint can be wrong: failed lookup reads a prepared snapshot',async()=>{const c=await setup({lookup:async()=>{throw Object.assign(new Error('network_error'),{code:0});}});c.online=()=>true;c.store.lookup=async()=>({ticket_id:9,symbol:'A',admission_allowed:true});await c.loadCode('A');assert.equal(c.ticket.source,'offline');assert.equal(c.state,'result');c.store.close();});

test('lookup reads durable pending operations while the network is in flight',async()=>{
 let resolveLookup,resolveOutbox,outboxStarted=false;
 const c=await setup({lookup:()=>new Promise(resolve=>{resolveLookup=resolve;})});c.online=()=>true;
 c.store.list=()=>{outboxStarted=true;return new Promise(resolve=>{resolveOutbox=resolve;});};
 const loading=c.loadCode('CODE');
 assert.equal(outboxStarted,true,'local pending checks must overlap network latency');
 const pending={key:'pending',state:'pending',payload:{ticket_id:1}};
 resolveOutbox([pending]);resolveLookup({ticket_id:1,symbol:'CODE',source:'online',admission_allowed:true});
 await loading;
 assert.equal(c.state,'pending');assert.equal(c.operation,pending,'pending admission cannot become confirmable again');c.store.close();
});

test('disposed lookup cannot publish a result after a slow outbox read',async()=>{
 let resolveOutbox,readingOutbox;
 const started=new Promise(resolve=>{readingOutbox=resolve;});
 const c=await setup();c.online=()=>true;
 c.store.list=()=>{readingOutbox();return new Promise(resolve=>{resolveOutbox=resolve;});};
 const loading=c.loadCode('CODE');await started;c.dispose();resolveOutbox([]);await loading;
 assert.notEqual(c.state,'result');assert.equal(c.ticket,undefined);c.store.close();
});

test('choosing another search result performs a fresh scoped lookup and ignores preview admission flags',async()=>{
 const c=await setup();c.online=()=>true;
 c.api.lookupTicket=async id=>({ticket_id:id,symbol:null,state:'storno',products:[],admission_allowed:false,source:'online'});
 await c.loadCode('FIRST');assert.equal(c.state,'result');
 await c.loadTicket({ticket_id:2,symbol:null,admission_allowed:true,state:'sent'});
 assert.equal(c.state,'result');assert.equal(c.ticket.ticket_id,2);assert.equal(c.ticket.state,'storno');assert.equal(c.ticket.admission_allowed,false);c.store.close();
});

test('offline search selection resolves ticket ID in the active snapshot partition',async()=>{
 const c=await setup();let requested;
 c.store.lookupTicket=async(partition,id)=>{requested=[partition,id];return {ticket_id:id,state:'storno',admission_allowed:false,products:[]};};
 await c.loadTicket({ticket_id:9,symbol:null});
 assert.deepEqual(requested,['p',9]);assert.equal(c.ticket.source,'offline');assert.equal(c.ticket.state,'storno');c.store.close();
});
