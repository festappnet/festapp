import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {FormDataLayer, analyticsPayload, publicFormLocation} from '../../src/components/forms/form_datalayer.js';
const identity='c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44';
const paid={item_id:'product_11',item_name:'Concert',price:100,quantity:2};
const purchase={event:'purchase',ecommerce:{currency:'CZK',transaction_id:identity,payment_type:'bank_transfer',items:[paid]}};
const policy={enabled:true,organization_allowed:true,runtime_supported:true,eligible:true,valid_for_seconds:60};
function fixture({analytics=policy,url='https://tickets.test/form/summer?embed=1',consent=true,session=false}={}) {
 const dom=new JSDOM('<html lang="cs"><body></body></html>',{url});
 const sent=[];let allowed=consent;
 const bridge={measurementEpoch:()=>bridge.measurementAllowed()?'fixture-lease':null,measurementAllowed:()=>allowed,track:p=>{sent.push(p);return true;},revokeMeasurement:()=>{allowed=false;}};
 const model={data:{analytics},visibleFields:[{id:4,type:'product_type',options:[{id:11,title:'Concert',price:100,currency:'CZK'},{id:12,title:'Free',price:0,currency:'CZK'}]}]};
 return {dom,sent,bridge,layer:new FormDataLayer({win:dom.window,model,bridge,session:()=>session})};
}
const events=sent=>sent.filter(p=>p.event);
for (const analytics of [undefined,{}, {gtm_container:'GTM-AB12'}, {...policy,enabled:false}, {...policy,enabled:'true'}, {...policy,organization_allowed:false}, {...policy,runtime_supported:false}, {...policy,eligible:false}]) {
 test('fail closed for incomplete/disabled policy '+JSON.stringify(analytics),()=>{
  const {dom,layer,sent}=fixture({analytics});layer.model.data.analytics=analytics;
  layer.view();layer.update({fields:[{4:11}]});layer.review({fields:[{4:11}]});layer.payment({fields:[{4:11}]},'bank');layer.confirmed({ticketOrder:{analytics:purchase}});layer.emit({event:'form_submit_error'});
  assert.deepEqual(sent,[]);assert.equal(dom.window.dataLayer,undefined);assert.equal(dom.window.document.querySelector('script'),null);dom.window.close();
 });
}
test('consent is required; no replay of events from before consent',()=>{
 const {dom,layer,sent,bridge}=fixture({consent:false});layer.view();assert.deepEqual(sent,[]);
 bridge.measurementAllowed=()=>true;layer.emit({event:'form_submit_error'});assert.deepEqual(sent,[{event:'form_submit_error'}]);dom.window.close();
});
test('catalog/cart/review/payment use catalog identity and quantity deltas without answers',()=>{
 const {dom,layer,sent}=fixture();layer.view();layer.update({fields:[{4:11},{email:'private'}],ticket:[{fields:[{product_type:11}]}]});layer.update({fields:[{4:12}]});layer.review({fields:[{4:11}]});layer.payment({fields:[{4:11}]},'stripe');
 assert.deepEqual(events(sent).map(p=>p.event),['page_view','view_item','add_to_cart','add_to_cart','remove_from_cart','page_view','begin_checkout','add_payment_info']);
 assert.equal(events(sent)[2].ecommerce.items[0].quantity,2);assert.equal(sent.at(-1).ecommerce.payment_type,'card');assert(!JSON.stringify(sent).includes('private'));assert.equal(dom.window.dataLayer,undefined);dom.window.close();
});
for(const conversion of [purchase,{event:'generate_lead',event_id:identity,currency:'CZK',value:0,lead_source:'waitlist'},{event:'generate_lead',event_id:identity,currency:'EUR',value:0,lead_source:'free_registration'}]) {
 test('confirmed server conversion deduplicates callbacks without browser storage: '+conversion.event+conversion.lead_source,()=>{
  const {dom,layer,sent}=fixture();Object.defineProperty(dom.window,'localStorage',{get(){throw Error('denied');}});
  layer.confirmed({ticketOrder:{analytics:conversion}});layer.confirmed({ticketOrder:{analytics:conversion}});
  assert.equal(events(sent).filter(p=>p.event===conversion.event).length,1);assert.equal(events(sent).at(-1).ecommerce?.transaction_id||events(sent).at(-1).event_id,identity);dom.window.close();
 });
}
test('failed delivery does not consume conversion identity, absence of server facts does not synthesize a lead',()=>{
 const {dom,layer,bridge,sent}=fixture();layer.confirmed({ticketOrder:{order:{payment_info:{amount:0}}}},true);assert.deepEqual(sent,[]);
 bridge.track=()=>false;layer.confirmed({ticketOrder:{analytics:purchase}});bridge.track=p=>{sent.push(p);return true;};layer.confirmed({ticketOrder:{analytics:purchase}});assert.equal(events(sent).filter(p=>p.event==='purchase').length,1);dom.window.close();
});
test('expiry, foreground invalidation and dispose stop emission; analytics errors never throw',()=>{
 const {dom,layer,sent,bridge}=fixture();bridge.track=()=>{throw Error('consumer');};assert.equal(layer.emit({event:'page_view'}),false);
 bridge.track=p=>{sent.push(p);return true;};layer.policyExpiresAt=Date.now()-1;assert.equal(layer.emit({event:'page_view'}),false);
 layer.policyExpiresAt=Date.now()+60000;dom.window.document.dispatchEvent(new dom.window.Event('visibilitychange'));assert.equal(layer.emit({event:'page_view'}),false);layer.dispose();assert.equal(layer.emit({event:'page_view'}),false);assert.deepEqual(sent,[]);dom.window.close();
});
for(const url of ['https://tickets.test/admin','https://tickets.test/form/summer?token=secret','https://tickets.test/form/summer?preview=true','https://tickets.test/form/summer#access_token=private'])test('private context is ineligible '+url,()=>{
 const {dom,layer,sent}=fixture({url});layer.view();assert.deepEqual(sent,[]);dom.window.close();
});
test('session, demo and all contact paths fail closed',()=>{
 const {dom,layer,sent}=fixture({session:true});layer.view();assert.deepEqual(sent,[]);assert.equal(layer.contact,undefined);
 layer.session=()=>false;layer.model.demoSimulation=true;layer.view();assert.deepEqual(sent,[]);dom.window.close();
});
test('shared payload contract strips secrets and contacts, validates identities and cents',()=>{
 const dirty={...purchase,user_data:{email:'secret'},token:'secret',ecommerce:{...purchase.ecommerce,value:999,url:'secret',items:[{...paid,email:'secret'}]}};
 assert.deepEqual(analyticsPayload(dirty,{allowUserData:true}),analyticsPayload(purchase));
 assert.equal(analyticsPayload({...purchase,ecommerce:{...purchase.ecommerce,transaction_id:'1A2C3E4F5G'}}),null);
 assert.equal(analyticsPayload({event:'generate_lead',currency:'CZK',value:0,lead_source:'waitlist'}),null);
 for(const items of [[],[{...paid,quantity:0}],[{...paid,item_id:'seat_1'}],new Array(201).fill(paid)])assert.equal(analyticsPayload({...purchase,ecommerce:{...purchase.ecommerce,items}}),null);
 assert.equal(analyticsPayload({event:'view_item',ecommerce:{currency:'CZK',items:[{...paid,price:0.1,quantity:3}]}}).ecommerce.value,0.3);
 assert.equal(publicFormLocation(new URL('https://tickets.test/form/a?unknown=secret')),false);
});

for (const initialConsent of [false,true]) test(`pending reservation cannot cross consent grant epochs (initial=${initialConsent})`,async()=>{
 const {dom,layer,bridge,sent}=fixture({consent:initialConsent});
 bridge.consentId='first';bridge.measurementEpoch=()=>bridge.measurementAllowed()?bridge.consentId:null;
 let finish;const session={payload:{fields:[{4:11}]},awaitPendingReservations:()=>new Promise(resolve=>{finish=resolve;})};
 layer.observe(session);await Promise.resolve();
 bridge.consentId='second';bridge.measurementAllowed=()=>true;finish();
 await new Promise(resolve=>setImmediate(resolve));assert.deepEqual(sent,[]);
 layer.update({fields:[{4:12}]});assert.equal(events(sent).filter(p=>p.event==='add_to_cart').length,1);
 assert.equal(events(sent).find(p=>p.event==='add_to_cart').ecommerce.items[0].item_id,'product_12');dom.window.close();
});
for(const conversion of [purchase,{event:'generate_lead',event_id:identity,currency:'CZK',value:0,lead_source:'waitlist'}])test(`observed pre-consent ${conversion.event} is never retried after grant`,()=>{
 const {dom,layer,bridge,sent}=fixture({consent:false});bridge.consentId=null;bridge.measurementEpoch=()=>bridge.measurementAllowed()?bridge.consentId:null;
 layer.confirmed({ticketOrder:{analytics:conversion}});
 bridge.consentId='new';bridge.measurementAllowed=()=>true;layer.confirmed({ticketOrder:{analytics:conversion}});
 assert.deepEqual(sent,[]);dom.window.close();
});
test('failed conversion delivery can retry in its original lease but not a later grant',()=>{
 const {dom,layer,bridge,sent}=fixture();bridge.consentId='first';bridge.measurementEpoch=()=>bridge.consentId;
 bridge.track=()=>false;layer.confirmed({ticketOrder:{analytics:purchase}});
 bridge.consentId='second';bridge.track=p=>{sent.push(p);return true;};layer.confirmed({ticketOrder:{analytics:purchase}});
 assert.deepEqual(sent,[]);dom.window.close();
});
test('failing transport eligibility checks cannot throw into checkout callbacks',()=>{
 const {dom,layer,bridge}=fixture();bridge.measurementAllowed=()=>{throw Error('unavailable transport');};bridge.measurementEpoch=()=>{throw Error('unavailable transport');};
 assert.doesNotThrow(()=>{layer.view();layer.review({});layer.payment({},'bank');layer.confirmed({ticketOrder:{analytics:purchase}});});dom.window.close();
});
for(const event of ['pagehide','pageshow'])test(`page lifecycle ${event} invalidates retained policy before bfcache reuse`,()=>{
 const {dom,layer,sent}=fixture();assert.equal(layer.enabled(),true);
 dom.window.dispatchEvent(new dom.window.PageTransitionEvent(event,{persisted:true}));
 assert.equal(layer.enabled(),false);layer.view();assert.deepEqual(sent,[]);layer.dispose();dom.window.close();
});

test('renewed policy preserves a pending reservation in its existing consent epoch',async()=>{
 const {dom,layer,sent,bridge}=fixture();Object.defineProperty(dom.window.document,'hidden',{value:false});
 let finish;layer.observe({payload:{fields:[{4:11}]},awaitPendingReservations:()=>new Promise(resolve=>finish=resolve)});await Promise.resolve();
 let updated=0;bridge.updatePolicy=()=>updated++;layer.refreshPolicy=async()=>({...policy});
 await layer.renewPolicy();finish();await new Promise(resolve=>setImmediate(resolve));
 assert.equal(updated,1);assert.equal(events(sent).filter(value=>value.event==='add_to_cart').length,1);
 layer.dispose();dom.window.close();
});
test('denied renewal revokes the transport, and a late renewal cannot revive a disposed owner',async()=>{
 const {dom,layer,bridge}=fixture();Object.defineProperty(dom.window.document,'hidden',{value:false});
 layer.refreshPolicy=async()=>({...policy,eligible:false});await layer.renewPolicy();assert.equal(layer.enabled(),false);assert.equal(bridge.measurementAllowed(),false);
 let finish,updated=0;bridge.updatePolicy=()=>updated++;layer.refreshPolicy=()=>new Promise(resolve=>finish=resolve);
 const pending=layer.renewPolicy();layer.dispose();finish({...policy});await pending;assert.equal(updated,0);dom.window.close();
});

test('disabled and private forms do not create a measurement policy polling timer',()=>{
 for (const [analytics,url] of [[{...policy,enabled:false,eligible:false},'https://tickets.test/form/a'],[policy,'https://tickets.test/form/a?token=private']]) {
  const dom=new JSDOM('<body></body>',{url,pretendToBeVisual:true});let timers=0;dom.window.setInterval=()=>{timers++;return 1;};
  const layer=new FormDataLayer({win:dom.window,model:{data:{analytics}},session:()=>false,refreshPolicy:async()=>policy});
  assert.equal(timers,0);layer.dispose();dom.window.close();
 }
});
