import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const { ScanPage } = await import('../../src/components/scan/scan_page.js');

test('lookup, errors, receipts and group review preserve the live camera; leaving scanner stops it', () => {
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
        page.batch=[{symbol:'A',controller:page.controller},{symbol:'B',controller:{state:'error',error:'not_found',scanSymbol:'B'}},{symbol:'C',controller:{state:'error',error:'not_found',scanSymbol:'C'}}];
        page.render();
        assert.equal(page.host.querySelector('video'),video,'a group review retains the preview');
        assert.equal(page.host.querySelectorAll('.scan-result').length,0,'group errors stay on their own rows until explicitly opened');
        assert.equal(page.host.querySelectorAll('[data-group-ticket]').length,3);
        page.host.querySelector('[data-group-ticket="1"]').click();
        assert.equal(page.host.querySelectorAll('.scan-result').length,1);
        const detail=page.host.querySelector('#scan-group-detail-1');
        assert.equal(detail.hidden,false);assert.equal(detail.querySelector('.scan-ticket-code').textContent,'B');
        assert.equal(page.host.querySelector('#scan-group-detail-2').hidden,true);
        assert.equal(page.host.querySelector('.scan-detail > .scan-result'),null,'there is no detached error for the whole group');
        page.host.querySelector('[data-group-ticket="1"]').click();
        assert.equal(page.host.querySelectorAll('.scan-result').length,0);
        assert.equal(document.activeElement.dataset.groupTicket,'1');
        page.route={page:'history'};page.render();
        assert.equal(stops,1,'leaving scanner releases camera tracks');
    } finally {
        dom.window.close();globalThis.document=previous.document;
        Object.defineProperty(globalThis,'navigator',previous.navigator);
    }
});

test('manual entry from a single result or group starts a focused, usable next-ticket form',async()=>{
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
        const input=page.host.querySelector('[name=symbol]');
        assert.equal(input.disabled,false);assert.equal(input.value,'');
        assert.equal(document.activeElement,input);assert.equal(page.controller.state,'ready');
        input.value='NEXT-TICKET';page.render();
        assert.equal(page.host.querySelector('[name=symbol]').value,'NEXT-TICKET','summary rendering preserves the typed draft');
        assert.equal(document.activeElement,page.host.querySelector('[name=symbol]'),'summary rendering preserves keyboard focus');
        page.host.querySelector('[data-code] button').click();
        await new Promise(resolve=>setImmediate(resolve));
        assert.equal(page.controller.ticket.symbol,'NEXT-TICKET');
        assert.deepEqual(lookups,['PREVIOUS','NEXT-TICKET']);
        page.mode='camera';
        page.batch=[{symbol:'NEXT-TICKET',controller:page.controller},{symbol:'OTHER',controller:page.createController()}];
        page.batch[1].controller.state='error';page.batch[1].controller.error='not_found';
        page.render();page.host.querySelector('[data-mode=manual]').click();
        assert.equal(page.batch,null);assert.equal(page.controller.state,'ready');
        assert.equal(page.host.querySelector('[name=symbol]').disabled,false);
        assert.equal(document.activeElement,page.host.querySelector('[name=symbol]'));
        page.row.session.capabilities.search_tickets=true;page.render();
        const search=page.host.querySelector('[data-search]');
        search.elements.query.value='a';search.querySelector('button').click();
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
        assert.equal(page.mode,'camera');assert.equal(cameraStarts,1,'automatic return does not request a never-used camera');
        page.mode='manual';page.controller.state='accepted';page.cameraUnavailable=true;
        page.nextScan(undefined,{auto:true});assert.equal(page.mode,'manual','denied/unavailable camera does not force the user out of manual entry');
    }finally{
        dom.window.close();globalThis.document=previous.document;
        Object.defineProperty(globalThis,'navigator',previous.navigator);
    }
});

test('camera appends new tickets while lookups and confirmations are pending without replacing reviewed controllers',async()=>{
    const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
    const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
    globalThis.document=dom.window.document;
    Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
    try{
        const page=new ScanPage(document.getElementById('scanner'),{client:{},store:{list:async()=>[]}});
        page.route={page:'scan'};page.storageAvailable=true;page.preferences={};
        page.row={partition:'fixture',session:{title:'Fixture',capabilities:{},settings:{fields:[]}}};
        page.input={paused:false,stop(){},pause(){assert.fail('ticket review must not pause recognition');}};
        const lookups=[],resolve=new Map();
        page.api={lookup:symbol=>{lookups.push(symbol);return new Promise(done=>resolve.set(symbol,done));}};
        const ticket=symbol=>({symbol,ticket_id:symbol.charCodeAt(0),holder_name:symbol,products:[],fields:[],admission_allowed:true,source:'online',state:'sent'});
        page.controller=page.createController();const first=page.controller;
        const a=page.loadCodes(['A']);const b=page.loadCodes(['B','A']);
        assert.deepEqual(lookups,['A','B']);assert.equal(page.batch.length,2);
        assert.equal(page.controller,first);assert.equal(page.input.paused,false);
        resolve.get('A')(ticket('A'));resolve.get('B')(ticket('B'));await Promise.all([a,b]);
        first.ticket={...first.ticket,order_id:17,spot:'Stůl 7 · místo 1',products:[{title:'Vstup'},{title:'Večeře <host>'}]};
        page.batch[1].controller.ticket={...page.batch[1].controller.ticket,order_id:17,spot:'Stůl 7 · místo 2'};
        page.render();
        assert.equal(page.host.querySelectorAll('.scan-order-group').length,1);
        assert.match(page.host.querySelector('.scan-order-header').textContent,/Stůl 7/);
        assert.equal(page.host.querySelector('[data-group-ticket="0"] strong').textContent.includes('Stůl 7 · místo 1'),true);
        assert.equal(page.host.querySelectorAll('[data-group-ticket="0"] .scan-group-products>span').length,2);
        assert.equal(page.host.querySelector('[data-group-ticket="0"] .scan-group-products').textContent,'VstupVečeře <host>');
        assert.equal(page.host.querySelector('[data-group-ticket="0"] host'),null);
        first.state='awaiting_server';first.operation={key:'op-a',payload:{ticket_id:65}};first.emit();
        page.batchConfirming=true;
        const c=page.loadCodes(['C','B']);assert.equal(page.batch.length,3);
        assert.equal(page.controller,first);assert.equal(first.state,'awaiting_server');
        resolve.get('C')(ticket('C'));await c;
        assert.deepEqual(lookups,['A','B','C']);assert.equal(page.batch[2].controller.state,'result');
        assert.equal(page.input.paused,false);assert.equal(page.batch[0].controller.operation.key,'op-a');
        page.batchConfirming=false;first.state='result';
        first.ticket={...ticket('A'),requires_unpaid_confirmation:true};page.render();page.host.querySelector('[data-group-ticket="0"]').click();
        page.host.querySelector('[data-unpaid]').click();assert.equal(page.controller.unpaidConfirmed,true);
        const d=page.loadCodes(['D']);resolve.get('D')(ticket('D'));await d;
        assert.equal(page.host.querySelector('[data-unpaid]').checked,true,'new detections preserve an explicit unpaid decision on the selected ticket');
        assert.equal(page.host.querySelector('[data-confirm]').disabled,false);
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
  let preparations=0;const page={row:{partition:'p',session:{capabilities:{offline:true},settings:{offline:{enabled:true}}}},store:{put:async()=>{},get:async()=>null},api:{summary:async()=>({used_current:0,eligible_total:1})},summaryAt:Date.now(),summary:{},render(){},async prepare({automatic}){assert.equal(automatic,true);preparations++;}};
  await ScanPage.prototype.recover.call(page);await page.backgroundPreparation;assert.equal(preparations,1);
  page.row.session.capabilities.offline=false;page.lastSnapshotAttempt=0;await ScanPage.prototype.recover.call(page);assert.equal(preparations,1);
 }finally{if(previous)Object.defineProperty(globalThis,'navigator',previous);else delete globalThis.navigator;}
});
