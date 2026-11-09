import {measurementProtocol} from '../../src/components/forms/form_measurement_contract.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {runtimeSource} from '../../../workers/form-measurement/src/runtime_source.mjs';
import {serveMeasurement} from '../../../workers/form-measurement/src/worker.mjs';
import {FormMeasurementRuntime} from '../../src/components/forms/form_measurement_runtime.js';
import {bindKlaroConsent} from '../../src/components/forms/form_measurement_consent.js';
import {attributionContext,measurementPageLocation,campaignContext,measurementOrigin,measurementManifest} from '../../src/components/forms/form_measurement_contract.js';
import {publicFormLocation,publicFormAttributionSearch} from '../../src/utils/public_form_location.js';
import {policy as base,purchase} from '../support/measurement_fixture.js';
const runtime='https://festival-measurement.pages.dev',parent='https://tickets.example';
const policy={...base,runtime_origin:runtime};const manifest=measurementManifest(policy,'summer');
const config={organization:1,unit:2,form_id:3,form_link:'summer',runtime_origin:runtime,parent_origin:parent,profile:'gtm-v1',ancestor_origins:[parent],collector_origins:['https://www.google-analytics.com'],policy,gtm_container:'GTM-W9WRHWT9',scripts:'</script><script>window.test=1</script>'};
const request=new Request(runtime+'/runtime?form=summer&parent='+encodeURIComponent(parent)),env={ORGANIZATION_ID:1,UNIT_ID:2};
test('Worker fetch uses edge-supported redirects and never forwards credentials to a redirect target',async t=>{
 const backendEnv={...env,FESTAPP_API_URL:'https://api.festapp.net',SUPABASE_SERVICE_ROLE_KEY:'fixture-server-credential'};
 const upstream=t.mock.method(globalThis,'fetch',async(url,options)=>{
  assert.equal(url,'https://api.festapp.net/rest/v1/rpc/get_form_measurement_runtime_config');
  assert.equal(options.redirect,'manual','Cloudflare Workers rejects redirect:error before sending the request');
  assert.equal(options.headers.authorization,'Bearer fixture-server-credential');
  return Response.json(config);
 });
 assert.equal((await serveMeasurement(request,backendEnv)).status,200);
 upstream.mock.mockImplementation(async()=>new Response(null,{status:302,headers:{location:'https://other.example/private'}}));
 const redirected=await serveMeasurement(request,backendEnv);
 assert.equal(redirected.status,404);assert.equal(await redirected.text(),'Measurement unavailable');
 assert.equal(upstream.mock.callCount(),2,'a redirect never causes a second credential-bearing request');
});
test('Worker binds actual SQL manifest, escapes scoped config, preserves CSP and rejects malformed responses',async()=>{
 let args;const response=await serveMeasurement(request,env,async value=>{args=value;return config});
 assert.equal(response.status,200);assert.deepEqual(args,{p_form_link:'summer',p_organization:1,p_unit:2,p_runtime_origin:runtime,p_parent_origin:parent});
 const html=await response.text();assert.ok(!html.includes(config.scripts));assert.ok(html.includes('\\u003c/script>'));assert.ok(html.includes('processing-a'));
 for(const directive of ["worker-src 'none'","frame-src 'none'","object-src 'none'","form-action 'none'",'frame-ancestors '+parent])assert.ok(response.headers.get('content-security-policy').includes(directive));
 for(const bad of [{...config,policy:{...policy,measurement_protocol:2}},{...config,policy:{...policy,measurement_protocol:undefined}},{...config,organization:2},{...config,unit:3},{...config,form_link:'other'}, {...config,parent_origin:'https://other.example'},
  {...config,runtime_origin:'https://other.pages.dev'}, {...config,policy:{...policy,eligible:false}}, {...config,policy:{...policy,processing_revision:null}},
  {...config,collector_origins:[parent]},{...config,collector_origins:['https://api.festapp.net']},{...config,collector_origins:['https://collect.example; script-src *']},{...config,scripts:'x'.repeat(5001)}])assert.equal((await serveMeasurement(request,env,async()=>bad)).status,404);
 assert.equal((await serveMeasurement(request,env,async()=>{throw Error('SECRET')})).status,404);
});
function fixture(t,embedded=false){
 const dom=new JSDOM('<body></body>',{url:parent+'/form/summer?gclid=click',pretendToBeVisual:true});const model={link:'summer',data:{analytics:policy}};
 const transport=new FormMeasurementRuntime({win:dom.window,model,embedded,campaign:()=>({form_embedded:!embedded})});let ready=0,mismatches=0;
 const grant={runtimeOrigin:runtime,manifest,generation:7,consent:{analytics:true,marketing:true},expiresAt:Date.now()+60000,onReady:()=>ready++,onMismatch:()=>mismatches++};
 const message=(type,extra={})=>dom.window.dispatchEvent(new dom.window.MessageEvent('message',{source:transport.frame?.contentWindow,origin:runtime,
  data:{namespace:'festapp-measurement',protocol:measurementProtocol,type,manifest,instance:transport.instance,generation:7,...extra}}));
 t.after(()=>{transport.destroy();dom.window.close();});return{dom,transport,grant,message,ready:()=>ready,mismatches:()=>mismatches};
}
test('no grant means no iframe; ready/init/ACK bind origin, source, manifest, generation and instance',t=>{
 const f=fixture(t),r=f.transport;r.activate();assert.equal(r.frame,null);
 r.activate(f.grant);assert.equal(r.frame.getAttribute('sandbox'),'allow-scripts allow-same-origin');assert.equal(r.frame.referrerPolicy,'no-referrer');
 f.message('ack',{protocol:1});f.message('ack',{instance:'forged'});f.message('ack',{generation:6});assert.equal(f.ready(),0);
 f.message('ready');f.message('ack');assert.equal(f.ready(),1);assert.equal(r.track({event:'page_view'}),true);
 r.renew(Date.now()+60000);assert.equal(f.ready(),1);r.stop();f.message('ack');assert.equal(r.track({event:'page_view'}),false);
});
test('policy A / Worker B mismatches before init, and old frames/ACKs cannot revive',t=>{
 const f=fixture(t),r=f.transport;r.activate(f.grant);const old=r.frame.contentWindow,instance=r.instance;
 f.message('ready',{manifest:{...manifest,processing_revision:'b'}});assert.equal(f.mismatches(),1);assert.equal(r.frame,null);
 r.activate({...f.grant,generation:8});f.dom.window.dispatchEvent(new f.dom.window.MessageEvent('message',{source:old,origin:runtime,data:{namespace:'festapp-measurement',protocol:measurementProtocol,type:'ack',manifest,instance,generation:7}}));
 assert.equal(f.ready(),0);r.frame.remove();f.message('ack',{generation:8});assert.equal(f.ready(),0);
});
for(const hidden of [false,true])test('expiry destroys the runtime even when hidden='+hidden,async t=>{
 const f=fixture(t);f.transport.activate({...f.grant,expiresAt:Date.now()+10});Object.defineProperty(f.dom.window.document,'hidden',{value:hidden});
 await new Promise(r=>setTimeout(r,30));assert.equal(f.transport.frame,null);assert.equal(f.transport.track({event:'page_view'}),false);
});
const unitScripts=f=>[...f.win.document.querySelectorAll('script')].filter(s=>s.textContent.includes('tagRuns') && s.id!=='measurement-config').length;
function bootstrap(t,consent={analytics:true,marketing:true},manifestOverride=manifest){
 const boot={...config,manifest};const dom=new JSDOM('<head><script type="application/json" id="measurement-config"></script></head>',{url:runtime+'/runtime',runScripts:'outside-only'});
 const win=dom.window;win.document.getElementById('measurement-config').textContent=JSON.stringify({...boot,gtm_container:'GTM-AB12',scripts:'window.tagRuns=(window.tagRuns||0)+1'});win.eval(runtimeSource);
 const send=(type,extra={})=>win.dispatchEvent(new win.MessageEvent('message',{source:win.parent,origin:parent,data:{namespace:'festapp-measurement',protocol:measurementProtocol,type,manifest:manifestOverride,instance:'instance',generation:7,consent,context:{page_location:parent+'/form/summer',gclid:'click'},...extra}}));
 t.after(()=>win.close());return{win,send};
}
for(const [consent,ads] of [[null,'denied'],[false,'denied'],[true,'denied'],[{analytics:true},'denied'],[{marketing:true},'granted'],[{analytics:false,marketing:false},'denied']])test('bootstrap always runs Unit code and events for '+JSON.stringify(consent),t=>{
 const f=bootstrap(t,consent);f.send('init');f.send('event',{payload:purchase});assert.equal(unitScripts(f),1);assert.ok(f.win.document.querySelector('script[src]').src.includes('GTM-AB12'));
 assert.equal(f.win.dataLayer[0][1],'default');assert.equal(f.win.dataLayer[0][2].ad_storage,ads);assert.equal(f.win.dataLayer.filter(p=>p.event==='purchase').length,1);
});
test('a later choice updates Consent Mode and the event context without running Unit code again',t=>{
 const f=bootstrap(t,false);f.send('init');f.send('consent',{consent:{analytics:true,marketing:true}});f.send('consent',{generation:6,consent:false});
 const entries=[...f.win.dataLayer];const update=entries.filter(p=>p[0]==='consent' && p[1]==='update').at(-1);assert.equal(update[2].ad_user_data,'granted');
 assert.equal(entries.filter(p=>p.event==='festapp_consent_update').length,1);assert.equal(unitScripts(f),1);
 f.send('event',{payload:purchase});assert.equal(JSON.stringify(f.win.dataLayer.find(p=>p.event==='purchase').festapp_consent),'{"analytics":true,"marketing":true}');
});
test('runtime transport sends a later choice only after init',t=>{
 const f=fixture(t),r=f.transport;const sent=[];r.activate(f.grant);const post=r.frame.contentWindow.postMessage;
 Object.defineProperty(r.frame.contentWindow,'postMessage',{value:(data,...rest)=>{sent.push(data);return post?.call(r.frame.contentWindow,data,...rest);}});
 r.updateConsent({analytics:true,marketing:true});assert.equal(sent.length,0);f.message('ready');
 assert.equal(sent[0].type,'init');assert.equal(sent[0].consent.marketing,true,'init carries the newest choice');
 r.updateConsent({analytics:false,marketing:false});assert.equal(sent.at(-1).type,'consent');assert.equal(r.frame!==null,true);
});
test('bootstrap rejects mismatched snapshot before code and establishes Consent Mode before script effects',t=>{
 const wrong=bootstrap(t,false,{...manifest,runtime_revision:2});wrong.send('init');assert.equal(wrong.win.document.querySelector('script[src]'),null);
 const f=bootstrap(t);f.send('init');const entries=f.win.dataLayer;
 assert.equal(entries[0][0],'consent');assert.equal(entries[0][1],'default');assert.equal(entries[0][2].ad_storage,'granted');assert.equal(entries[1][1],'update');
 assert.equal(f.win.document.querySelectorAll('script[src]').length,1);assert.ok(f.win.document.querySelector('script[src]').src.includes('GTM-AB12'));
 f.send('event',{payload:{...purchase,user_data:{email:'buyer@example.test',phone_number:'+420601234567',first_name:'PRIVATE'}}});
 assert.equal(entries.filter(p=>p.event==='purchase').length,1);assert.equal(JSON.stringify(entries.find(p=>p.event==='purchase').user_data),'{"email":"buyer@example.test","phone_number":"+420601234567"}');
 assert.doesNotMatch(JSON.stringify(entries),/PRIVATE/);assert.equal(entries.at(-1).user_data,null,'the contact does not carry over to later events');
 f.send('event',{generation:6,payload:purchase});assert.equal(entries.filter(p=>p.event==='purchase').length,1);
});
test('isolated Google tags receive cross-site cookie flags before loading without changing consent',t=>{
 const f=bootstrap(t,false);f.send('init');const entries=[...f.win.dataLayer];
 const cookieSettings=entries.findIndex(p=>p[0]==='set' && p[1]?.cookie_flags==='SameSite=None;Secure');
 assert(cookieSettings>=0,'framed Google tags require explicit cross-site cookie flags');
 assert(cookieSettings<entries.findIndex(p=>p.event==='gtm.js'));
 assert.equal(entries[0][2].analytics_storage,'denied');assert.equal(entries[1][2].analytics_storage,'denied');
});
test('Klaro saved-choice adapter rejects drafts and unavailable services; disconnect revokes',()=>{
 let watcher;const sent=[];const manager={confirmed:false,savedConsents:{analytics:false},getConsent:()=>true,watch:value=>watcher=value,unwatch:value=>assert.equal(value,watcher)};
 const stop=bindKlaroConsent(manager,value=>sent.push(value));manager.confirmed=true;watcher.update();assert.deepEqual(sent.at(-1),{analytics:false,marketing:false});
 manager.savedConsents.analytics=true;watcher.update();assert.deepEqual(sent.at(-1),{analytics:true,marketing:false});manager.savedConsents.marketing=true;watcher.update();assert.deepEqual(sent.at(-1),{analytics:true,marketing:true});stop();assert.equal(sent.at(-1),false);
});
test('attribution retains allowed campaign/click IDs and drops credentials and private contexts',()=>{
 assert.equal(measurementOrigin(runtime),runtime);for(const bad of ['https://tenant.runtime.example',runtime+'/',runtime+'?x=1','http://localhost:3000'])assert.equal(measurementOrigin(bad),null);
 const result=attributionContext({page_location:parent+'/form/summer',page_referrer:'https://ref.example/private?token=SECRET#hash',gclid:'click',gbraid:'app',utm_term:'PRIVATE@example.test',token:'SECRET'});
 assert.deepEqual(result,{page_location:parent+'/form/summer',form_embedded:false,page_referrer:'https://ref.example/',gclid:'click',gbraid:'app'});
 assert.equal(attributionContext({page_location:parent+'/form/summer?token=SECRET'}),null);
 for(const key of ['gclid','gbraid','wbraid','gad_source','gad_campaignid','srsltid','fbclid','sznclid','ttclid','msclkid']){
  assert.equal(campaignContext({[key]:'click'})[key],'click');assert.ok(measurementPageLocation({page_location:parent+'/form/summer',[key]:'click'}).includes(key+'=click'));
  assert.equal(publicFormLocation(new URL(parent+'/form/summer?'+key+'=click')),true);
 }
 assert.equal(publicFormAttributionSearch(new URL(parent+'/form/summer?_gl=x&gtm_debug=1&utm_id=2')),'?utm_id=2');
});

test('a broken CMP unsubscribe still revokes its saved grant synchronously',()=>{
 const sent=[];const manager={confirmed:true,savedConsents:{analytics:true,marketing:true},getConsent:()=>true,watch(){},unwatch(){throw Error('CMP teardown failed');}};
 const disconnect=bindKlaroConsent(manager,value=>sent.push(value));assert.deepEqual(sent.at(-1),{analytics:true,marketing:true});
 assert.throws(disconnect,/teardown failed/);assert.equal(sent.at(-1),false);
});

test('cutover: update publishes a fresh nested consent snapshot before another event',t=>{
 const f=bootstrap(t);const model={},events=[];
 f.win.dataLayer.push=(...entries)=>{for(const entry of entries){const snapshot=JSON.parse(JSON.stringify(entry));Object.assign(model,snapshot);if(snapshot.event)events.push({payload:snapshot,model:structuredClone(model)});}return 0;};
 f.send('init');f.send('consent',{consent:false});
 assert.equal(events.at(-1).payload.event,'festapp_consent_update');
 assert.deepEqual(events.at(-1).model.festapp_consent,{analytics:false,marketing:false});
 f.send('consent',{consent:{analytics:true,marketing:true}});
 assert.deepEqual(events.at(-1).model.festapp_consent,{analytics:true,marketing:true});assert.equal(unitScripts(f),1);
});

test('Klaro failed registration cleans its watcher and disposal is idempotent',()=>{
 let watched,unwatched=0;
 const manager={watch(w){watched=w;throw Error('partial registration');},unwatch(w){assert.equal(w,watched);unwatched++;}};
 assert.throws(()=>bindKlaroConsent(manager,()=>{}),/partial registration/);assert.equal(unwatched,1);
 manager.watch=w=>{watched=w;};const stop=bindKlaroConsent(manager,()=>{});stop();stop();assert.equal(unwatched,2);
});

for(const embedded of [false,true])test('runtime init carries parent embed state: '+embedded,t=>{
 const f=fixture(t,embedded),r=f.transport;r.activate(f.grant);const sent=[];
 r.frame.contentWindow.postMessage=data=>sent.push(data);f.message('ready');
 assert.equal(sent[0].context.form_embedded,embedded,'parent state overrides campaign input');
});
for(const value of [true,false,undefined,null,1,0,'true','false',{},[]])test('bootstrap sanitizes embed state in context pushes: '+JSON.stringify(value),t=>{
 const expected=value===true,f=bootstrap(t,false);
 f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:value}});
 const entries=f.win.dataLayer,initial=entries.find(p=>p.page_location);
 assert.deepEqual(JSON.parse(JSON.stringify(initial)),{page_location:parent+'/form/summer',form_embedded:expected,festapp_consent:{analytics:false,marketing:false}});
 assert(entries.indexOf(initial)<entries.findIndex(p=>p.event==='gtm.js'));
 f.send('event',{payload:{event:'page_view',form_embedded:!expected}});
 f.send('event',{payload:purchase});f.send('consent',{consent:true});
 for(const event of ['page_view','purchase'])assert.equal(entries.find(p=>p.event===event).form_embedded,expected,'events carry context');
 assert.equal(attributionContext({page_location:parent+'/form/summer',form_embedded:value}).form_embedded,expected);
});
