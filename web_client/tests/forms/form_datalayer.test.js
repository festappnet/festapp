import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {FormDataLayer} from '../../src/components/forms/form_datalayer.js';
import {analyticsPayload} from '../../src/components/forms/form_measurement_contract.js';
import {publicFormLocation} from '../../src/utils/public_form_location.js';
import {normalizeE164Phone} from '../../src/utils/phone_formatter.js';
const identity='c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44';
const paid={item_id:'product_11',item_name:'Concert',price:100,quantity:2};
const purchase={event:'purchase',ecommerce:{currency:'CZK',transaction_id:identity,payment_type:'bank_transfer',items:[paid]}};
const policy={enabled:true,organization_allowed:true,runtime_supported:true,privacy_url:"https://organizer.example/privacy",eligible:true,valid_for_seconds:60};
function fixture({analytics=policy,url='https://tickets.test/form/summer?embed=1',ready=true,session=false,data={},occasionTitle,productTypeData}={}) {
 const dom=new JSDOM('<html lang="cs"><body></body></html>',{url});
 const sent=[];let allowed=ready;
 const bridge={measurementAllowed:()=>allowed,track:p=>{sent.push(p);return true;},revokeMeasurement:()=>{allowed=false;},updatePolicy(){allowed=ready;}};
 const model={data:{analytics,...data},occasionTitle,visibleFields:[{id:4,type:'product_type',productTypeData,options:[{id:11,title:'Concert',price:100,currency:'CZK'},{id:12,title:'Free',price:0,currency:'CZK'}]},{id:5,type:'email'},{id:6,type:'phone'}]};
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
test('nothing is queued before the transport is ready, whatever the consent state',()=>{
 const {dom,layer,sent,bridge}=fixture({ready:false});layer.view();assert.deepEqual(sent,[]);
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
test('expiry and dispose stop emission, hiding the page does not; analytics errors never throw',()=>{
 const {dom,layer,sent,bridge}=fixture();bridge.track=()=>{throw Error('consumer');};assert.equal(layer.emit({event:'page_view'}),false);
 bridge.track=p=>{sent.push(p);return true;};layer.policyExpiresAt=Date.now()-1;assert.equal(layer.emit({event:'page_view'}),false);
 layer.policyExpiresAt=Date.now()+60000;dom.window.document.dispatchEvent(new dom.window.Event('visibilitychange'));assert.equal(layer.emit({event:'page_view'}),true);sent.length=0;layer.dispose();assert.equal(layer.emit({event:'page_view'}),false);assert.deepEqual(sent,[]);dom.window.close();
});
for(const url of ['https://tickets.test/admin','https://tickets.test/form/summer?token=secret','https://tickets.test/form/summer?preview=true','https://tickets.test/form/summer#access_token=private'])test('private context is ineligible '+url,()=>{
 const {dom,layer,sent}=fixture({url});layer.view();assert.deepEqual(sent,[]);dom.window.close();
});
test('a session the server has not named, and demo mode, fail closed',()=>{
 const {dom,layer,sent}=fixture({session:true});layer.view();assert.deepEqual(sent,[]);assert.equal(layer.contact({fields:[{5:'private@example.test'}]}),null);
 layer.session=()=>false;layer.model.demoSimulation=true;layer.view();assert.deepEqual(sent,[]);dom.window.close();
});
test('every browser event carries product type and occasion labels, including seat and area products',()=>{
 const {dom,layer,sent}=fixture({occasionTitle:'Letní fest',productTypeData:{title:'Vstupenky'}});
 const labels={item_category:'Vstupenky',item_brand:'Letní fest'};
 layer.view();layer.update({fields:[{4:11}]});layer.review({fields:[{4:11}]});layer.payment({fields:[{4:11}]},'bank');
 for(const event of ['view_item','add_to_cart','begin_checkout','add_payment_info']){
  const item=events(sent).find(p=>p.event===event).ecommerce.items[0];assert.deepEqual({item_category:item.item_category,item_brand:item.item_brand},labels,event);
 }
 const seat={id:21,title:'Sedadlo',price:50,currency_code:'CZK',type_title:'Sezení'};
 const session={spotModels:new Map([['7',{productModel:seat}]]),state:{tickets:[{},{_blueprintProduct:{...seat,id:22,title:'Stání',type_title:'Stání'}}]}};
 layer.update({ticket:[{spot:7},{fields:[{product_type:22}]}]},session);
 const added=events(sent).filter(p=>p.event==='add_to_cart').at(-1).ecommerce.items;
 assert.deepEqual(added.map(item=>[item.item_id,item.item_category,item.item_brand]),[['product_21','Sezení','Letní fest'],['product_22','Stání','Letní fest']]);
 layer.update({ticket:[{spot:7}]},{spotModels:new Map([['7',{productModel:{...seat,type_title:undefined}}]])});
 assert.equal(layer.catalog.get('21').item_category,'Sezení','a sparse seat model keeps the known catalog label');
 dom.window.close();
});
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

test('a cart observed before the transport is ready becomes the baseline, not a change',async()=>{
 const {dom,layer,bridge,sent}=fixture({ready:false});
 let finish;const session={payload:{fields:[{4:11}]},awaitPendingReservations:()=>new Promise(resolve=>{finish=resolve;})};
 layer.observe(session);await Promise.resolve();finish();
 await new Promise(resolve=>setImmediate(resolve));assert.deepEqual(sent,[]);
 bridge.measurementAllowed=()=>true;layer.update({fields:[{4:11},{4:12}]});assert.equal(events(sent).filter(p=>p.event==='add_to_cart').length,1);dom.window.close();
});
test('a conversion missed while the transport was not ready is delivered once by a later callback',()=>{
 const {dom,layer,bridge,sent}=fixture({ready:false});
 layer.confirmed({ticketOrder:{analytics:purchase}});assert.deepEqual(sent,[]);
 bridge.measurementAllowed=()=>true;layer.confirmed({ticketOrder:{analytics:purchase}});layer.confirmed({ticketOrder:{analytics:purchase}});
 assert.equal(events(sent).filter(p=>p.event==='purchase').length,1);dom.window.close();
});
test('failing transport eligibility checks cannot throw into checkout callbacks',()=>{
 const {dom,layer,bridge}=fixture();bridge.measurementAllowed=()=>{throw Error('unavailable transport');};
 assert.doesNotThrow(()=>{layer.view();layer.review({});layer.payment({},'bank');layer.confirmed({ticketOrder:{analytics:purchase}});});dom.window.close();
});
test('hiding the page and returning from bfcache keep the frame and recheck policy',async()=>{
 const {dom,layer,bridge}=fixture();Object.defineProperty(dom.window.document,'hidden',{value:false});let renewals=0,revoked=0;layer.refreshPolicy=async()=>{renewals++;return {...policy,valid_for_seconds:60};};const revoke=bridge.revokeMeasurement;bridge.revokeMeasurement=()=>{revoked++;revoke();};
 dom.window.dispatchEvent(new dom.window.PageTransitionEvent('pagehide',{persisted:true}));assert.equal(layer.enabled(),true);assert.equal(renewals,0);
 dom.window.dispatchEvent(new dom.window.PageTransitionEvent('pageshow',{persisted:true}));await Promise.resolve();assert.equal(renewals,1);
 await new Promise(resolve=>setImmediate(resolve));dom.window.document.dispatchEvent(new dom.window.Event('visibilitychange'));assert.equal(renewals,2);
 await new Promise(resolve=>setImmediate(resolve));assert.equal(revoked,0);layer.dispose();dom.window.close();
});
test('a failed recheck after returning removes the frame',async()=>{
 const {dom,layer,bridge}=fixture();Object.defineProperty(dom.window.document,'hidden',{value:false});let revoked=0;layer.refreshPolicy=async()=>{throw Error('denied');};bridge.revokeMeasurement=()=>revoked++;
 dom.window.document.dispatchEvent(new dom.window.Event('visibilitychange'));await new Promise(resolve=>setImmediate(resolve));
 assert.equal(revoked,1);assert.equal(layer.enabled(),false);layer.dispose();dom.window.close();
});

test('renewed policy preserves a pending reservation',async()=>{
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

test('view events retry failed sends and new frames get current context only',()=>{
 const {dom,layer,bridge,sent}=fixture();
 bridge.track=()=>false;layer.view();assert.equal(layer.viewedPages.size,0);assert.equal(layer.viewedCurrencies.size,0);
 bridge.track=p=>{sent.push(p);return p.event!=='view_item';};layer.view();
 assert.deepEqual([...layer.viewedPages],['product']);assert.equal(layer.viewedCurrencies.size,0);
 sent.length=0;bridge.track=p=>{sent.push(p);return true;};layer.view();layer.view();
 assert.deepEqual(events(sent).map(p=>p.event),['view_item']);
 layer.review({fields:[{4:11}]});assert.equal(events(sent).filter(p=>p.event==='page_view').length,1,'checkout is its own page_view');sent.length=0;layer.view();
 assert.deepEqual(sent,[{page_type:'checkout',user_type:'b2c',language:'cs'}]);
 layer.page('product');layer.review({fields:[{4:11}]});assert.equal(events(sent).filter(p=>p.event==='page_view').length,0,'back and repeated review add no page_view');
 layer.confirmed({ticketOrder:{analytics:purchase}});assert.equal(events(sent).filter(p=>p.event==='page_view').length,1,'confirmation is its own page_view');sent.length=0;layer.view();
 assert.deepEqual(sent,[{page_type:'confirmation',user_type:'b2c',language:'cs'}]);dom.window.close();
});

test('form_start waits for the transport, fires once and carries no field data',()=>{
 const {dom,layer,bridge,sent}=fixture({ready:false});
 layer.started();assert.deepEqual(sent,[]);
 bridge.measurementAllowed=()=>true;layer.started();layer.started();
 assert.deepEqual(sent,[{event:'form_start'}]);
 assert.deepEqual(analyticsPayload({event:'form_start',email:'private@example.com',field:'name'}),{event:'form_start'});dom.window.close();
});

test('host dataLayer transport respects SQL no_privacy_policy denial',()=>{
 const {dom,layer,sent}=fixture({analytics:{...policy,eligible:false,privacy_url:null,blocked_reasons:['no_privacy_policy']}});
 try {
  layer.view();
  layer.confirmed({ticketOrder:{analytics:purchase}});
  assert.equal(layer.enabled(),false);
  assert.deepEqual(sent,[]);
 } finally {layer.dispose();dom.window.close();}
});

const lead={event:'generate_lead',event_id:identity,currency:'CZK',value:0,lead_source:'free_registration'};
const answers={fields:[{5:'  Visitor@Example.TEST '},{6:'+420 601 234 567'}]};
const contact={email:'visitor@example.test',phone_number:'+420601234567'};

test('contract passes only a bounded e-mail and E.164 phone, only on the two conversions',()=>{
 const user_data={...contact,first_name:'Private',address:{city:'Private'},sha256_email_address:'a'.repeat(64)};
 assert.deepEqual(analyticsPayload({...purchase,user_data}).user_data,contact);
 assert.deepEqual(analyticsPayload({...lead,user_data}).user_data,contact);
 assert.deepEqual(analyticsPayload({...purchase,user_data:{email:'a@'+'b'.repeat(249)+'.cz'}}).user_data,{email:'a@'+'b'.repeat(249)+'.cz'},'254 characters');
 for(const email of ['a@'+'b'.repeat(250)+'.cz','no-at-sign','a b@example.test','a@b','a@example.test\n','a\u0000@example.test',1,null,{}])
  assert.deepEqual(analyticsPayload({...purchase,user_data:{email,phone_number:contact.phone_number}}).user_data,{phone_number:contact.phone_number},String(email));
 for(const phone_number of ['601234567','420601234567','+0601234567','+420 601 234 567','+1234567','+1234567890123456',601234567,null])
  assert.deepEqual(analyticsPayload({...purchase,user_data:{email:contact.email,phone_number}}).user_data,{email:contact.email},String(phone_number));
 assert.equal(analyticsPayload({...purchase,user_data:{email:'bad',phone_number:'bad'}}).user_data,undefined);
 for(const event of ['view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info'])
  assert.equal(analyticsPayload({...purchase,event,user_data}).user_data,undefined,event);
 for(const event of ['page_view','form_start','form_submit_error']) assert.deepEqual(analyticsPayload({event,user_data}),{event});
 assert.equal(analyticsPayload({page_type:'checkout',user_data}).user_data,undefined);
});

test('normalized contact reaches the transport on the two conversions and no other event',()=>{
 for(const conversion of [purchase,lead]) {
  const {dom,layer,sent}=fixture();
  layer.view();layer.update({fields:[{4:11}]});layer.confirmed({ticketOrder:{analytics:conversion}},layer.contact(answers));
  assert.deepEqual(sent.find(p=>p.event===conversion.event).user_data,contact);
  assert.equal(sent.filter(p=>p.user_data).length,1,'no other event carries it');dom.window.close();
 }
});

test('host transport hands contact only to an approved origin; other hosts still get the event',()=>{
 const approved={...policy,approved_hosts:['https://approved.example']};
 for(const [analytics,host,expected] of [[approved,'https://approved.example',contact],[approved,'https://evil.example',undefined],[policy,'https://approved.example',undefined],[{...policy,approved_hosts:'https://approved.example'},'https://approved.example',undefined]]) {
  const {dom,layer,sent,bridge}=fixture({analytics});bridge.dataLayerHost=()=>host;
  layer.confirmed({ticketOrder:{analytics:purchase}},contact);
  assert.equal(events(sent).at(-1).event,'purchase');assert.deepEqual(events(sent).at(-1).user_data,expected,host);dom.window.close();
 }
 const frame=fixture();frame.bridge.dataLayerHost=()=>null;assert.equal(frame.layer.contactAllowed(),true,'frame ancestors are enforced by CSP');frame.dom.window.close();
});

const settled=()=>new Promise(resolve=>setImmediate(resolve));
function signedIn(role,options={}){
 let answer={...policy,visitor_role:role};
 const value=fixture({session:true,...options});
 value.layer.refreshPolicy=async()=>{value.calls=(value.calls||0)+1;if(answer instanceof Error)throw answer;return answer;};
 value.answer=next=>{answer=next;};
 return value;
}

test('a signed-in ordinary visitor is measured once the server names the role, with contact',async()=>{
 const {dom,layer,sent}=signedIn('visitor');
 layer.view();assert.deepEqual(sent,[],'nothing before the role is known');
 assert.equal(await layer.visitorReady(),true);assert.ok(events(sent).some(p=>p.event==='page_view'));
 layer.confirmed({ticketOrder:{analytics:purchase}},layer.contact(answers));assert.deepEqual(events(sent).at(-1).user_data,contact);dom.window.close();
});

for(const role of ['staff','anonymous',undefined,'admin']) test('signed-in role '+role+' is not measured',async()=>{
 const {dom,layer,sent}=signedIn(role);
 assert.equal(await layer.visitorReady(),false);layer.view();layer.emit({event:'form_start'});
 assert.deepEqual(sent,[]);assert.equal(layer.contact(answers),null);dom.window.close();
});

test('a failed role check is not measured',async()=>{
 const {dom,layer,sent,answer}=signedIn('visitor');answer(new Error('offline'));
 assert.equal(await layer.visitorReady(),false);layer.view();assert.deepEqual(sent,[]);dom.window.close();
});

test('staff signing in during a visit stops measurement for the page, for good',async()=>{
 const {dom,layer,bridge,sent,answer}=signedIn('visitor',{session:false});
 layer.authChanged(null);let revoked=0;const revoke=bridge.revokeMeasurement;bridge.revokeMeasurement=()=>{revoked++;revoke();};
 layer.session=()=>true;answer({...policy,visitor_role:'staff'});
 layer.authChanged('staff-user');assert.equal(layer.emit({event:'page_view'}),false,'nothing is sent while the role is unknown');
 await settled();assert.ok(revoked>0);assert.equal(layer.staff,true);
 bridge.measurementAllowed=()=>true;sent.length=0;layer.session=()=>false;layer.view();assert.deepEqual(sent,[],'signing out does not resume this page');dom.window.close();
});

test('an ordinary visitor signing in resumes after the check; token refresh changes nothing',async()=>{
 const value=signedIn('visitor',{session:false}),{dom,layer,bridge,sent}=value;
 layer.authChanged(null);layer.authChanged(null);assert.equal(value.calls,undefined,'same identity is not a change');
 layer.session=()=>true;layer.authChanged('user-1');await settled();assert.equal(value.calls,1);
 bridge.measurementAllowed=()=>true;assert.equal(layer.emit({event:'page_view'}),true);
 layer.authChanged('user-1');await settled();assert.equal(value.calls,1,'token refresh keeps the frame');assert.equal(sent.length>0,true);dom.window.close();
});

test('no token or session value reaches the transport',async()=>{
 const secret='eyJ_JWT_SENTINEL',value=signedIn('visitor'),{dom,layer,sent}=value;
 dom.window.localStorage.setItem('sb-festapp-auth-token',JSON.stringify({access_token:secret,refresh_token:secret}));
 await layer.visitorReady();layer.view();layer.confirmed({ticketOrder:{analytics:{...purchase,access_token:secret,user_data:{...contact,token:secret}}}},layer.contact(answers));
 assert.ok(events(sent).length>0);assert.equal(JSON.stringify(sent).includes(secret),false);dom.window.close();
});

test('a missing or unusable answer leaves only that field out',()=>{
 const {dom,layer}=fixture();
 assert.deepEqual(layer.contact({fields:[{5:'no-at-sign'},{6:'601234567'}]}),{email:null,phone_number:null});
 assert.deepEqual(layer.contact({fields:[{6:'00420601234567'}]}),{email:null,phone_number:'+420601234567'});dom.window.close();
 const single=fixture({data:{phone_prefixes:['+421']}});
 assert.equal(single.layer.contact({fields:[{6:'901 234 567'}]}).phone_number,'+421901234567');single.dom.window.close();
});

test('a malformed payload cannot throw into order submission',()=>{
 const {dom,layer}=fixture();
 for(const payload of [{fields:[null]},{fields:'x'},{fields:[{get 5(){throw Error('answer');}}]}]) assert.equal(layer.contact(payload),null);
 assert.deepEqual(layer.contact(undefined),{email:null,phone_number:null});dom.window.close();
});

test('E.164 adapter keeps a known country and refuses to guess',()=>{
 for(const [value,expected] of [['+420 601 234 567','+420601234567'],['00421 901-234-567','+421901234567'],['420601234567','+420601234567'],['+4915112345678','+4915112345678'],
  ['601234567',null],['+420',null],['+420 (0) 601 234 567',null],['+0123456789',null],['0601234567',null],['abc',null],[undefined,null]]) assert.equal(normalizeE164Phone(value),expected,String(value));
 assert.equal(normalizeE164Phone('601234567',{defaultPrefix:'+420'}),'+420601234567');
 assert.equal(normalizeE164Phone('601234567',{defaultPrefix:'+48'}),null);
});
