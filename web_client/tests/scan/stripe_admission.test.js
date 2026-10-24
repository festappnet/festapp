import test from 'node:test';
import assert from 'node:assert/strict';
import {indexedDB} from 'fake-indexeddb';
import {ScannerStore} from '../../src/services/scanner_store.js';
import {ScannerController} from '../../src/components/scan/scanner_controller.js';
test('A19 offline cache retains bank ticket and refuses a card ticket',async()=>{
  const store=await new ScannerStore({indexedDB,name:crypto.randomUUID()}).open();
  try{
    const tickets=[{ticket_id:1,symbol:'BANK',state:'sent'},{ticket_id:2,symbol:'CARD',state:'sent',admission_allowed:true,online_required:true}];
    const raw=JSON.stringify(tickets),digest=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw))).toString('hex');
    await store.activateSnapshot('p',{schema_version:1,snapshot_id:'fixture',ticket_count:2,byte_count:new TextEncoder().encode(raw).length,expires_at:new Date(Date.now()+3600000).toISOString(),pages:[{index:0,digest}]},[{page_index:0,payload_text:raw,digest}]);
    assert.equal((await store.lookup('p','BANK')).symbol,'BANK');
    await assert.rejects(()=>store.lookup('p','CARD'),/online_required/);
  }finally{store.close();}
});
test('A19 connection loss after card lookup cannot create an offline admission',async()=>{
  let online=true,enqueued=0;
  const controller=new ScannerController({api:{lookup:async()=>({ticket_id:2,symbol:'CARD',state:'sent',source:'online',admission_allowed:true,online_required:true})},
    store:{list:async()=>[],enqueue:async()=>{enqueued++;}},row:{},sync:{run:async()=>{}},online:()=>online});
  await controller.loadCode('CARD');online=false;await controller.confirm();
  assert.equal(enqueued,0);assert.equal(controller.state,'error');assert.equal(controller.error,'online_required');assert.equal(controller.offlineReady,false);
});
