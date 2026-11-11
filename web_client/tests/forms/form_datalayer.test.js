import test from 'node:test';
import assert from 'node:assert/strict';
import {analyticsPayload} from '../../src/components/forms/form_measurement_contract.js';
import {publicFormLocation} from '../../src/utils/public_form_location.js';
import {fixture,purchase} from '../support/measurement_fixture.js';
const paid={item_id:'product_11',item_name:'Concert',price:100,quantity:2};
test('item labels are optional, bounded, contact-free and never change item identity or value',()=>{
 const label=(item_category,item_brand)=>({...paid,item_category,item_brand});
 const payload=item=>analyticsPayload({...purchase,ecommerce:{...purchase.ecommerce,items:[item]}}).ecommerce;
 assert.deepEqual(analyticsPayload(purchase).ecommerce.items,[paid],'stored facts without labels remain valid and unchanged');
 assert.deepEqual(payload(label('  VIP  ','Letní fest')).items,[{...paid,item_category:'VIP',item_brand:'Letní fest'}]);
 assert.equal(payload(label('x'.repeat(101),'y'.repeat(100))).items[0].item_category,'x'.repeat(100));
 assert.equal(payload(label('x'.repeat(101),'y'.repeat(100))).items[0].item_brand,'y'.repeat(100));
 for(const unsafe of ['mail@example.test','a\nb','a\u007fb','a\u0085b','   ','',7,null,{title:'x'},['x']]){
  const result=payload(label(unsafe,unsafe));
  assert.deepEqual(result.items,[paid],JSON.stringify(unsafe));assert.equal(result.value,200);
 }
 const extra=payload({...paid,item_variant:'L',coupon:'SECRET',discount:50,affiliation:'Organizer',item_list_name:'x'}).items[0];
 assert.deepEqual(extra,paid,'fields without a verified Festapp source are not forwarded');
});
test('shared payload contract strips secrets and contacts, validates identities and cents',()=>{
 const dirty={...purchase,user_data:{email:'secret'},token:'secret',ecommerce:{...purchase.ecommerce,value:999,url:'secret',items:[{...paid,email:'secret'}]}};
 assert.deepEqual(analyticsPayload(dirty),analyticsPayload(purchase));
 assert.equal(analyticsPayload({...purchase,ecommerce:{...purchase.ecommerce,transaction_id:'1A2C3E4F5G'}}),null);
 assert.equal(analyticsPayload({event:'generate_lead',currency:'CZK',value:0,lead_source:'waitlist'}),null);
 for(const items of [[],[{...paid,quantity:0}],[{...paid,item_id:'seat_1'}],new Array(201).fill(paid)])assert.equal(analyticsPayload({...purchase,ecommerce:{...purchase.ecommerce,items}}),null);
 assert.equal(analyticsPayload({event:'view_item',ecommerce:{currency:'CZK',items:[{...paid,price:0.1,quantity:3}]}}).ecommerce.value,0.3);
 assert.equal(publicFormLocation(new URL('https://tickets.test/form/a?unknown=secret')),false);
});


test('catalog/cart/review/payment retain labels, price and currency without answers',async t=>{
 const f=fixture(t);await f.start();f.layer.update({fields:[{4:11},{email:'PRIVATE'}],ticket:[{fields:[{product_type:11}]}]});
 f.layer.update({fields:[{4:12}]});f.layer.review({fields:[{4:11}]});f.layer.payment({fields:[{4:11}]},'stripe');
 assert.deepEqual(f.sent.filter(p=>p.event).map(p=>p.event),['page_view','view_item','add_to_cart','add_to_cart','remove_from_cart','page_view','begin_checkout','add_payment_info']);
 assert.equal(f.sent.at(-1).ecommerce.payment_type,'card');assert.equal(f.sent.at(-1).ecommerce.items[0].item_brand,'Letní fest');
 assert.equal(f.sent.at(-1).ecommerce.items[0].item_category,'Vstupenky');assert(!JSON.stringify(f.sent).includes('PRIVATE'));
 const seat={id:21,title:'Sedadlo',price:50,currency_code:'CZK',type_title:'Sezení'};
 f.layer.update({ticket:[{spot:7},{fields:[{product_type:22}]}]}, {spotModels:new Map([['7',{productModel:seat}]]),state:{tickets:[{},{_blueprintProduct:{...seat,id:22,title:'Stání',type_title:'Stání'}}]}});
 assert.deepEqual(f.sent.filter(p=>p.event==='add_to_cart').at(-1).ecommerce.items.map(p=>[p.item_id,p.item_category]),[['product_21','Sezení'],['product_22','Stání']]);
});
for(const conversion of [purchase,{event:'generate_lead',event_id:'c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44',currency:'CZK',value:0,lead_source:'waitlist'},
 {event:'generate_lead',event_id:'c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44',currency:'EUR',value:0,lead_source:'free_registration'}])test('confirmed SQL conversion deduplicates '+conversion.event+conversion.lead_source,async t=>{
 const f=fixture(t);await f.start();const outcome=f.layer.captureSubmission();outcome(true,{ticketOrder:{analytics:conversion}});outcome(true,{ticketOrder:{analytics:conversion}});
 assert.equal(f.sent.filter(p=>p.event===conversion.event).length,1);
});
test('accepted page and form-start deduplicate across renewed grants; no synthetic conversion',async t=>{
 const f=fixture(t);await f.start();f.layer.started();f.choose(false);f.layer.started();f.choose({analytics:true,marketing:true});f.layer.started();
 f.layer.captureSubmission()(true,{ticketOrder:{order:{payment_info:{amount:0}}}});
 assert.equal(f.sent.filter(p=>p.event==='form_start').length,1);assert.equal(f.sent.filter(p=>p.event==='page_view').length,1);
 assert.equal(f.sent.some(p=>['purchase','generate_lead'].includes(p.event)),false);
});
