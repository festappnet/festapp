import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture,policy,purchase,settle} from '../support/measurement_fixture.js';

for(const role of ['visitor','staff','anonymous',undefined,'admin'])test('delayed real construction/start and signed-in role '+role,async t=>{
 let resolve,calls=0;const f=fixture(t,{identity:'user',source:()=>{calls++;return new Promise(r=>resolve=r);}});
 assert.equal(calls,0,'constructor is inert');f.session.start();
 const first=f.session.refresh(),second=f.session.refresh();assert.equal(first,second,'waiters share the in-flight request');
 await settle();assert.equal(calls,1);assert.equal(f.starts.length,0);
 resolve({...policy,visitor_role:role});await first;
 assert.equal(f.session.record({event:'form_start'}),role==='visitor');assert.equal(f.starts.length,role==='visitor'?1:0);
});
for(const [consent,state] of [[null,{analytics:false,marketing:false}],[false,{analytics:false,marketing:false}],[true,{analytics:true,marketing:false}],[{analytics:true},{analytics:true,marketing:false}],[{marketing:true},{analytics:false,marketing:true}],[{analytics:'true',marketing:true},{analytics:false,marketing:true}]])test('consent never gates measurement '+JSON.stringify(consent),async t=>{
 const f=fixture(t,{consent});await f.start();assert.equal(f.starts.length,1);assert.equal(f.session.record({event:'page_view'}),true);
 assert.deepEqual(f.starts[0].consent,state);
});
test('a later choice reaches the transport as state and keeps grant, frame and captured senders',async t=>{
 const f=fixture(t,{consent:false});const updates=[];f.transport.updateConsent=value=>updates.push(value);await f.start();
 const send=f.session.capture(),grant=f.transport.grant;f.choose({analytics:true,marketing:true});f.choose({analytics:true,marketing:true});f.choose(false);
 assert.deepEqual(updates,[{analytics:true,marketing:true},{analytics:false,marketing:false}]);
 assert.equal(f.transport.grant,grant);assert.equal(f.starts.length,1);assert.equal(send({event:'form_start'}),true);
});
test('policy error recovers; stale identity response and finally cannot replace current request',async t=>{
 const queue=[];const f=fixture(t,{source:()=>new Promise((resolve,reject)=>queue.push({resolve,reject}))});
 f.session.start();await settle();queue[0].reject(Error('offline'));await settle();assert.equal(f.starts.length,0);
 const recovery=f.session.refresh();await settle();f.identity('user-b');await settle();assert.equal(queue.length,3);
 queue[1].resolve({...policy,visitor_role:'staff'});await recovery;
 const current=f.session.refresh();assert.equal(queue.length,3,'old finally did not clear newer request');
 queue[2].resolve({...policy,visitor_role:'visitor'});await current;assert.equal(f.session.state,'active');
 f.identity('anonymous');await settle();queue[3].resolve(policy);await settle();assert.equal(f.session.state,'active','staff/error is not terminal');
});
test('equivalent renewal keeps generation; processing, runtime and policy revisions revoke old senders',async t=>{
 let answer={...policy};const f=fixture(t,{source:async()=>answer});await f.start();
 const sender=f.session.capture(),generation=f.session.generation;await f.session.refresh();
 assert.equal(f.session.generation,generation);assert.equal(f.starts.length,1);assert.equal(sender({event:'form_start'}),true);
 for(const field of ['processing_revision','runtime_revision','policy_revision']){
  const old=f.session.capture();answer={...answer,[field]:field==='processing_revision'?'b':2};await f.session.refresh();
  assert.equal(old({event:'form_start'}),false);assert.equal(f.session.state,'active');
 }
});
test('a replaced grant never revives captured submit or reservations; conversions carry the contact once',async t=>{
 const f=fixture(t);await f.start();f.sent.length=0;
 const contact={fields:[{5:' Buyer@Example.TEST '},{6:'+420601234567'},{7:'PRIVATE'}]};
 const submit=f.layer.captureSubmission(contact);let finish;
 const checkout={payload:{fields:[{4:11}]},awaitPendingReservations:()=>new Promise(r=>finish=r)};
 f.layer.observe(checkout);await settle();f.choose({analytics:true,marketing:true,leaseId:'next'});finish();await settle();
 submit(true,{ticketOrder:{analytics:purchase}});assert.equal(f.sent.some(p=>['purchase','add_to_cart'].includes(p.event)),false);
 f.choose(false);const current=f.layer.captureSubmission(contact);current(true,{ticketOrder:{analytics:{...purchase,private:'SECRET'}}});
 current(true,{ticketOrder:{analytics:purchase}});const sent=f.sent.filter(p=>p.event==='purchase');assert.equal(sent.length,1);
 assert.deepEqual(sent[0].user_data,{email:'buyer@example.test',phone_number:'+420601234567'},'a refusal does not remove the contact');
 assert.doesNotMatch(JSON.stringify(f.sent),/SECRET|PRIVATE/);
 f.layer.captureSubmission(contact)(true,{ticketOrder:{analytics:purchase}});
 assert.equal(f.sent.filter(p=>p.event==='purchase').length,1,'dedupe survives grant changes');
});
test('an unusable contact is left out without touching the conversion',async t=>{
 const f=fixture(t);await f.start();f.sent.length=0;
 f.layer.captureSubmission({fields:[{5:'not-an-email'},{6:'601234567'}]})(true,{ticketOrder:{analytics:purchase}});
 assert.equal(f.sent.find(p=>p.event==='purchase').user_data,undefined);
});
test('inactive cart updates baseline, activation starts from current cart without replay',async t=>{
 const f=fixture(t,{autoReady:false});await f.start();f.checkout.payload={fields:[{4:11}]};f.layer.observe(f.checkout);await settle();
 f.transport.grant.onReady();assert.equal(f.sent.some(p=>p.event==='add_to_cart'),false);
 f.layer.observe(f.checkout);await settle();assert.equal(f.sent.some(p=>p.event==='add_to_cart'),false);
 f.checkout.payload={fields:[{4:11},{4:12}]};f.layer.observe(f.checkout);await settle();
 assert.deepEqual(f.sent.filter(p=>p.event==='add_to_cart').map(p=>p.ecommerce.items[0].item_id),['product_12']);
});
test('hiding keeps the frame so the container runs once; pagehide/BFCache and an expired lease revoke',async t=>{
 const f=fixture(t,{autoReady:false});await f.start();const old=f.transport.grant;
 Object.defineProperty(f.dom.window.document,'hidden',{value:true,configurable:true});f.dom.window.document.dispatchEvent(new f.dom.window.Event('visibilitychange'));
 assert.equal(f.transport.grant,old);old.onReady();assert.equal(f.session.state,'active');assert.equal(f.session.record({event:'form_start'}),true);
 Object.defineProperty(f.dom.window.document,'hidden',{value:false,configurable:true});f.dom.window.document.dispatchEvent(new f.dom.window.Event('visibilitychange'));await settle();
 assert.equal(f.starts.length,1,'returning to the tab does not start the frame again');
 const captured=f.session.capture();f.dom.window.dispatchEvent(new f.dom.window.PageTransitionEvent('pagehide',{persisted:true}));
 assert.equal(captured({event:'page_view'}),false);assert.equal(f.transport.grant,null);
 f.dom.window.dispatchEvent(new f.dom.window.PageTransitionEvent('pageshow',{persisted:true}));await settle();f.transport.grant.onReady();
 f.choose({analytics:true,marketing:true,leaseId:'lease',expiresAt:Date.now()-1});assert.equal(f.session.record({event:'page_view'}),false);
});
test('policy expiry always removes transport including hidden pages; disposed stays terminal',async t=>{
 const f=fixture(t,{source:async()=>({...policy,valid_for_seconds:0.01})});await f.start();const send=f.session.capture();
 await new Promise(r=>setTimeout(r,30));assert.equal(f.transport.grant,null);assert.equal(send({event:'page_view'}),false);
 f.session.dispose();f.session.start();await f.session.refresh();assert.equal(f.session.state,'disposed');
});
for(const url of ['https://tickets.test/admin','https://tickets.test/form/summer?token=SECRET','https://tickets.test/form/summer?preview=true','https://tickets.test/form/summer#access_token=SECRET'])test('private context blocked '+url,async t=>{
 const f=fixture(t,{url});await f.start();assert.equal(f.starts.length,0);assert.deepEqual(f.sent,[]);
});
test('transport errors cannot reach checkout callbacks or consume conversion identity',async t=>{
 const f=fixture(t);await f.start();f.sent.length=0;f.delivery(false);
 const outcome=f.layer.captureSubmission();assert.doesNotThrow(()=>outcome(true,{ticketOrder:{analytics:purchase}}));
 f.delivery(true);outcome(true,{ticketOrder:{analytics:purchase}});assert.equal(f.sent.filter(p=>p.event==='purchase').length,1);
});
test('staff-to-visitor policy recovery reconnects the previously suppressed CMP source',async t=>{
 let answer={...policy,visitor_role:'staff'};const f=fixture(t,{identity:'user',source:async()=>answer});
 await f.start();assert.equal(f.session.state,'blocked');
 answer={...policy,visitor_role:'visitor'};await f.session.refresh();assert.equal(f.session.state,'active');
});
test('a delayed embed helper selects no transport until it is known, then activates',async t=>{
 const f=fixture(t);let selection=null,notify;
 f.transport.selection=()=>selection;f.transport.subscribe=fn=>{notify=fn;return ()=>{};};
 await f.start();assert.equal(f.starts.length,0);assert.equal(f.session.grant,null);
 selection='runtime';notify();assert.equal(f.starts.length,1);assert.equal(f.session.state,'active');
});
test('consent changes preserve owner expiry and expired policy cannot revive a captured sender',async t=>{
 const f=fixture(t,{source:async()=>({...policy,valid_for_seconds:0.03})});await f.start();f.choose(false);f.choose({analytics:true,marketing:true});
 const send=f.session.capture();await new Promise(r=>setTimeout(r,50));assert.equal(f.session.grant,null);assert.equal(send({event:'form_start'}),false);
 await f.session.refresh();assert.equal(f.session.state,'active');assert.equal(send({event:'form_start'}),false);
});
test('missing/broken consent source measures with denied state and retries after renewal',async t=>{
 const f=fixture(t);let attempts=0,notify;const updates=[];f.transport.updateConsent=value=>updates.push(value);
 f.session.consentSource={connect(_policy,callback){notify=callback;if(++attempts===1)throw Error('CMP unavailable');callback({analytics:true,marketing:true});return ()=>{};}};
 await f.start();assert.equal(f.starts.length,1);assert.deepEqual(f.starts[0].consent,{analytics:false,marketing:false});assert.equal(f.session.consentConnected,false);
 await f.session.refresh();assert.equal(f.session.state,'active');assert.equal(attempts,2);assert.deepEqual(updates.at(-1),{analytics:true,marketing:true});
 const send=f.session.capture();notify(null);assert.equal(send({event:'page_view'}),true,'an unavailable CMP never stops measurement');assert.deepEqual(updates.at(-1),{analytics:false,marketing:false});
 await f.session.refresh();assert.equal(f.session.state,'active');assert.equal(attempts,3);assert.equal(f.starts.length,1);
});
test('session alone owns approved-host eligibility and binds the host instance into its grant',async t=>{
 let host={origin:'https://unapproved.test',instance:'one'},answer={...policy,approved_hosts:['https://approved.test']};
 const f=fixture(t,{source:async()=>answer});f.transport.hostContext=()=>host;
 await f.start();assert.equal(f.starts.length,0,'owner rejects unapproved host before transport activation');
 host={origin:'https://approved.test',instance:'one'};await f.session.refresh();assert.equal(f.session.state,'active');
 assert.deepEqual(f.transport.grant.host,host);assert.equal(f.transport.grant.runtimeOrigin,policy.runtime_origin);
 const old=f.session.capture();host={...host,instance:'two'};assert.equal(old({event:'page_view'}),false,'host instance is part of the captured permission');
 f.session.reconcile();await f.session.refresh();assert.equal(f.session.state,'active');assert.equal(old({event:'page_view'}),false);
 answer={...answer,approved_hosts:[]};await f.session.refresh();assert.equal(f.transport.grant,null,'policy removal is owned by session');
});
test('a stale submission cannot change event-owner page state across reactivation',async t=>{
 const f=fixture(t);await f.start();const outcome=f.layer.captureSubmission();f.choose({analytics:true,marketing:true,leaseId:'one'});
 outcome(true,{ticketOrder:{analytics:purchase}});assert.equal(f.layer.pageType,'product');
 f.choose({analytics:true,marketing:true,leaseId:'two'});assert.equal(f.sent.some(p=>p.page_type==='confirmation'),false);
});
test('a delayed expiry timer cannot let policy renewal revive the expired grant',async t=>{
 let now=100000;const f=fixture(t,{clock:()=>now});await f.start();const expired=f.session.capture();
 now+=61000;assert.equal(expired({event:'page_view'}),false,'expiry is checked before sending, independent of timers');
 await f.session.refresh();assert.equal(f.session.state,'active');assert.equal(expired({event:'page_view'}),false,'renewal creates a new grant after elapsed expiry');
});
