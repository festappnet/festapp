import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const { ScanPage } = await import('../../src/components/scan/scan_page.js');

test('lookup, errors and receipts preserve the live camera; leaving scanner stops it', () => {
    const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
    const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
    globalThis.document=dom.window.document;
    Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
    try {
        const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
        page.route={page:'scan'};page.mode='camera';page.storageAvailable=true;
        page.row={session:{title:'Fixture',capabilities:{},settings:{fields:[]}}};
        page.controller={state:'ready'};
        let stops=0,plays=0;
        const video=document.createElement('video');video.play=async()=>{plays++;};
        const stream={getVideoTracks:()=>[{getCapabilities:()=>({torch:false})}]};
        page.input={video,stream,stop(){stops++;this.stream=null;}};
        page.render();
        page.summary={used_current:2,eligible_total:10};page.render();
        assert.equal(page.host.querySelector('video'),video);
        assert.equal(page.input.stream,stream);
        assert.equal(stops,0,'a summary update must not revoke the camera stream');
        assert.equal(plays,2,'reattached video resumes playback');
        assert.equal(page.host.querySelector('.scan-camera').dataset.active,'true');
        assert.equal(page.host.querySelector('[data-torch]').hidden,true);
        for(const state of ['looking_up','error','pending','accepted']) {
            page.controller={state,...(state==='error'?{error:'not_found'}:{})};page.render();
            assert.equal(page.host.querySelector('video'),video,`${state} keeps the same live preview`);
            assert.equal(page.input.stream,stream);
            assert.equal(stops,0,`${state} must not stop camera tracks`);
        }
        assert.equal(page.host.querySelector('.scan-group'),null,'there is no accumulating scanned-ticket list');
        page.route={page:'history'};page.render();
        assert.equal(stops,1,'leaving scanner releases camera tracks');
    } finally {
        dom.window.close();globalThis.document=previous.document;
        Object.defineProperty(globalThis,'navigator',previous.navigator);
    }
});

test('switching input preserves review; deliberately starting another ticket focuses manual search',async()=>{
    const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
    const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
    globalThis.document=dom.window.document;
    Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
    try {
        const page=new ScanPage(document.getElementById('scanner'),{client:{},store:{list:async()=>[]}});
        page.route={page:'scan'};page.storageAvailable=true;
        page.row={partition:'fixture',session:{title:'Fixture',capabilities:{},settings:{fields:[]}}};
        page.input={stream:null,stop(){},pause(){},paused:true};
        const lookups=[];
        page.api={lookup:async symbol=>{lookups.push(symbol);return {symbol,ticket_id:1,holder_name:'Fixture',products:[],fields:[],admission_allowed:true,source:'online',state:'sent'};}};
        page.controller=page.createController();
        await page.controller.loadCode('PREVIOUS');
        page.host.querySelector('[data-mode=manual]').click();
        assert.equal(page.controller.ticket.symbol,'PREVIOUS','switching inputs does not discard the active ticket');
        page.host.querySelector('[data-next-mode=manual]').click();
        const input=page.host.querySelector('[name=query]');
        assert.equal(input.disabled,false);assert.equal(input.value,'');
        assert.equal(document.activeElement,input);assert.equal(page.controller.state,'ready');
        input.value='NEXT-TICKET';page.render();
        assert.equal(page.host.querySelector('[name=query]').value,'NEXT-TICKET','summary rendering preserves the typed draft');
        assert.equal(document.activeElement,page.host.querySelector('[name=query]'),'summary rendering preserves keyboard focus');
        page.host.querySelector('[data-search]').dispatchEvent(new dom.window.Event('submit',{cancelable:true}));
        await new Promise(resolve=>setImmediate(resolve));
        assert.equal(page.controller.ticket.symbol,'NEXT-TICKET');
        assert.deepEqual(lookups,['PREVIOUS','NEXT-TICKET']);
        page.startCamera=async()=>{};page.setInputMode('camera');
        assert.equal(page.controller.ticket.symbol,'NEXT-TICKET');
        page.host.querySelector('[data-mode=manual]').click();
        page.host.querySelector('[data-next-mode=manual]').click();
        assert.equal(page.controller.state,'ready');
        assert.equal(page.host.querySelector('[name=query]').disabled,false);
        assert.equal(document.activeElement,page.host.querySelector('[name=query]'));
        page.row.session.capabilities.search_tickets=true;page.render();
        const search=page.host.querySelector('[data-search]');
        search.elements.query.value='a';search.dispatchEvent(new dom.window.Event('submit',{cancelable:true}));
        await new Promise(resolve=>setImmediate(resolve));
        const field=page.host.querySelector('[name=query]'),message=page.host.querySelector('#scan-search-error');
        assert.equal(field.getAttribute('aria-invalid'),'true');
        assert.equal(field.getAttribute('aria-describedby'),message.id);
        assert.equal(message.hidden,false);assert.equal(message.closest('form').hasAttribute('data-search'),true);
        assert.equal(page.error,null,'a field validation error never appears in the page banner');
        field.value='Anna';field.dispatchEvent(new dom.window.Event('input'));
        assert.equal(message.hidden,true);assert.equal(field.getAttribute('aria-invalid'),'false');
        let cameraStarts=0;page.startCamera=()=>{cameraStarts++;};
        page.controller.state='accepted';page.cameraWasStarted=true;
        page.nextScan(undefined,{auto:true});
        assert.equal(page.mode,'camera','a completed manual exception returns to the primary camera workflow');
        assert.equal(cameraStarts,1);
        page.mode='manual';page.controller.state='accepted';page.cameraWasStarted=false;page.cameraUnavailable=false;
        page.nextScan(undefined,{auto:true});
        assert.equal(page.mode,'manual');assert.equal(cameraStarts,1,'manual search does not request a never-used camera');
        page.mode='manual';page.controller.state='accepted';page.cameraUnavailable=true;
        page.nextScan(undefined,{auto:true});assert.equal(page.mode,'manual','denied/unavailable camera does not force the user out of manual entry');
    }finally{
        dom.window.close();globalThis.document=previous.document;
        Object.defineProperty(globalThis,'navigator',previous.navigator);
    }
});

test('one current ticket ignores other QR codes until explicitly finished; unpaid review stays stable',async()=>{
 const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
 const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
 globalThis.document=dom.window.document;Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 try {
  const page=new ScanPage(document.getElementById('scanner'),{client:{},store:{list:async()=>[]}});
  page.route={page:'scan'};page.mode='camera';page.storageAvailable=true;
  page.row={partition:'p',session:{title:'Ples',capabilities:{},settings:{fields:[]}}};
  const lookups=[],pending=new Map();page.input={pause(){this.paused=true;},stop(){},allowSame(){},stream:null};
  page.startCamera=async()=>{page.input.paused=page.controller.state!=='ready';};
  page.api={lookup:symbol=>{lookups.push(symbol);return new Promise(resolve=>pending.set(symbol,resolve));}};
  const ticket=symbol=>({ticket_id:1,symbol,state:'sent',source:'online',admission_allowed:true,products:[],fields:[]});
  page.controller=page.createController();const controller=page.controller;
  const loading=page.loadCodes(['https://noise.invalid','A','B']);
  assert.equal(controller.state,'looking_up');assert.equal(page.input.paused,true);
  await page.loadCodes(['B','C']);assert.deepEqual(lookups,['A']);
  pending.get('A')(ticket('A'));await loading;await page.loadCodes(['B']);
  assert.equal(page.controller,controller);assert.equal(controller.ticket.symbol,'A');assert.deepEqual(lookups,['A']);
  assert.equal(page.host.querySelectorAll('.scan-result').length,1);assert.equal(page.host.querySelector('[data-group-ticket]'),null);
  page.setInputMode('camera');assert.equal(controller.ticket.symbol,'A');assert.equal(page.input.paused,true);
  controller.state='awaiting_server';page.nextScan();assert.equal(controller.state,'awaiting_server');
  controller.state='pending';controller.operation={key:'durable',payload:{ticket_id:1}};controller.emit();
  page.nextScan();assert.equal(controller.state,'ready');assert.equal(page.history[0].key,'durable','leaving review preserves durable history');
  const loadingB=page.loadCodes(['B','C']);pending.get('B')({...ticket('B'),requires_unpaid_confirmation:true});await loadingB;
  page.host.querySelector('[data-unpaid]').click();await page.loadCodes(['C']);
  assert.equal(controller.ticket.symbol,'B');assert.equal(controller.unpaidConfirmed,true);assert.deepEqual(lookups,['A','B']);
  assert.equal(page.host.querySelector('[data-unpaid]').checked,true);assert.equal(page.host.querySelector('[data-confirm]').disabled,false);
  page.disposeControllers();clearTimeout(page.advanceTimer);
 }finally{dom.window.close();globalThis.document=previous.document;Object.defineProperty(globalThis,'navigator',previous.navigator);}
});

test('editor display settings are a direct menu action and the back arrow targets the ticket list',()=>{
 const dom=new JSDOM('<div id="scanner"></div>',{url:'https://vstupenky.online/scan'});
 const previous=globalThis.document;globalThis.document=dom.window.document;
 try {
  const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
  page.route={page:'scan'};page.returnPath='/PlesAKH2025-copy-ad8a55ba/reservations/tickets';
  page.row={session:{title:'Fixture',capabilities:{settings:true},settings:{fields:[]}}};
  page.host.innerHTML=page.shell('');
  assert.equal(page.host.querySelector('.scan-home').getAttribute('href'),page.returnPath);
  assert.ok(page.host.querySelector('.scan-menu nav a[href="/scan/settings"]'));
  page.row.session.capabilities.settings=false;page.host.innerHTML=page.shell('');
  assert.equal(page.host.querySelector('a[href="/scan/settings"]'),null);
 }finally {globalThis.document=previous;dom.window.close();}
});

test('device preferences cannot override the shared event field visibility',()=>{
 const c={state:'result',ticket:{state:'sent',admission_allowed:true,products:[],fields:[{key:'order:1:2',label:'Diet',value:'SHARED VISIBLE',default_visible:true},{key:'order:1:3',label:'Private',value:'SHARED HIDDEN',default_visible:false}]}};
 const html=ScanPage.prototype.resultHtml.call({preferences:{'order:1:2':false,'order:1:3':true},storageAvailable:true,row:{locked:false}},c);
 assert.match(html,/SHARED VISIBLE/);assert.doesNotMatch(html,/SHARED HIDDEN/);
});

test('allowed offline preparation runs automatically without a snapshot; disabled events do not download',async()=>{
 const previous=Object.getOwnPropertyDescriptor(globalThis,'navigator');Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 try{
  let preparations=0;const page={row:{partition:'p',session:{capabilities:{offline:true},settings:{offline:{enabled:true}}}},store:{put:async()=>{},get:async()=>null},api:{summary:async()=>({used_current:0,eligible_total:1})},summaryAt:Date.now(),summary:{snapshot_ticket_count:1},render(){},async prepare({automatic}){assert.equal(automatic,true);preparations++;}};
  await ScanPage.prototype.recover.call(page);await page.backgroundPreparation;assert.equal(preparations,1);
  page.row.session.capabilities.offline=false;page.lastSnapshotAttempt=0;await ScanPage.prototype.recover.call(page);assert.equal(preparations,1);
 }finally{if(previous)Object.defineProperty(globalThis,'navigator',previous);else delete globalThis.navigator;}
});


test('automatic offline preparation uses complete snapshot size, includes 1000, and refreshes manually prepared large events',async()=>{
 const previous=Object.getOwnPropertyDescriptor(globalThis,'navigator');Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 try {
  for(const [count,expected] of [[0,true],[999,true],[1000,true],[1001,false],[undefined,false],[-1,false],['1000',false]]) {
   let preparations=0;
   const page={row:{partition:'p',session:{capabilities:{offline:true},settings:{offline:{enabled:true}}}},store:{put:async()=>{},get:async()=>null},api:{summary:async()=>({eligible_total:1,snapshot_ticket_count:count})},summaryAt:0,render(){},async prepare({automatic}){assert.equal(automatic,true);preparations++;}};
   await ScanPage.prototype.recover.call(page);await page.backgroundPreparation;
   assert.equal(preparations,Number(expected),`snapshot size ${count}`);
   page.snapshot={server_time:new Date(Date.now()-120000).toISOString()};page.lastSnapshotAttempt=0;
   await ScanPage.prototype.recover.call(page);await page.backgroundPreparation;
   assert.equal(preparations,Number(expected)+1,'existing large-event preparation is refreshed');
   page.row.session.settings.offline.enabled=false;page.lastSnapshotAttempt=0;
   await ScanPage.prototype.recover.call(page);await page.backgroundPreparation;
   assert.equal(preparations,Number(expected)+1,'explicit disabled setting is respected');
  }
 }finally{if(previous)Object.defineProperty(globalThis,'navigator',previous);else delete globalThis.navigator;}
});


test('passive recovery retains the review DOM, scroll, disclosures and pinned actions',async()=>{
 const dom=new JSDOM('<div id="scanner"></div>',{url:'https://vstupenky.online/scan'});
 const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
 globalThis.document=dom.window.document;Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 try {
  const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
  page.route={page:'scan'};page.mode='manual';page.storageAvailable=true;
  page.row={session:{title:'Ples',capabilities:{},settings:{fields:[]}}};
  page.input={stop(){}};
  page.api={summary:async()=>({used_current:2,eligible_total:40})};
  page.controller={state:'result',ticket:{symbol:'TEST',state:'sent',source:'online',admission_allowed:true,products:[],fields:Array.from({length:8},(_,i)=>({key:`field-${i}`,label:`Field ${i}`,value:'Value',default_visible:true}))}};
  page.render();
  const detail=page.host.querySelector('.scan-detail'),disclosure=detail.querySelector('details'),confirm=page.host.querySelector('[data-confirm]');
  detail.scrollTop=180;disclosure.open=true;confirm.focus();
  assert.equal(confirm.closest('.scan-detail'),null,'admission controls are outside scrolling content');
  assert.ok(confirm.closest('.scan-review-footer'));
  assert.equal(page.host.querySelectorAll('.scan-review-footer [data-next]').length,1,'footer retains an explicit next-ticket action');
  assert.equal(page.host.querySelectorAll('.scan-review-footer [data-mode]').length,0,'input modes do not compete with confirmation');
  assert.ok(page.host.querySelector('.scan-review-navigation [data-mode=camera]'),'manual review retains reachable camera navigation');
  await page.recover();
  assert.equal(page.host.querySelector('.scan-detail'),detail);
  assert.equal(detail.scrollTop,180);assert.equal(disclosure.open,true);
  assert.equal(page.host.querySelector('[data-confirm]'),confirm);assert.equal(document.activeElement,confirm);
  page.storageAvailable=false;page.render();
  assert.equal(page.host.querySelector('[data-confirm]'),null,'storage loss invalidates preserved admission controls');
  assert.equal(page.host.querySelector('.scan-detail').scrollTop,180);
  assert.equal(page.host.querySelector('.scan-detail details').open,true);
 }finally{dom.window.close();globalThis.document=previous.document;Object.defineProperty(globalThis,'navigator',previous.navigator);}
});

test('explicit return admits the same code to a new review; automatic return retains duplicate suppression',async()=>{
 const dom=new JSDOM('<div id="scanner"></div>',{url:'https://vstupenky.online/scan'});
 const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
 globalThis.document=dom.window.document;Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 try {
  const page=new ScanPage(document.getElementById('scanner'),{client:{},store:{list:async()=>[]}});
  page.route={page:'scan'};page.mode='manual';page.storageAvailable=true;
  page.row={partition:'fixture',session:{title:'Ples',capabilities:{},settings:{fields:[]}}};
  let resets=0,lookups=0;
  page.input={stop(){},pause(){},allowSame(){resets++;}};
  page.api={lookup:async symbol=>{lookups++;return {symbol,ticket_id:1,state:'sent',source:'online',admission_allowed:true,products:[],fields:[]};}};
  page.controller=page.createController();
  await page.loadCodes(['SAME']);
  page.mode='camera';page.startCamera=async()=>{};page.render();
  assert.equal(page.host.querySelector('[data-camera-expand]'),null);
  page.host.querySelector('[data-next]').click();
  assert.equal(resets,1);assert.equal(page.controller.state,'ready');
  await page.loadCodes(['SAME']);assert.equal(lookups,2);assert.equal(page.host.querySelector('.scan-group'),null);
  page.nextScan('manual',{auto:true});assert.equal(resets,1);
  page.disposeControllers();clearTimeout(page.advanceTimer);
 }finally{dom.window.close();globalThis.document=previous.document;Object.defineProperty(globalThis,'navigator',previous.navigator);}
});

test('only a server-accepted receipt automatically advances; durable offline pending remains explicit',t=>{
 const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
 const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
 globalThis.document=dom.window.document;Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 t.mock.timers.enable({apis:['setTimeout']});
 try {
  const page=new ScanPage(document.getElementById('scanner'),{client:{},store:{list:async()=>[]}});
  page.route={page:'scan'};page.mode='camera';page.cameraWasStarted=true;page.storageAvailable=true;
  page.row={partition:'p',session:{title:'Ples',capabilities:{},settings:{fields:[]}}};
  page.input={pause(){this.paused=true;},stop(){},stream:null,allowSame(){assert.fail('automatic advance must retain suppression');}};
  let starts=0;page.startCamera=()=>{starts++;};page.controller=page.createController();
  const c=page.controller;c.state='pending';c.ticket={ticket_id:1,symbol:'ONE',products:[],fields:[],source:'offline'};
  c.operation={key:'op',payload:{operation_id:'accepted-once',ticket_id:1}};c.offlineReady=true;c.emit();
  t.mock.timers.tick(5000);assert.equal(c.state,'pending');assert.ok(page.host.querySelector('[data-next]'));
  c.state='accepted';c.operation.receipt={outcome:'accepted'};c.emit();
  t.mock.timers.tick(1199);assert.equal(c.state,'accepted');assert.equal(page.input.paused,true);
  t.mock.timers.tick(1);assert.equal(c.state,'ready');assert.equal(page.input.paused,false);assert.equal(starts,1);
  assert.equal(page.history.length,1,'receipt history survives advancing to the next ticket');
  page.disposeControllers();clearTimeout(page.advanceTimer);
 }finally{dom.window.close();globalThis.document=previous.document;Object.defineProperty(globalThis,'navigator',previous.navigator);}
});
