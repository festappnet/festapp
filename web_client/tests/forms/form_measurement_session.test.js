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
for(const consent of [null,false,true,{analytics:true},{marketing:true},{analytics:'true',marketing:true}])test('both purposes strictly required '+JSON.stringify(consent),async t=>{
 const f=fixture(t,{consent});await f.start();assert.equal(f.starts.length,0);assert.equal(f.session.record({event:'page_view'}),false);
 const send=f.session.capture();f.choose({analytics:true,marketing:true});assert.equal(f.starts.length,1);assert.equal(send({event:'page_view'}),false,'inactive capture remains inactive');
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
test('revoke/regrant never revives captured submit or reservations and never replays preconsent actions',async t=>{
 const f=fixture(t);await f.start();f.sent.length=0;
 const submit=f.layer.captureSubmission();let finish;
 const checkout={payload:{fields:[{4:11}]},awaitPendingReservations:()=>new Promise(r=>finish=r)};
 f.layer.observe(checkout);await settle();f.choose(false);f.choose({analytics:true,marketing:true});finish();await settle();
 submit(true,{ticketOrder:{analytics:purchase}});assert.equal(f.sent.some(p=>['purchase','add_to_cart'].includes(p.event)),false);
 const current=f.layer.captureSubmission();current(true,{ticketOrder:{analytics:{...purchase,user_data:{email:'private@example.test',phone_number:'+420601234567'},private:'SECRET'}}});
 current(true,{ticketOrder:{analytics:purchase}});assert.equal(f.sent.filter(p=>p.event==='purchase').length,1);
 assert.doesNotMatch(JSON.stringify(f.sent),/private|SECRET|user_data|601234567/);
 f.choose(false);f.choose({analytics:true,marketing:true});f.layer.captureSubmission()(true,{ticketOrder:{analytics:purchase}});
 assert.equal(f.sent.filter(p=>p.event==='purchase').length,1,'dedupe survives inactive periods');
});
test('inactive cart updates baseline, activation starts from current cart without replay',async t=>{
 const f=fixture(t,{consent:false});await f.start();f.checkout.payload={fields:[{4:11}]};f.layer.observe(f.checkout);await settle();
 f.choose({analytics:true,marketing:true});assert.equal(f.sent.some(p=>p.event==='add_to_cart'),false);
 f.layer.observe(f.checkout);await settle();assert.equal(f.sent.some(p=>p.event==='add_to_cart'),false);
 f.checkout.payload={fields:[{4:11},{4:12}]};f.layer.observe(f.checkout);await settle();
 assert.deepEqual(f.sent.filter(p=>p.event==='add_to_cart').map(p=>p.ecommerce.items[0].item_id),['product_12']);
});
test('hidden, pagehide/BFCache and expired source revoke synchronously; late ACK cannot activate',async t=>{
 const f=fixture(t,{autoReady:false});await f.start();const old=f.transport.grant;
 Object.defineProperty(f.dom.window.document,'hidden',{value:true,configurable:true});f.dom.window.document.dispatchEvent(new f.dom.window.Event('visibilitychange'));
 old.onReady();assert.notEqual(f.session.state,'active');assert.equal(f.transport.grant,null);
 Object.defineProperty(f.dom.window.document,'hidden',{value:false,configurable:true});f.dom.window.document.dispatchEvent(new f.dom.window.Event('visibilitychange'));await settle();
 f.transport.grant.onReady();const captured=f.session.capture();f.dom.window.dispatchEvent(new f.dom.window.PageTransitionEvent('pagehide',{persisted:true}));
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
 await f.start();assert.equal(f.session.state,'awaiting-consent');
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
test('missing/broken consent source retries after renewal and recovers without reconstructing the session',async t=>{
 const f=fixture(t);let attempts=0,notify;
 f.session.consentSource={connect(_policy,callback){notify=callback;if(++attempts===1)throw Error('CMP unavailable');callback({analytics:true,marketing:true});return ()=>{};}};
 await f.start();assert.equal(f.starts.length,0);assert.equal(f.session.consentConnected,false);
 await f.session.refresh();assert.equal(f.session.state,'active');assert.equal(attempts,2);
 const old=f.session.capture();notify(null);assert.equal(f.transport.grant,null);assert.equal(old({event:'page_view'}),false);
 await f.session.refresh();assert.equal(f.session.state,'active');assert.equal(attempts,3);assert.equal(old({event:'page_view'}),false);
});
