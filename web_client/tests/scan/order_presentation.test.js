import {register} from 'node:module';register('../css_loader.mjs',import.meta.url);
import test from 'node:test';import assert from 'node:assert/strict';import {JSDOM} from 'jsdom';
const {ScanPage}=await import('../../src/components/scan/scan_page.js');
test('single ticket shows purchaser once, its table and dinner, and escaped order and ticket notes',()=>{
 const c={state:'result',ticket:{symbol:'A',holder_name:'A',purchaser_name:'Petra Svobodová',order_note:'Společná poznámka <order>',note:'Jednotlivá poznámka <ticket>',admission_allowed:true,spot:'28A',spot_group:{title:'28'},products:[{title:'Místo',type:'spot',type_title:'Místo'},{type:'food',type_title:'Večeře',title:'Menu 1: Hovězí guláš',short_title:'Guláš'}]}};
 const html=ScanPage.prototype.resultHtml.call({storageAvailable:true,row:{locked:false}},c),dom=new JSDOM(html),doc=dom.window.document;
 try{
  assert.equal(doc.querySelector('h3').textContent,'Petra Svobodová');assert.equal(doc.querySelectorAll('.scan-purchaser').length,0);
  assert.equal(doc.body.textContent.match(/Petra Svobodová/g).length,1);assert.match(doc.body.textContent,/table 28/);assert.match(doc.body.textContent,/28A/);
  assert.equal(doc.querySelectorAll('.scan-products li').length,1);assert.match(doc.querySelector('.scan-products').textContent,/Večeře: Guláš/);
  assert.match(doc.body.textContent,/Společná poznámka <order>/);assert.match(doc.body.textContent,/Jednotlivá poznámka <ticket>/);
  assert.equal(doc.querySelector('order'),null);assert.equal(doc.querySelector('ticket'),null);
  assert.ok(doc.querySelector('[data-confirm]'));assert.ok(doc.querySelector('[data-next]'));assert.equal(doc.querySelector('details'),null);
 }finally{dom.window.close();}
});

test('product titles use configured non-empty short titles and fall back consistently',async()=>{
 const {scannerProductTitle}=await import('../../src/components/scan/scanner_presentation.js');
 assert.equal(scannerProductTitle({title:'Full title',short_title:' Short '}),'Short');
 assert.equal(scannerProductTitle({title:'Full title',short_title:'  '}),'Full title');
 assert.equal(scannerProductTitle({title:'Full title'}),'Full title');
});

test('non-seat product captions identify dinner and transport using the configured short title',async()=>{
 const {scannerProductCaption}=await import('../../src/components/scan/scanner_presentation.js');
 assert.equal(scannerProductCaption({type:'food',type_title:'Večeře',title:'Full menu',short_title:'Guláš'}),'Večeře: Guláš');
 assert.equal(scannerProductCaption({type:'other',type_title:'Odvoz',title:'Opava, Východní nádraží'}),'Odvoz: Opava, Východní nádraží');
 assert.equal(scannerProductCaption({type:'spot',type_title:'Místo',title:'VIP'}),'VIP');
});

test('offline manual search finds purchaser, batch and case-insensitive ticket code',async()=>{
 const now=Date.now(),ticket={ticket_id:10,symbol:'X3485A9H2F',holder_name:'X3485A9H2F',purchaser_name:'Petra Svobodová',batch_title:'Páteční prodej'};
 const oldNavigator=Object.getOwnPropertyDescriptor(globalThis,'navigator');
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:false}});
 try {
  const page={row:{partition:'event',wallAt:now,serverAt:now,session:{offline_until:new Date(now+60000).toISOString()}},store:{async list(name,partition){assert.equal(name,'tickets');assert.equal(partition,'event');return [{ticket}];}},render(){}};
  for(const query of ['Petra Svobodová','páteční','x3485a9h2f']){
   page.searchQuery=query;await ScanPage.prototype.search.call(page,0);assert.deepEqual(page.searchResults,[ticket]);
  }
 } finally {if(oldNavigator)Object.defineProperty(globalThis,'navigator',oldNavigator);else delete globalThis.navigator;}
});


test('ticket status is independent of products and preserves cancellation, waiting and historical use',async()=>{
 const {scannerTicketStatus}=await import('../../src/components/scan/scanner_presentation.js');
 const {scanResult}=await import('../../src/components/scan/scan_result.js');
 for(const [state,key] of [['storno','ticket_cancelled'],['waitlisted','ticket_waitlisted'],['used','already_used'],['ordered','unpaid']]){
  const ticket={state,symbol:null,products:[],fields:[],admission_allowed:false};
  assert.equal(scannerTicketStatus(ticket).key,key);
  const html=scanResult({state:'result',ticket},true);
  assert.match(html,new RegExp(key));assert.doesNotMatch(html,/no_products|data-confirm/);assert.match(html,/data-next/);
 }
 assert.equal(scannerTicketStatus({state:'sent',order_state:'storno',admission_allowed:false}).key,'ticket_cancelled');
 assert.equal(scannerTicketStatus({state:'used',order_state:'storno'}).key,'already_used');
});
