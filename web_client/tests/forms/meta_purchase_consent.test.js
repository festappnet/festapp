import {test} from 'node:test';
import {register} from 'node:module';
import assert from 'node:assert/strict';
import {purchaseConsentSnapshot, PurchaseConsentOrders} from '../../src/components/forms/meta_purchase_consent.js';
const now = Date.now();
const notice = {revision:'a'.repeat(32),origin:'https://organizer.example'};
const choice = () => ({marketing:true, expiresAt:now+60000, purchaseConsent:{source:'cookiebot',timestamp:new Date(now-1000).toISOString(),
    websiteOrigin:notice.origin,consentRevision:'b'.repeat(32),binding:{id:'11111111-1111-1111-1111-111111111111',version:1},ad_storage:true,ad_user_data:true,ad_personalization:true}});
test('snapshot requires every saved advertising purpose and a live transport',()=>{
    assert.ok(purchaseConsentSnapshot(choice(),notice,now));
    for(const key of ['ad_storage','ad_user_data','ad_personalization']) {
        const value=choice(); value.purchaseConsent[key]=false;
        assert.equal(purchaseConsentSnapshot(value,notice,now),null,key);
    }
    assert.equal(purchaseConsentSnapshot({...choice(),expiresAt:now},notice,now),null);
    const denied=choice(); denied.marketing=false; denied.purchaseConsent.ad_user_data=false;
    assert.equal(purchaseConsentSnapshot(denied,notice,now),null);
    assert.equal(purchaseConsentSnapshot(choice(),{...notice,origin:'https://other.example'},now),null);
    for(const timestamp of [undefined,'invalid',new Date(now+1).toISOString(),new Date(now-365*86400000).toISOString()]) {
        const value=choice(); value.purchaseConsent.timestamp=timestamp;
        assert.equal(purchaseConsentSnapshot(value,notice,now),null);
    }
});
const denyAdvertising = () => {
    const denied=choice();
    denied.purchaseConsent.ad_storage=false;
    denied.purchaseConsent.timestamp=new Date(now-1).toISOString();
    return denied;
};

test('only a newer saved denial in the captured consent scope withdraws checkout consent',async()=>{
    const calls=[];
    const orders=new PurchaseConsentOrders({clock:()=>now,revoke:async scope=>{calls.push(scope);return true;}});
    orders.observe(choice());
    const scope={token:'buyer-capability',orderId:42};
    orders.track(scope,purchaseConsentSnapshot(choice(),notice,now),notice);
    const unrelated=denyAdvertising(),older=denyAdvertising();
    unrelated.purchaseConsent.binding.version++;
    older.purchaseConsent.timestamp=new Date(now-2000).toISOString();
    for (const value of [false,null,unrelated,older]) orders.observe(value);
    await new Promise(resolve=>setImmediate(resolve));
    assert.deepEqual(calls,[]);
    orders.observe(denyAdvertising());
    await new Promise(resolve=>setImmediate(resolve));
    assert.deepEqual(calls,[scope]);
});

test('denial during submit is retained until buyer capability arrives, and failed withdrawal retries',async()=>{
    let calls=0;
    const orders=new PurchaseConsentOrders({clock:()=>now,revoke:async()=>++calls>1});
    orders.observe(denyAdvertising());
    orders.track({token:'capability',orderId:7},purchaseConsentSnapshot(choice(),notice,now),notice);
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(calls,1);
    orders.observe(choice());
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(calls,2);
    assert.equal(orders.orders.size,0);
});

test('source snapshot never upgrades individually denied advertising purposes',async()=>{
    const {readConsentSource}=await import('../../src/components/forms/measurement_consent_source.js');
    const scope={consentRevision:'b'.repeat(32),websiteOrigin:notice.origin,requiredPurposes:['analytics','marketing']};
    for(const key of ['ad_storage','ad_user_data','ad_personalization']) for (const denied of [false,'denied',null]) for (const location of ['raw','snapshot']) {
        const raw={marketing:true,consentRevision:scope.consentRevision,purchaseConsent:{source:'cookiebot',timestamp:new Date(now-1000).toISOString(),ad_storage:true,ad_user_data:true,ad_personalization:true}};
        (location === 'raw' ? raw : raw.purchaseConsent)[key]=denied;
        const value=readConsentSource({read:()=>raw},scope);
        assert.equal(value.purchaseConsent[key],denied===false ? false : undefined);
        assert.equal(purchaseConsentSnapshot(value,notice,now),null);
    }
});

test('host dataLayer bridge carries the saved CAPI snapshot while keeping host tag consent ownership',async()=>{
    const {JSDOM}=await import('jsdom');
    const {build}=await import('esbuild');
    const bundle=await build({stdin:{contents:`import {createHostMeasurement} from './src/embed/host_measurement.js'; window.createHostMeasurement=createHostMeasurement;`,resolveDir:new URL('../../',import.meta.url).pathname},bundle:true,write:false,format:'iife',platform:'browser'});
    const win=new JSDOM('',{url:notice.origin,runScripts:'outside-only'}).window;
    try {
        win.document.cookie='_fbp=fb.1.1795000000000.1234; path=/';
        win.document.cookie='_fbc=fb.1.1795000000000.Click_123; path=/';
        win.eval(bundle.outputFiles[0].text);
        const messages=[],matchingResponses=[],frame=win.document.createElement('iframe');frame.setAttribute('data-festapp-datalayer','');
        const record={manifest:{organization:1,unit:2,processing_revision:'revision',consent_revision:'b'.repeat(32),measurement_consent_bridge:true,
            website_consent_bindings:[{websiteOrigin:notice.origin,effective:true,id:'11111111-1111-1111-1111-111111111111',version:1}]},channel:{send:(type,data)=>type==='meta-checkout-matching' ? matchingResponses.push(data) : messages.push(data.measurement)}};
        let saved=choice(),notify;
        saved.purchaseConsent.matching={fbp:'fb.1.1795000000000.mustNotCross'};
        const cookieDescriptor=Object.getOwnPropertyDescriptor(win.Document.prototype,'cookie');
        let cookieReads=0;
        Object.defineProperty(win.document,'cookie',{get:()=>{cookieReads++;return cookieDescriptor.get.call(win.document);}});
        const frames=new Map([[frame,record]]);
        const host=win.createHostMeasurement({frames,currentRecord:()=>true,disposeRecord:()=>{},scan:()=>{},
            consentSource:{configured:true,read:()=>saved,subscribe:callback=>{notify=callback;return ()=>{};}}});
        host.syncConsent(frame,record);
        assert.equal(messages.at(-1).consent.marketing,false,'the host owns tag consent');
        assert.equal(messages.at(-1).consent.purchaseConsent.timestamp,saved.purchaseConsent.timestamp);
        assert.equal(messages.at(-1).binding.version,1);
        assert.equal(messages.at(-1).consent.purchaseConsent.matching,undefined);
        assert.equal(cookieReads,0,'consent renewal never reads Meta cookies');
        const {measurementManifest}=await import('../../src/components/forms/form_measurement_contract.js');
        const {policy}=await import('../support/measurement_fixture.js');
        const request={requestId:'checkout-1',leaseId:record.lease.id,manifest:record.manifest,origin:notice.origin,
            revision:notice.revision,decisionAt:saved.purchaseConsent.timestamp,consentRevision:saved.purchaseConsent.consentRevision,
            binding:saved.purchaseConsent.binding};
        host.receive(frame,record,{type:'meta-checkout-matching-request',matchingRequest:request});
        assert.equal(cookieReads,0,'consent-only manifest cannot read Meta cookies');
        record.manifest=measurementManifest(policy,policy.form_link);
        const live={...request,manifest:{...record.manifest,consent_revision:record.manifest.consent_revision}};
        live.manifest.website_consent_bindings=[{websiteOrigin:notice.origin,effective:true,...request.binding}];
        record.manifest=live.manifest;
        for(const wrong of [{...live,leaseId:'obsolete'},{...live,revision:undefined},{...live,decisionAt:'older'}]) {
            host.receive(frame,record,{type:'meta-checkout-matching-request',matchingRequest:wrong});
        }
        assert.equal(cookieReads,0,'no matching for stale or unscoped requests');
        host.receive(frame,record,{type:'meta-checkout-matching-request',matchingRequest:live});
        assert.equal(cookieReads,1);
        assert.deepEqual(JSON.parse(JSON.stringify(matchingResponses[0].matching)),
            {fbp:'fb.1.1795000000000.1234',fbc:'fb.1.1795000000000.Click_123'});
        saved=null;notify();
        assert.equal(messages.at(-1).consent.purchaseConsent,undefined,'source loss cannot retain a snapshot');
        const {purchase}=await import('../support/measurement_fixture.js');
        record.manifest=measurementManifest(policy,policy.form_link);record.lease.generation=1;
        record.pageContext={page_type:'confirmation',language:'en'};
        const delivery={type:'analytics',measurement:{protocol:3,manifest:record.manifest,generation:1,leaseId:record.lease.id}};
        const meta={...purchase,event:'meta_purchase',meta_purchase_allowed:true,meta_purchase_expires_at:Date.now()+60000};
        saved=choice();
        saved.purchaseConsent.ad_personalization=false;
        host.receive(frame,record,{...delivery,payload:meta});
        assert.equal(win.dataLayer,undefined,'a stale iframe choice cannot bypass a current denial at the host');
        saved=choice();
        for (const event of ['purchase','meta_purchase']) {
            const payload={...purchase,event,meta_purchase_allowed:true,meta_purchase_expires_at:Date.now()+60000,user_data:{email:'buyer@example.test'}};
            host.receive(frame,record,{type:'analytics',measurement:{protocol:3,manifest:record.manifest,generation:1,leaseId:record.lease.id},payload});
            assert.equal(win.dataLayer.at(-2).event,event);
            assert.deepEqual(JSON.parse(JSON.stringify(win.dataLayer.at(-1))),{form_embedded:false,user_data:null,ecommerce:null,event_id:null,meta_purchase_allowed:null,page_type:null,user_type:null,language:null});
            const retained=Object.assign({},...win.dataLayer,{event:'native_event'});
            for (const key of ['meta_purchase_allowed','event_id','ecommerce','user_data','page_type']) assert.equal(retained[key],null);
        }
        assert.equal(JSON.stringify(win.dataLayer).includes('fb.1.'),false,'browser identifiers never enter dataLayer');
        host.stopHeartbeat(record);
    } finally {win.close();}
});

test('client snapshot also excludes unknown fields and missing notice cannot break tracking',()=>{
 const value=choice();value.purchaseConsent.email='must not persist';value.purchaseConsent.binding.email='must not persist';
 const snapshot=purchaseConsentSnapshot(value,notice,now);
 assert.equal(snapshot.email,undefined);assert.equal(snapshot.binding.email,undefined);
 const orders=new PurchaseConsentOrders({revoke:async()=>true});
 assert.doesNotThrow(()=>orders.track({token:'capability',orderId:1},snapshot,null));
 assert.equal(orders.orders.size,0);
});

test('denial then regrant before submit response remains withdrawn for the original snapshot',async()=>{
 const calls=[],orders=new PurchaseConsentOrders({clock:()=>now,revoke:async scope=>{calls.push(scope);return true;}});
 orders.observe(choice());
 const attempt=orders.capture(purchaseConsentSnapshot(choice(),notice,now),notice);
 orders.observe(denyAdvertising());
 orders.observe(choice());
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls.length,0,'no withdrawal without buyer capability');
 orders.authorize(attempt,{token:'original-buyer-capability',orderId:91});
 await new Promise(resolve=>setImmediate(resolve));
 assert.deepEqual(calls,[{token:'original-buyer-capability',orderId:91}]);
});
test('generic source cannot fill missing individual ad purposes from marketing',async()=>{
 const {readConsentSource}=await import('../../src/components/forms/measurement_consent_source.js');
 const scope={consentRevision:'b'.repeat(32),websiteOrigin:notice.origin,requiredPurposes:['analytics','marketing']};
 for (const missing of ['ad_storage','ad_user_data','ad_personalization']) {
  const raw={...choice(),consentRevision:scope.consentRevision};delete raw.purchaseConsent[missing];
  const value=readConsentSource({read:()=>raw},scope);
  assert.equal(value.purchaseConsent[missing],undefined);
  assert.equal(purchaseConsentSnapshot(value,notice,now),null);
 }
 for (const marketing of [true,false]) {
  const raw={marketing,consentRevision:scope.consentRevision,purchaseConsent:{source:'cookiebot',timestamp:new Date(now-1000).toISOString()}};
  const value=readConsentSource({read:()=>raw},scope);
  for (const key of ['ad_storage','ad_user_data','ad_personalization']) assert.equal(value.purchaseConsent[key],undefined);
 }
});

test('embedded delayed-payment overview uses current host consent and handshake without standalone CMP',async()=>{
 const {JSDOM}=await import('jsdom');
 const {loadOrderOverview,stopOrderOverview}=await import('../../src/components/forms/order_overview.js');
 const {DbForms}=await import('../../src/components/forms/db_forms.js');
 const {EmbedMeasurement}=await import('../../src/embed/measurement.js');
 const {SupabaseService}=await import('../../src/services/supabase_service.js');
 const {policy,purchase,settle}=await import('../support/measurement_fixture.js');
 const token='a'.repeat(64),scope={token,orderId:17};
 const dom=new JSDOM('<iframe></iframe>',{url:'https://tickets.example',pretendToBeVisual:true});
 const frame=dom.window.document.querySelector('iframe');frame.src=`https://tickets.example/order?order_id=17&token=${token}&embed=1`;
 const win=frame.contentWindow;win.document.open();win.document.write('<html><body><main></main></body></html>');win.document.close();
 const host=win.document.querySelector('main'),messages=[];
 const oldWindow=globalThis.window,oldDocument=globalThis.document,oldPolicy=DbForms.getMeasurementPolicy,oldClient=SupabaseService.getClient;
 globalThis.window=win;globalThis.document=win.document;
 SupabaseService.getClient=()=>({auth:{onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}});
 const bridge=new EmbedMeasurement(win,{origin:'https://host.example',instance:'11111111-1111-1111-1111-111111111111',closed:false,send:(type,value)=>messages.push({type,...value})});
 bridge.configure({dataLayer:true,measurementProtocol:3});host._overviewEmbedBridge=bridge;
 DbForms.getMeasurementPolicy=async()=>({...policy,approved_hosts:['https://host.example']});
 const overview={code:200,measurementFormLink:'summer',root:{id:17,title:'Concert',symbol:'17'},orders:[],people:[],offers:[],serverTime:new Date().toISOString()};
 const commands={overview:async()=>overview};
 try {
  await loadOrderOverview(host,commands,scope);await settle();
  assert.equal(host._purchaseSession.transport,bridge);
  assert.equal(bridge.measurementRuntime,host._purchaseRuntime);
  assert.equal(messages.some(message=>message.type==='analytics'),false,'no event before host permission');
  const leaseId='22222222-2222-2222-2222-222222222222';
  bridge.receive({type:'measurement-consent',measurement:{protocol:3,manifest:bridge.measurementManifest,leaseId,ttl:60000,consent:{analytics:false,marketing:false}}});
  const activation=messages.find(message=>message.type==='measurement-activate');
  assert.ok(activation,'uses existing host activation handshake');
  bridge.receive({type:'measurement-ack',measurement:activation.measurement});
  overview.orders=[{id:17,symbol:'17',state:'paid',currency:'CZK',total:200,items:[],analytics:purchase}];
  await loadOrderOverview(host,commands,scope);await settle();
  const delivered=messages.filter(message=>message.type==='analytics' && message.payload.event==='purchase');
  assert.equal(delivered.length,1,'delayed payment follows current live host grant');
  assert.deepEqual(host._purchaseSession.consent.analytics,false);
  assert.deepEqual(host._purchaseSession.consent.marketing,false,'host denial stays denied for tags');
  assert.doesNotMatch(JSON.stringify(messages),new RegExp(token),'buyer capability never crosses host bridge');
  assert.equal(win.document.querySelector('#festapp-measurement-consent'),null,'no standalone Klaro in iframe');
  bridge.receive({type:'measurement-consent',measurement:{protocol:3,manifest:bridge.measurementManifest,ttl:0,consent:false}});
  overview.orders[0].analytics={...purchase,event_id:'33333333-3333-3333-3333-333333333333',ecommerce:{...purchase.ecommerce,transaction_id:'33333333-3333-3333-3333-333333333333'}};
  await loadOrderOverview(host,commands,scope);await settle();
  assert.equal(messages.filter(message=>message.type==='analytics' && message.payload.event==='purchase').length,1,'disconnected host cannot send another paid event');
 } finally {
  stopOrderOverview(host);SupabaseService.getClient=oldClient;DbForms.getMeasurementPolicy=oldPolicy;globalThis.window=oldWindow;globalThis.document=oldDocument;dom.window.close();
 }
});

test('matching reads only the consented source origin, validates cookies and derives stable click identity',async()=>{
 const {metaBrowserMatching,validMetaBrowserMatching}=await import('../../src/components/forms/meta_purchase_consent.js');
 const snapshot=choice().purchaseConsent;
 let reads=0;
 const win={location:{origin:notice.origin,href:notice.origin+'/?fbclid=Click_123'},performance:{timeOrigin:1795000000000},
  document:{get cookie(){reads++;return '_fbp=fb.1.1795000000000.1234; _fbc=invalid';}}};
 assert.deepEqual(metaBrowserMatching(null,win),{});
 assert.deepEqual(metaBrowserMatching({...snapshot,ad_storage:false},win),{});
 assert.deepEqual(metaBrowserMatching({...snapshot,websiteOrigin:'https://other.example'},win),{});
 assert.equal(reads,0,'no cookie access without all purposes and the exact source origin');
 const matching=metaBrowserMatching(snapshot,win);
 assert.deepEqual(matching,{fbp:'fb.1.1795000000000.1234',fbc:'fb.1.1795000000000.Click_123'});
 assert.deepEqual(metaBrowserMatching(snapshot,win),matching,'the fallback click time is stable for this page visit');
 const value=choice();value.purchaseConsent.matching={...matching,email:'private',ip:'192.0.2.1'};
 assert.equal(purchaseConsentSnapshot(value,notice,now).matching,undefined);
 assert.deepEqual(validMetaBrowserMatching(value.purchaseConsent.matching),matching);
 value.purchaseConsent.matching={fbp:'fb.1.1795000000000.bad\n',fbc:'fb.1.1795000000000.'+'a'.repeat(501)};
 assert.deepEqual(validMetaBrowserMatching(value.purchaseConsent.matching),{});
 win.document={cookie:'_fbc=fb.1.1795000000001.Click_123'};
 assert.deepEqual(metaBrowserMatching(snapshot,win),{fbc:'fb.1.1795000000001.Click_123'},'the cookie keeps the original click time');
 win.document={cookie:'_fbc=fb.1.1795000000001.OldClick'};
 assert.deepEqual(metaBrowserMatching(snapshot,win),{fbc:'fb.1.1795000000000.Click_123'},'a newer URL click replaces an older cookie');
 win.location.href=notice.origin;
 assert.deepEqual(metaBrowserMatching(snapshot,win),{fbc:'fb.1.1795000000001.OldClick'},'without a URL click the cookie is used');
 win.location.href=notice.origin+'/?fbclid=Click_123';
 win.document={get cookie(){throw new Error('blocked');}};
 assert.deepEqual(metaBrowserMatching(snapshot,win),{fbc:'fb.1.1795000000000.Click_123'},'blocked cookies still allow consented URL fallback');
 win.document={cookie:''};win.location.href=notice.origin;
 assert.deepEqual(metaBrowserMatching(snapshot,win),{},'no invented browser identifier');
});


test('checkout matching waits for the correlated response under the same live lease',async()=>{
    const {EmbedMeasurement}=await import('../../src/embed/measurement.js');
    const {measurementManifest}=await import('../../src/components/forms/form_measurement_contract.js');
    const {policy}=await import('../support/measurement_fixture.js');
    const sent=[];
    const win={crypto:globalThis.crypto,setTimeout,clearTimeout};
    const bridge=new EmbedMeasurement(win,{origin:notice.origin,instance:'test-instance',send:(type,data)=>sent.push({type,...data})});
    bridge.measurementProtocol=3;
    bridge.measurementManifest=measurementManifest(policy,policy.form_link);
    bridge.leaseId='checkout-lease';
    bridge.leaseUntil=Date.now()+60000;
    const snapshot=purchaseConsentSnapshot(choice(),notice,now);
    const waiting=bridge.collectMetaCheckoutMatching(snapshot);
    const request=sent.at(-1).matchingRequest;
    assert.equal(sent.at(-1).type,'meta-checkout-matching-request');
    assert.deepEqual(request.binding,snapshot.binding);
    bridge.receive({type:'meta-checkout-matching',requestId:'other-checkout',leaseId:request.leaseId,matching:{fbp:'fb.1.1795000000000.bad'}});
    bridge.receive({type:'meta-checkout-matching',requestId:request.requestId,leaseId:'old-lease',matching:{fbp:'fb.1.1795000000000.bad'}});
    bridge.receive({type:'meta-checkout-matching',requestId:request.requestId,leaseId:request.leaseId,
        matching:{fbp:'fb.1.1795000000000.good',fbc:'malformed',email:'not-a-matching-field'}});
    assert.deepEqual(await waiting,{fbp:'fb.1.1795000000000.good'});
    const unavailable=bridge.collectMetaCheckoutMatching(snapshot);
    bridge.suspend();
    assert.deepEqual(await unavailable,{},'a disappearing helper does not hold checkout open');
});

test('checkout only asks the host after a fresh notice and discards matching if the saved choice changes',async t=>{
    register('../css_loader.mjs',import.meta.url);
    const {JSDOM}=await import('jsdom');
    const win=new JSDOM('',{url:'https://tickets.example/form/pilot'}).window;
    const globals={window:win,document:win.document,HTMLElement:win.HTMLElement,CustomEvent:win.CustomEvent};
    const previous=Object.fromEntries(Object.keys(globals).map(key=>[key,globalThis[key]]));
    Object.assign(globalThis,globals);
    t.after(()=>{Object.assign(globalThis,previous);win.close();});
    const {FormPage}=await import('../../src/components/forms/form_page.js');
    const {DbForms}=await import('../../src/components/forms/db_forms.js');
    const model={link:'pilot'};
    const initial=choice();
    const snapshot=purchaseConsentSnapshot(initial,notice,now);
    const page={
        currentSession:{formModel:model},
        measurementSession:{consent:initial},
        embedBridge:{collectMetaCheckoutMatching:async()=>({fbp:'fb.1.1795000000000.good'})},
    };
    const collect=()=>FormPage.prototype.collectMetaCheckoutMatching.call(page,model,snapshot);
    const host=t.mock.method(page.embedBridge,'collectMetaCheckoutMatching');
    const lookup=t.mock.method(DbForms,'getMetaPurchaseConsent',async()=>null);
    assert.deepEqual(await collect(),{});
    assert.equal(host.mock.callCount(),0);
    lookup.mock.mockImplementation(async()=>notice);
    assert.deepEqual(await collect(),{fbp:'fb.1.1795000000000.good'});
    host.mock.mockImplementation(async()=>{
        page.measurementSession.consent=denyAdvertising();
        return {fbp:'fb.1.1795000000000.mustBeDiscarded'};
    });
    assert.deepEqual(await collect(),{});
});
