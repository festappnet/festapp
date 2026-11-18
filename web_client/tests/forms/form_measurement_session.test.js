import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture,policy,registrationLead,settle,purchase} from '../support/measurement_fixture.js';

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
test('a replaced grant recovers only the conversion fact, never contacts or reservations',async t=>{
 const f=fixture(t);await f.start();f.sent.length=0;
 const contact={fields:[{5:' Buyer@Example.TEST '},{6:'+420601234567'},{7:'PRIVATE'}]};
 const submit=f.layer.captureSubmission(contact);let finish;
 const checkout={payload:{fields:[{4:11}]},awaitPendingReservations:()=>new Promise(r=>finish=r)};
 f.layer.observe(checkout);await settle();f.choose({analytics:true,marketing:true,leaseId:'next',expiresAt:Date.now()+30000});finish();await settle();
 submit(true,{ticketOrder:{analytics:registrationLead}});await settle();
 assert.equal(f.sent.filter(p=>p.event==='generate_lead').length,1);
 assert.equal(f.sent.find(p=>p.event==='generate_lead').user_data,undefined);
 assert.equal(f.sent.some(p=>p.event==='add_to_cart'),false);
 f.choose(false);const current=f.layer.captureSubmission(contact);
 const second={...registrationLead,event_id:'d5c624bd-01b6-4dcf-9bf9-00dcb73a7b44'};current(true,{ticketOrder:{analytics:{...second,private:'SECRET'}}});
 current(true,{ticketOrder:{analytics:registrationLead}});const sent=f.sent.filter(p=>p.event==='generate_lead' && p.user_data);assert.equal(sent.length,1);
 assert.deepEqual(sent[0].user_data,{email:'buyer@example.test',phone_number:'+420601234567'},'a refusal does not remove the contact');
 assert.doesNotMatch(JSON.stringify(f.sent),/SECRET|PRIVATE/);
 f.layer.captureSubmission(contact)(true,{ticketOrder:{analytics:registrationLead}});
 assert.equal(f.sent.filter(p=>p.event==='generate_lead').length,2,'dedupe survives grant changes');
});
test('an unusable contact is left out without touching the conversion',async t=>{
 const f=fixture(t);await f.start();f.sent.length=0;
 f.layer.captureSubmission({fields:[{5:'not-an-email'},{6:'601234567'}]})(true,{ticketOrder:{analytics:registrationLead}});
 assert.equal(f.sent.find(p=>p.event==='generate_lead').user_data,undefined);
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
 const outcome=f.layer.captureSubmission();assert.doesNotThrow(()=>outcome(true,{ticketOrder:{analytics:registrationLead}}));
 f.delivery(true);outcome(true,{ticketOrder:{analytics:registrationLead}});await settle();assert.equal(f.sent.filter(p=>p.event==='generate_lead').length,1);
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
 outcome(true,{ticketOrder:{analytics:registrationLead}});assert.equal(f.layer.pageType,'product');
 f.choose({analytics:true,marketing:true,leaseId:'two'});assert.equal(f.sent.some(p=>p.page_type==='confirmation'),false);
});
test('a delayed expiry timer cannot let policy renewal revive the expired grant',async t=>{
 let now=100000;const f=fixture(t,{clock:()=>now});await f.start();const expired=f.session.capture();
 now+=61000;assert.equal(expired({event:'page_view'}),false,'expiry is checked before sending, independent of timers');
 await f.session.refresh();assert.equal(f.session.state,'active');assert.equal(expired({event:'page_view'}),false,'renewal creates a new grant after elapsed expiry');
});

test('policy refresh and unchanged source renewals clamp the runtime deadline',async t=>{
 const now=Date.now(),f=fixture(t,{clock:()=>now,consent:{analytics:true,marketing:true,leaseId:'source',expiresAt:now+10000}}),renewals=[];
 f.transport.renew=until=>renewals.push(until);await f.start();await f.session.refresh();
 assert.equal(renewals.at(-1),now+10000);
 const generation=f.session.generation;
 f.choose({analytics:true,marketing:true,leaseId:'source',expiresAt:now+5000});
 assert.equal(renewals.at(-1),now+5000);assert.equal(f.session.generation,generation);
 f.choose({analytics:true,marketing:true,leaseId:'source',expiresAt:now+20000});
 assert.equal(renewals.at(-1),now+20000);
});
for(const expiresAt of [0,NaN,Infinity,-1]) test('malformed source deadline cannot become unlimited '+expiresAt,async t=>{
 const f=fixture(t,{consent:{analytics:true,marketing:true,leaseId:'source',expiresAt}});await f.start();assert.equal(f.transport.grant,null);
});

test('managed binding changes retire live senders even when semantic notice is unchanged',async t=>{
 const id='11111111-1111-1111-1111-111111111111';
 let answer={...policy,consent_revision:'a'.repeat(32),website_consent_bindings:[{id,version:1,websiteOrigin:'https://host.example',effective:true}]};
 const f=fixture(t,{source:async()=>answer});await f.start();
 const first=f.session.capture();
 answer={...answer,website_consent_bindings:[{...answer.website_consent_bindings[0],version:2,effective:false}]};
 await f.session.refresh();
 assert.equal(first({event:'form_start'}),false,'manifest boundary also guards peers missing technical fingerprint updates');
 assert.equal(f.session.policy.consent_revision,'a'.repeat(32));
});

test('pending lead waits for verified ready transport and uses the current denied consent',async t=>{
 const event='generate_lead';
 const f=fixture(t,{autoReady:false});await f.start();f.transport.grant.onReady();
 const fact=registrationLead;
 const outcome=f.layer.captureSubmission({fields:[{5:'buyer@example.test'}]});
 f.choose({analytics:false,marketing:false,leaseId:'replacement',expiresAt:Date.now()+30000});
 outcome(true,{ticketOrder:{analytics:fact}});outcome(true,{ticketOrder:{analytics:fact}});
 await settle();assert.equal(f.sent.some(p=>p.event===event),false);
 assert.equal(f.session.pendingConversions.size,1);
 assert.doesNotMatch(JSON.stringify([...f.session.pendingConversions.values()]),/buyer@example/);
 const send=f.session.capture();f.transport.grant.onReady();
 assert.equal(send({event:'form_start'}),false,'old sender remains invalid');
 const delivered=f.sent.filter(p=>p.event===event);assert.equal(delivered.length,1);assert.equal(delivered[0].user_data,undefined);
 assert.deepEqual(f.transport.grant.consent,{analytics:false,marketing:false});
 assert.equal(f.session.pendingConversions.size,0);
 await f.session.refresh();assert.equal(f.sent.filter(p=>p.event===event).length,1);
});
for(const change of ['identity','policy','host','dispose'])test('pending conversion cannot cross '+change+' boundary',async t=>{
 let answer={...policy};const f=fixture(t,{autoReady:false,source:async()=>answer});
 let host={origin:'https://host.test',instance:'one'};
 if(change==='host'){answer.approved_hosts=[host.origin];f.transport.hostContext=()=>host;}
 await f.start();f.transport.grant.onReady();const outcome=f.layer.captureSubmission();
 f.choose({analytics:false,marketing:false,leaseId:'replacement',expiresAt:Date.now()+30000});
 outcome(true,{ticketOrder:{analytics:registrationLead}});
 if(change==='identity')f.identity('staff');
 if(change==='policy')answer={...answer,enabled:false};
 if(change==='host')host={...host,instance:'two'};
 if(change==='dispose')f.session.dispose();
 await settle();await f.session.refresh();f.transport.grant?.onReady();
 assert.equal(f.sent.some(p=>p.event==='generate_lead'),false);
});

for(const key of ['unrelated-preference','festapp-consent'])test('storage change for '+key+' preserves an in-flight conversion across lease renewal',async t=>{
 const f=fixture(t,{autoReady:false});await f.start();f.transport.grant.onReady();
 const outcome=f.layer.captureSubmission({fields:[{5:'buyer@example.test'}]});
 const epoch=f.session.contextEpoch;
 f.dom.window.dispatchEvent(new f.dom.window.StorageEvent('storage',{key,newValue:'changed'}));
 assert.equal(f.session.contextEpoch,epoch);
 f.choose({analytics:false,marketing:false,leaseId:'renewed',expiresAt:Date.now()+30000});
 outcome(true,{ticketOrder:{analytics:registrationLead}});await settle();
 assert.equal(f.session.pendingConversions.size,1);
 f.transport.grant.onReady();
 const delivered=f.sent.filter(p=>p.event==='generate_lead');assert.equal(delivered.length,1);
 assert.equal(delivered[0].user_data,undefined);
 assert.deepEqual(f.transport.grant.consent,{analytics:false,marketing:false});
});
test('storage-observed identity change discards the in-flight conversion even if the identity returns',async t=>{
 let identity='anonymous';const f=fixture(t,{autoReady:false});
 f.session.identitySource.read=()=>identity;
 await f.start();f.transport.grant.onReady();const outcome=f.layer.captureSubmission();
 identity='other-user';
 f.dom.window.dispatchEvent(new f.dom.window.StorageEvent('storage',{key:'auth-token',newValue:'changed'}));
 assert.equal(f.session.contextEpoch,1);
 identity='anonymous';
 f.dom.window.dispatchEvent(new f.dom.window.StorageEvent('storage',{key:'auth-token',newValue:null}));
 outcome(true,{ticketOrder:{analytics:registrationLead}});await settle();
 f.transport.grant?.onReady();
 assert.equal(f.sent.some(p=>p.event==='generate_lead'),false);
 assert.equal(f.session.pendingConversions.size,0);
});

for(const role of ['anonymous','staff'])test('buyer overview uses current policy and isolated transport '+role,async t=>{
 const token='a'.repeat(64),scope={token,orderId:17};
 const f=fixture(t,{url:`https://tickets.test/order?order_id=17&token=${token}`,authorizedOrderScope:scope,source:async()=>({...policy,visitor_role:role})});
 await f.start();
 assert.equal(f.session.record({event:'form_start'}),role==='anonymous');
 assert.equal(JSON.stringify(f.sent).includes(token),false,'capability stays out of exported events');
 f.dom.reconfigure({url:`https://tickets.test/order?order_id=18&token=${token}`});
 assert.equal(f.session.record({event:'form_start'}),false,'changed capability scope invalidates access');
});
test('order URL alone cannot activate browser purchases',async t=>{
 const f=fixture(t,{url:`https://tickets.test/order?order_id=17&token=${'a'.repeat(64)}`});
 await f.start(); assert.equal(f.starts.length,0);
});

test('overview purchase polls and repeated transport readiness deliver each UUID once',async t=>{
 const token='a'.repeat(64);
 const f=fixture(t,{url:`https://tickets.test/order?order_id=17&token=${token}`,authorizedOrderScope:{orderId:17,token},autoReady:false});
 const publish=()=>{if(f.session.state==='active')f.session.captureConversion()(purchase);};
 f.session.onActive=publish;
 await f.start();publish();assert.equal(f.sent.filter(p=>p.event==='purchase').length,0);
 f.transport.grant.onReady();publish();publish();f.transport.grant.onReady();
 assert.equal(f.sent.filter(p=>p.event==='purchase').length,1);
 f.session.invalidate();await f.session.refresh();f.transport.grant.onReady();publish();
 assert.equal(f.sent.filter(p=>p.event==='purchase').length,1,'runtime restart preserves delivered UUIDs');
});

for(const suffix of ['', '&embed=1','&embed=0','&embed=1&embed=1','&unknown=1','&token=duplicate'])test('authorized order query allows only canonical optional embed '+suffix,async t=>{
 const token='a'.repeat(64),scope={token,orderId:17};
 const f=fixture(t,{url:`https://tickets.test/order?order_id=17&token=${token}${suffix}`,authorizedOrderScope:scope});
 await f.start();
 assert.equal(f.session.contextAllowed(),suffix==='' || suffix==='&embed=1');
});

test('analytics granted and advertising denied preserves general purchase independently of CAPI',async t=>{
 const f=fixture(t,{consent:{analytics:true,marketing:false}});await f.start();
 const general={...purchase,meta_purchase_allowed:false};
 assert.equal(f.session.captureConversion()(general),true);
 assert.equal(f.sent.filter(p=>p.event==='purchase').length,1);
 assert.equal(f.sent.find(p=>p.event==='purchase').meta_purchase_allowed,false);
 assert.equal(f.transport.grant.consent.analytics,true);assert.equal(f.transport.grant.consent.marketing,false);
});
const advertisingChoice = () => ({analytics:true,marketing:true,purchaseConsent:{
 source:'klaro',timestamp:new Date(Date.now()-1000).toISOString(),consentRevision:'a'.repeat(32),
 ad_storage:true,ad_user_data:true,ad_personalization:true,
}});

test('general Purchase and Meta companion deduplicate by event plus shared UUID',async t=>{
 const f=fixture(t,{consent:advertisingChoice()});await f.start();
 const general={...purchase,meta_purchase_allowed:false},meta={...purchase,event:'meta_purchase',meta_purchase_allowed:true,meta_purchase_expires_at:Date.now()+60000};
 for(let i=0;i<3;i++){f.session.captureConversion()(general);f.session.captureConversion()(meta);}
 assert.equal(f.sent.filter(p=>p.event==='purchase').length,1);assert.equal(f.sent.filter(p=>p.event==='meta_purchase').length,1);
});


test('a current advertising denial blocks immediate and queued Meta companions, including after regrant for the withdrawn order',async t=>{
 const f=fixture(t,{consent:advertisingChoice()});await f.start();
 const general={...purchase,meta_purchase_allowed:false},meta={...purchase,event:'meta_purchase',meta_purchase_allowed:true,meta_purchase_expires_at:Date.now()+60000};
 f.delivery(false);
 assert.equal(f.session.captureConversion()(meta),true);
 const denied=advertisingChoice();denied.purchaseConsent.ad_user_data=false;
 f.choose(denied);f.delivery(true);
 await f.session.refresh();
 assert.equal(f.session.captureConversion()(meta),false);
 assert.equal(f.session.captureConversion()(general),true);
 f.session.allowMetaPurchase=()=>false;f.choose(advertisingChoice());await f.session.refresh();
 assert.equal(f.session.captureConversion()(meta),false);
 assert.equal(f.sent.filter(payload=>payload.event==='purchase').length,1);
 assert.equal(f.sent.filter(payload=>payload.event==='meta_purchase').length,0);
});

test('a queued Meta companion cannot outlive its deduplication deadline',async t=>{
 let now=Date.now();
 const f=fixture(t,{consent:advertisingChoice(),clock:()=>now});await f.start();
 const expiry=now+1000;
 const companion={...purchase,event:'meta_purchase',meta_purchase_allowed:true,meta_purchase_expires_at:expiry};
 f.delivery(false);assert.equal(f.session.captureConversion()(companion),true);
 f.delivery(true);now=expiry;
 await f.session.refresh();
 assert.equal(f.session.captureConversion()(companion),false);
 assert.equal(f.sent.some(payload=>payload.event==='meta_purchase'),false);
 assert.equal(f.session.captureConversion()({...purchase,meta_purchase_allowed:true,meta_purchase_expires_at:expiry}),true);
 assert.equal(f.sent.find(payload=>payload.event==='purchase').meta_purchase_allowed,false);
});
