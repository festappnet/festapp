import test from 'node:test';
import assert from 'node:assert/strict';
import {overviewItemChanges} from '../../src/components/forms/order_overview_details.js';
test('history diff preserves duplicate instances and separates tickets',()=>{
 const a={ticketId:1,id:10,title:'Dinner',price:100}, b={...a,ticketId:2};
 const result=overviewItemChanges([a,a,b],[a,{...b,price:150},{ticketId:2,id:11,title:'Seat',price:50}]);
 assert.deepEqual(result.map(c=>c.kind),['removed','changed','added']);
 assert.equal(result[0].before.ticketId,1);
 assert.equal(result[1].before.price,100); assert.equal(result[1].after.price,150);
 assert.deepEqual(overviewItemChanges([a,b],[b,a]),[]);
});

test('product row shows table and seat beside the correct price without interpreting labels as HTML', async () => {
 const {JSDOM}=await import('jsdom');
 const {renderOverviewProducts}=await import('../../src/components/forms/order_overview_details.js');
 const dom=new JSDOM('<main></main>'); globalThis.document=dom.window.document;
 try {
  const host=document.querySelector('main');
  renderOverviewProducts(host,[{title:'Místo',price:450,spotGroupTitle:'7',spotTitle:'<b>3</b>'},{title:'Lunch',price:100}],'CZK',(price,currency)=>`${price} ${currency}`);
  const details=host.querySelectorAll('.overview-product-seating');
  assert.equal(details.length,1); assert.match(details[0].textContent,/7.*<b>3<\/b>/);
  assert.equal(details[0].querySelector('b'),null);
  assert.match(details[0].closest('li').textContent,/450 CZK/);
 } finally {dom.window.close();delete globalThis.document;}
});
