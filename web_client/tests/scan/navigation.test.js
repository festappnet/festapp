import {register} from 'node:module';register('../css_loader.mjs',import.meta.url);
import {JSDOM} from 'jsdom';
const {ScanPage}=await import('../../src/components/scan/scan_page.js');
import test from 'node:test';
import assert from 'node:assert/strict';
import {scannerReturnPath,safeScannerReturn} from '../../src/components/scan/scanner_navigation.js';
const origin='https://vstupenky.online';
const tickets='/PlesAKH2025-copy-ad8a55ba/reservations/tickets';
test('scanner returns to its ticket list after the scan secret is removed and after reload',()=>{
 const entries=new Map(),storage={getItem:k=>entries.get(k),setItem:(k,v)=>entries.set(k,v)};
 assert.equal(scannerReturnPath({location:{href:origin+'/scan/SECRET?returnTo='+encodeURIComponent(tickets)},storage}),tickets);
 assert.equal(scannerReturnPath({location:{href:origin+'/scan'},storage}),tickets);
 assert.equal(scannerReturnPath({location:{href:origin+'/scan/settings'},returnTo:tickets,storage}),tickets);
});
test('scanner return paths reject other origins and scanner loops, and work without storage',()=>{
 for(const value of ['https://evil.invalid','//evil.invalid','/scan','/scan/settings','/login-qr'])assert.equal(safeScannerReturn(value,origin),null);
 assert.equal(scannerReturnPath({location:{href:origin+'/scan'},referrer:origin+tickets,storage:{getItem(){throw Error();},setItem(){throw Error();}}}),tickets);
 assert.equal(scannerReturnPath({location:{href:origin+'/scan'}}),'/');
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
 page.controller.state='awaiting_server';page.searchOpen=false;page.render();
 dom.window.history.back();await new Promise(resolve=>setTimeout(resolve,30));
 assert.equal(page.mode,'manual','history navigation cannot interrupt persisting/server confirmation');assert.equal(dom.window.history.state.scannerInput,'manual');assert.equal(dom.window.history.length,2,'router and component process the same blocked Back only once');
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
