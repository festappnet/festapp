import {register} from 'node:module';register('../css_loader.mjs',import.meta.url);
import {JSDOM} from 'jsdom';
const {ScanPage}=await import('../../src/components/scan/scan_page.js');
import test from 'node:test';
import assert from 'node:assert/strict';
import {scannerReturnPath,safeScannerReturn,scannerInputHistoryState} from '../../src/components/scan/scanner_navigation.js';
const origin='https://vstupenky.online';
const country={occasion_id:32316,organization_id:3,occasion_link:'skautskyples2026-copy-ae6d7140'};
const original={occasion_id:13,organization_id:3,occasion_link:'skautskyples2025'};
const tickets='/'+country.occasion_link+'/reservations/tickets';
const location=path=>({href:origin+path});
const memory=()=>{const entries=new Map();return {getItem:k=>entries.get(k),setItem:(k,v)=>entries.set(k,v)};};
test('return destination survives secret removal and reload within the same occasion',()=>{
 const storage=memory();
 assert.equal(scannerReturnPath({location:location('/scan/SECRET?returnTo='+encodeURIComponent(tickets)),storage,session:country}),tickets);
 assert.equal(scannerReturnPath({location:location('/scan/settings'),storage,session:country}),tickets);
});
test('direct Country code ignores original event storage, referrer and explicit returnTo',()=>{
 const storage=memory();
 const foreign='/'+original.occasion_link+'/reservations/tickets';
 storage.setItem('festapp-scanner-return',foreign);
 scannerReturnPath({location:location('/scan'),returnTo:foreign,storage,session:original});
 for(const input of [{},{returnTo:foreign},{referrer:origin+foreign}])
  assert.equal(scannerReturnPath({location:location('/scan/SECRET'),storage,session:country,...input}),'/'+country.occasion_link);
 assert.equal(scannerReturnPath({location:location('/scan'),storage,session:original}),foreign);
});
test('return paths are isolated across backends and require authenticated occasion metadata',()=>{
 const storage=memory();
 scannerReturnPath({location:location('/scan'),returnTo:tickets,storage,session:country,backend:{origin:'https://api.example',generation:1}});
 assert.equal(scannerReturnPath({location:location('/scan'),storage,session:country,backend:{origin:'https://api.example',generation:2}}),'/'+country.occasion_link);
 assert.equal(scannerReturnPath({location:location('/scan'),returnTo:tickets,storage}),'/');
 assert.equal(scannerReturnPath({location:location('/scan'),returnTo:tickets,storage,session:{occasion_id:32316}}),'/');
});
test('rejects foreign origins, scanner loops and event prefix lookalikes; works without storage',()=>{
 for(const value of ['https://evil.invalid','//evil.invalid','/scan','/scan/settings','/login-qr'])assert.equal(safeScannerReturn(value,origin),null);
 for(const value of ['/'+country.occasion_link+'-other/reservations','/'+country.occasion_link+'%2fother/reservations'])
  assert.equal(scannerReturnPath({location:location('/scan'),returnTo:value,session:country}),'/'+country.occasion_link);
 assert.equal(scannerReturnPath({location:location('/scan'),referrer:origin+tickets,session:country,storage:{getItem(){throw Error();},setItem(){throw Error();}}}),tickets);
});

function navigationPage(t,{loaded=true}={}) {
 const dom=new JSDOM('<div id="scanner"></div>',{url:'https://vstupenky.online/scan'});
 const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator'),window:Object.getOwnPropertyDescriptor(globalThis,'window')};
 globalThis.document=dom.window.document;Object.defineProperty(globalThis,'window',{configurable:true,value:dom.window});Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 const page=new ScanPage(document.getElementById('scanner'),{client:{},store:{list:async()=>[]}});
 page.route={page:'scan'};page.mode='camera';page.storageAvailable=true;page.returnPath=tickets;
 page.row={partition:'current-event',session:{title:'Ples',capabilities:{search_tickets:true},settings:{fields:[]}}};
 page.input={pause(){this.paused=true;},stop(){},allowSame(){},suppress(){}};
 page.startCamera=async()=>{page.input.paused=page.controller.state!=='ready';};
 page.api={lookup:async symbol=>({ticket_id:1,symbol,holder_name:'Anna Novotná',state:'sent',source:'online',products:[],fields:[],admission_allowed:true})};
 page.controller=page.createController();if(loaded){page.controller.state='result';page.controller.ticket={ticket_id:1,symbol:'OLD',state:'sent',source:'online',products:[],fields:[]};}
 page.render();
 t.after(()=>{clearTimeout(page.advanceTimer);clearTimeout(page.searchTimer);dom.window.removeEventListener('popstate',page.onInputHistory);page.disposeControllers();globalThis.document=previous.document;Object.defineProperty(globalThis,'navigator',previous.navigator);if(previous.window)Object.defineProperty(globalThis,'window',previous.window);else delete globalThis.window;dom.window.close();});
 return {page,dom};
}
for(const loaded of [false,true])test(`search is visible and focused with ticket loaded=${loaded}; header Back returns to camera`,async t=>{
 const {page,dom}=navigationPage(t,{loaded});
 page.host.querySelector('[data-mode=manual]').click();
 assert.equal(page.mode,'manual');assert.equal(page.searchOpen,true);assert.ok(page.host.querySelector('.manual-ready'));
 assert.equal(document.activeElement,page.host.querySelector('[name=query]'));assert.equal(page.host.querySelector('.scan-result'),null);assert.equal(page.host.querySelector('[data-confirm]'),null);
 const event=new dom.window.MouseEvent('click',{bubbles:true,cancelable:true});page.host.querySelector('.scan-home').dispatchEvent(event);
 assert.equal(event.defaultPrevented,true);assert.equal(page.mode,'camera');assert.equal(dom.window.location.pathname,'/scan');
 await new Promise(resolve=>setTimeout(resolve,30));assert.equal(dom.window.history.state.scannerInput,'camera');
 assert.equal(page.controller.state,'ready');assert.equal(page.controller.ticket,null,'Back opens camera alone');
 assert.equal(page.host.querySelector('.scan-result'),null);assert.equal(page.host.querySelector('[data-confirm]'),null);
 const leave=new dom.window.MouseEvent('click',{bubbles:true,cancelable:true});page.host.querySelector('.scan-home').dispatchEvent(leave);assert.equal(leave.defaultPrevented,false,'only Back from camera may leave the scanner');
});

test('browser Back/Forward stays inside scanner and does not reach the app router',async t=>{
 const {page,dom}=navigationPage(t);let routerCalls=0;
 const {RouterService}=await import('../../src/services/router_service.js');
 const oldPage=RouterService._scannerPage,oldPath=RouterService._lastPath;
 RouterService._scannerPage=page;RouterService._lastPath='/scan/SECRET';
 t.mock.method(RouterService,'mountScanner',async()=>{routerCalls++;});
 RouterService.initPopStateListener();
 t.after(()=>{RouterService._scannerPage=oldPage;RouterService._lastPath=oldPath;});
 page.setInputMode('manual');dom.window.history.back();await new Promise(resolve=>setTimeout(resolve,30));
 assert.equal(page.mode,'camera');assert.equal(routerCalls,0);
 dom.window.history.forward();await new Promise(resolve=>setTimeout(resolve,30));
 assert.equal(page.mode,'manual');assert.equal(document.activeElement,page.host.querySelector('[name=query]'));assert.equal(routerCalls,0);
 const pushes=t.mock.method(dom.window.history,'pushState');
 page.controller.state='awaiting_server';page.searchOpen=false;page.render();
 dom.window.history.back();await new Promise(resolve=>setTimeout(resolve,30));
 assert.equal(page.mode,'manual','history navigation cannot interrupt persisting/server confirmation');assert.equal(dom.window.history.state.scannerInput,'manual');assert.equal(dom.window.history.length,2,'router and component process the same blocked Back only once');assert.equal(pushes.mock.callCount(),0,'busy Back restores the existing workspace without creating skippable history');
});

test('new ticket arrival animates once per lookup, not on recovery, and respects reduced motion',async t=>{
 const {page,dom}=navigationPage(t,{loaded:false}),animations=[];
 dom.window.Element.prototype.animate=function(frames,options){animations.push({element:this,frames,options});};
 dom.window.matchMedia=()=>({matches:false});
 await page.loadCodes(['FIRST']);assert.equal(animations.length,1);assert.equal(animations[0].element.classList.contains('scan-detail'),true);
 page.render();page.render();assert.equal(animations.length,1,'passive updates must not replay arrival');
 page.nextScan('camera');await page.loadCodes(['FIRST']);assert.equal(animations.length,2,'an explicit new lookup is visible even for the same ticket');
 dom.window.matchMedia=()=>({matches:true});page.nextScan('camera');await page.loadCodes(['SECOND']);assert.equal(animations.length,2);
 page.setInputMode('manual');page.controller.state='accepted';page.controller.operation={payload:{operation_id:'done'},receipt:{outcome:'accepted'}};page.updateAutoAdvance();assert.equal(page.advanceTimer,null,'background acceptance never takes focus away from an open search');
});


test('Back from a camera ticket clears the review before leaving the scanner',async t=>{
 const {page,dom}=navigationPage(t,{loaded:false});
 dom.window.history.replaceState(null,'',tickets);dom.window.history.pushState(null,'','/scan');
 await page.loadCodes(['SCANNED']);assert.ok(page.host.querySelector('.scan-result'));
 dom.window.history.back();await new Promise(resolve=>setTimeout(resolve,30));
 assert.equal(dom.window.location.pathname,'/scan');assert.equal(page.mode,'camera');assert.equal(page.controller.state,'ready');assert.equal(page.controller.ticket,null);assert.equal(page.host.querySelector('.scan-result'),null);
 dom.window.history.back();await new Promise(resolve=>setTimeout(resolve,30));
 assert.equal(dom.window.location.pathname,tickets,'second Back from camera leaves scanner');
});

test('header Back from a scanned ticket shows camera alone',async t=>{
 const {page,dom}=navigationPage(t,{loaded:false});await page.loadCodes(['SCANNED']);
 const back=new dom.window.MouseEvent('click',{bubbles:true,cancelable:true});page.host.querySelector('.scan-home').dispatchEvent(back);
 assert.equal(back.defaultPrevented,true);assert.equal(page.controller.state,'ready');assert.equal(page.controller.ticket,null);assert.equal(page.mode,'camera');
 await new Promise(resolve=>setTimeout(resolve,30));assert.equal(dom.window.history.state.scannerInput,'camera');
});


test('Back on scanner entry without a session remains a normal exit link',t=>{
 const {page,dom}=navigationPage(t,{loaded:false});page.row=null;page.disposeControllers();page.controller=null;page.render();
 const back=new dom.window.MouseEvent('click',{bubbles:true,cancelable:true});page.host.querySelector('.scan-home').dispatchEvent(back);assert.equal(back.defaultPrevented,false);
});


test('automatic scans after Back reuse the workspace entry without a new pushState',async t=>{
 const {page,dom}=navigationPage(t,{loaded:false});
 await page.loadCodes(['FIRST']);
 const push=t.mock.method(dom.window.history,'pushState');
 for(let cycle=0;cycle<3;cycle++){
  dom.window.history.back();await new Promise(resolve=>setTimeout(resolve,30));
  assert.equal(page.controller.state,'ready');assert.equal(page.mode,'camera');
  await page.loadCodes(['NEXT-'+cycle]);await new Promise(resolve=>setTimeout(resolve,30));
  assert.equal(page.controller.state,'result');assert.equal(dom.window.location.pathname,'/scan');
 }
 assert.equal(push.mock.callCount(),0,'async camera detection cannot create skippable browser history after a traversal');
});


test('Back from the initial full camera skips its empty reserved workspace',async t=>{
 const {page,dom}=navigationPage(t,{loaded:false});
 dom.window.history.replaceState(null,'',tickets);dom.window.history.pushState(null,'','/scan');
 page.prepareInputHistory();dom.window.history.back();await new Promise(resolve=>setTimeout(resolve,60));
 assert.equal(dom.window.location.pathname,tickets);
});

test('Back keeps a held QR suppressed; removing and presenting it again allows a new scan',async t=>{
 const {page,dom}=navigationPage(t,{loaded:false});
 const {ScannerInput}=await import('../../src/components/scan/scanner_input.js');
 page.input=new ScannerInput(code=>page.loadCodes([code]));t.after(()=>page.input.dispose());
 const frame=[{value:'HELD'}];page.input.dispatchCodes(frame);await new Promise(resolve=>setImmediate(resolve));
 assert.equal(page.controller.state,'result');
 dom.window.history.back();await new Promise(resolve=>setTimeout(resolve,30));
 page.input.dispatchCodes(frame);await new Promise(resolve=>setImmediate(resolve));
 assert.equal(page.controller.state,'ready','the same visible QR must not instantly reopen after Back');
 page.input.dispatchCodes([]);page.input.dispatchCodes(frame);await new Promise(resolve=>setImmediate(resolve));
 assert.equal(page.controller.state,'result','the same ticket works again after it leaves the camera');
});

test('scanner route normalization preserves only the owned camera/workspace state',()=>{
 assert.deepEqual(scannerInputHistoryState({scannerInput:'camera',scannerLevel:'camera',secret:'discard'}),{scannerInput:'camera',scannerLevel:'camera'});
 assert.deepEqual(scannerInputHistoryState({scannerInput:'manual',scannerLevel:'workspace',scannerReview:true}),{scannerInput:'manual',scannerLevel:'workspace',scannerReview:true});
 for(const state of [null,{}, {scannerInput:'camera'}, {scannerInput:'camera',scannerLevel:'other'}])assert.equal(scannerInputHistoryState(state),null);
});


test('the real router keeps the reserved scanner levels across reload normalization',async t=>{
 const {dom}=navigationPage(t,{loaded:false});
 const {RouterService}=await import('../../src/services/router_service.js');
 const original=RouterService._lastPath;t.after(()=>{RouterService._lastPath=original;});
 const mounted=t.mock.method(RouterService,'mountScanner',async()=>{});
 dom.window.history.replaceState({scannerInput:'camera',scannerLevel:'camera',secret:'discard'},'', '/scan');
 assert.equal(await RouterService.handleInitialLoad(),true);
 assert.deepEqual(dom.window.history.state,{scannerInput:'camera',scannerLevel:'camera'});
 assert.equal(mounted.mock.calls[0].arguments[0].page,'scan');
});
