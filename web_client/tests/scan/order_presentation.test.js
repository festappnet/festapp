import {register} from 'node:module';register('../css_loader.mjs',import.meta.url);
import test from 'node:test';import assert from 'node:assert/strict';import {JSDOM} from 'jsdom';
const {ScanPage}=await import('../../src/components/scan/scan_page.js');
test('one purchaser with two unnamed tickets appears once above the order; dinner variants stay on individual cards',()=>{
 const batch=['A','B'].map((symbol,index)=>({symbol,controller:{state:'result',ticket:{symbol,holder_name:symbol,order_id:9,purchaser_name:'Petra Svobodová',order_note:'Společná poznámka <order>',note:index?'':'Jednotlivá poznámka <ticket>',admission_allowed:true,spot:`28${symbol}`,spot_group:{blueprint_id:7,id:'28',title:'28'},products:[{title:'Místo',type:'spot',type_title:'Místo'},{type:'food',type_title:'Večeře',title:index?'Bez večeře':'Menu 1: Hovězí guláš, houskový knedlík',short_title:index?'':'Guláš'}]}}}));
 const html=ScanPage.prototype.batchHtml.call({batch,storageAvailable:true,row:{locked:false}}),dom=new JSDOM(html),doc=dom.window.document;
 try{
  assert.match(doc.querySelector('.scan-order-header').textContent,/Petra Svobodová/);
  const cards=[...doc.querySelectorAll('[data-group-ticket]')];assert.equal(cards.length,2);
  for(const card of cards)assert.doesNotMatch(card.querySelector('strong').textContent,/Petra/);
  assert.match(cards[0].querySelector('.scan-product-food').textContent,/Večeře: Guláš/);
  assert.match(cards[1].querySelector('.scan-product-food').textContent,/Večeře: Bez večeře/);
  assert.match(cards[0].querySelector('strong').textContent,/28A/);
  assert.equal(cards[0].querySelectorAll('.scan-group-products>span').length,1,'seat product is redundant when the actual seat is shown');
  assert.doesNotMatch(doc.querySelector('.scan-order-header').textContent,/Objednatel|purchaser/);
  assert.ok(cards[0].classList.contains('allowed'));
  assert.ok(cards[0].querySelector('.scan-ticket-status .scan-icon'));
  assert.equal(cards[0].querySelector('small'),null,'raw ticket codes stay in the expandable detail');
  assert.equal(doc.querySelectorAll('.scan-order-group>.scan-visible-note').length,1);
  assert.match(doc.querySelector('.scan-order-group>.scan-visible-note').textContent,/Společná poznámka <order>/);
  assert.match(cards[0].textContent,/Jednotlivá poznámka <ticket>/);
  assert.doesNotMatch(cards[1].textContent,/Jednotlivá poznámka/);
  assert.equal(doc.querySelector('order'),null);assert.equal(doc.querySelector('ticket'),null);
  assert.equal(doc.querySelector('[data-group-confirm]').disabled,false);
 }finally{dom.window.close();}
});

test('product titles use configured non-empty short titles and fall back consistently',async()=>{
 const {scannerProductTitle}=await import('../../src/components/scan/scanner_presentation.js');
 assert.equal(scannerProductTitle({title:'Full title',short_title:' Short '}),'Short');
 assert.equal(scannerProductTitle({title:'Full title',short_title:'  '}),'Full title');
 assert.equal(scannerProductTitle({title:'Full title'}),'Full title');
});

test('mixed order confirms only the remaining valid ticket and preserves already used and unpaid tickets',async()=>{
 const used={state:'result',ticket:{order_id:1,state:'used',admission_allowed:false},confirm:async()=>assert.fail('used ticket cannot be confirmed again')};
 let calls=0;
 const valid={state:'result',ticket:{order_id:1,state:'sent',admission_allowed:true},async confirm(){calls++;this.state='accepted';}};
 const unpaid={state:'result',ticket:{order_id:1,state:'ordered',admission_allowed:true,requires_unpaid_confirmation:true},confirm:async()=>assert.fail('unpaid ticket needs an individual decision')};
 const page={batch:[used,valid,unpaid].map((controller,index)=>({controller,symbol:`T${index}`})),storageAvailable:true,row:{locked:false},render(){},sound:{play(){}},updateAutoAdvance(){}};
 const before=new JSDOM(ScanPage.prototype.batchHtml.call(page));
 assert.match(before.window.document.querySelector('[data-group-confirm]').textContent,/\(1\)/);assert.ok(before.window.document.querySelector('[data-group-ticket="0"]').classList.contains('already-used'));before.window.close();
 await ScanPage.prototype.confirmBatch.call(page);
 assert.equal(calls,1);assert.equal(used.state,'result');assert.equal(used.ticket.state,'used');assert.equal(valid.state,'accepted');assert.equal(unpaid.state,'result');
 const after=new JSDOM(ScanPage.prototype.batchHtml.call(page));assert.equal(after.window.document.querySelector('[data-group-confirm]'),null);after.window.close();
});

test('non-seat product captions identify dinner and transport using the configured short title',async()=>{
 const {scannerProductCaption}=await import('../../src/components/scan/scanner_presentation.js');
 assert.equal(scannerProductCaption({type:'food',type_title:'Večeře',title:'Full menu',short_title:'Guláš'}),'Večeře: Guláš');
 assert.equal(scannerProductCaption({type:'other',type_title:'Odvoz',title:'Opava, Východní nádraží'}),'Odvoz: Opava, Východní nádraží');
 assert.equal(scannerProductCaption({type:'spot',type_title:'Místo',title:'VIP'}),'VIP');
});

test('different orders retain purchaser names with seats and never group by a matching name',()=>{
 const batch=[1,2].map((order_id,index)=>({symbol:`T${index}`,controller:{state:'result',ticket:{symbol:`T${index}`,holder_name:`T${index}`,purchaser_name:'Shared surname',order_id,admission_allowed:true,spot:`S1${index}`,products:[]}}}));
 const dom=new JSDOM(ScanPage.prototype.batchHtml.call({batch,storageAvailable:true,row:{locked:false}}));
 try{const cards=[...dom.window.document.querySelectorAll('[data-group-ticket]')];assert.equal(cards.length,2);for(const card of cards)assert.equal(card.querySelector('strong').textContent,'Shared surname');assert.equal(dom.window.document.querySelectorAll('.scan-order-header').length,0);assert.match(cards[0].querySelector('.scan-group-seat').textContent,/S10/);}finally{dom.window.close();}
});
