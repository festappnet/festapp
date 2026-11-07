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
test('Worker binds actual SQL manifest, escapes scoped config, preserves CSP and rejects malformed responses',async()=>{
 let args;const response=await serveMeasurement(request,env,async value=>{args=value;return config});
 assert.equal(response.status,200);assert.deepEqual(args,{p_form_link:'summer',p_organization:1,p_unit:2,p_runtime_origin:runtime,p_parent_origin:parent});
 const html=await response.text();assert.ok(!html.includes(config.scripts));assert.ok(html.includes('\\u003c/script>'));assert.ok(html.includes('processing-a'));
 for(const directive of ["worker-src 'none'","frame-src 'none'","object-src 'none'","form-action 'none'",'frame-ancestors '+parent])assert.ok(response.headers.get('content-security-policy').includes(directive));
 for(const bad of [{...config,organization:2},{...config,unit:3},{...config,form_link:'other'}, {...config,parent_origin:'https://other.example'},
  {...config,runtime_origin:'https://other.pages.dev'}, {...config,policy:{...policy,eligible:false}}, {...config,policy:{...policy,processing_revision:null}},
  {...config,collector_origins:[parent]},{...config,collector_origins:['https://api.festapp.net']},{...config,collector_origins:['https://collect.example; script-src *']},{...config,scripts:'x'.repeat(5001)}])assert.equal((await serveMeasurement(request,env,async()=>bad)).status,404);
 assert.equal((await serveMeasurement(request,env,async()=>{throw Error('SECRET')})).status,404);
});
function fixture(t){
 const dom=new JSDOM('<body></body>',{url:parent+'/form/summer?gclid=click',pretendToBeVisual:true});const model={link:'summer',data:{analytics:policy}};
 const transport=new FormMeasurementRuntime({win:dom.window,model});let ready=0,mismatches=0;
 const grant={manifest,generation:7,consent:{analytics:true,marketing:true},expiresAt:Date.now()+60000,onReady:()=>ready++,onMismatch:()=>mismatches++};
 const message=(type,extra={})=>dom.window.dispatchEvent(new dom.window.MessageEvent('message',{source:transport.frame?.contentWindow,origin:runtime,
  data:{namespace:'festapp-measurement',protocol:2,type,manifest,instance:transport.instance,generation:7,...extra}}));
 t.after(()=>{transport.destroy();dom.window.close();});return{dom,transport,grant,message,ready:()=>ready,mismatches:()=>mismatches};
}
test('no grant means no iframe; ready/init/ACK bind origin, source, manifest, generation and instance',t=>{
 const f=fixture(t),r=f.transport;r.start();assert.equal(r.frame,null);r.start({...f.grant,consent:{analytics:true,marketing:false}});assert.equal(r.frame,null);
 r.start(f.grant);assert.equal(r.frame.getAttribute('sandbox'),'allow-scripts allow-same-origin');assert.equal(r.frame.referrerPolicy,'no-referrer');
 f.message('ack',{protocol:1});f.message('ack',{instance:'forged'});f.message('ack',{generation:6});assert.equal(f.ready(),0);
 f.message('ready');f.message('ack');assert.equal(f.ready(),1);assert.equal(r.track({event:'page_view'}),true);
 r.renew(Date.now()+60000);assert.equal(f.ready(),1);r.stop();f.message('ack');assert.equal(r.track({event:'page_view'}),false);
});
test('policy A / Worker B mismatches before init, and old frames/ACKs cannot revive',t=>{
 const f=fixture(t),r=f.transport;r.start(f.grant);const old=r.frame.contentWindow,instance=r.instance;
 f.message('ready',{manifest:{...manifest,processing_revision:'b'}});assert.equal(f.mismatches(),1);assert.equal(r.frame,null);
 r.start({...f.grant,generation:8});f.dom.window.dispatchEvent(new f.dom.window.MessageEvent('message',{source:old,origin:runtime,data:{namespace:'festapp-measurement',protocol:2,type:'ack',manifest,instance,generation:7}}));
 assert.equal(f.ready(),0);r.frame.remove();f.message('ack',{generation:8});assert.equal(f.ready(),0);
});
for(const hidden of [false,true])test('expiry destroys the runtime even when hidden='+hidden,async t=>{
 const f=fixture(t);f.transport.start({...f.grant,expiresAt:Date.now()+10});Object.defineProperty(f.dom.window.document,'hidden',{value:hidden});
 await new Promise(r=>setTimeout(r,30));assert.equal(f.transport.frame,null);assert.equal(f.transport.track({event:'page_view'}),false);
});
function bootstrap(t,consent={analytics:true,marketing:true},manifestOverride=manifest){
 const boot={...config,manifest};const dom=new JSDOM('<head><script type="application/json" id="measurement-config"></script></head>',{url:runtime+'/runtime',runScripts:'outside-only'});
 const win=dom.window;win.document.getElementById('measurement-config').textContent=JSON.stringify({...boot,gtm_container:'GTM-AB12',scripts:'window.tagRuns=(window.tagRuns||0)+1'});win.eval(runtimeSource);
 const send=(type,extra={})=>win.dispatchEvent(new win.MessageEvent('message',{source:win.parent,origin:parent,data:{namespace:'festapp-measurement',protocol:2,type,manifest:manifestOverride,instance:'instance',generation:7,consent,context:{page_location:parent+'/form/summer',gclid:'click'},...extra}}));
 t.after(()=>win.close());return{win,send};
}
for(const consent of [null,false,true,{analytics:true},{marketing:true},{analytics:false,marketing:false}])test('bootstrap refuses Unit code and events for '+JSON.stringify(consent),t=>{
 const f=bootstrap(t,consent);f.send('init');f.send('event',{payload:purchase});assert.equal(f.win.tagRuns,undefined);assert.equal(f.win.document.querySelector('script[src]'),null);assert.equal(f.win.dataLayer.length,0);
});
test('bootstrap rejects mismatched snapshot before code and establishes Consent Mode before script effects',t=>{
 const wrong=bootstrap(t,{analytics:true,marketing:true},{...manifest,runtime_revision:2});wrong.send('init');assert.equal(wrong.win.document.querySelector('script[src]'),null);
 const f=bootstrap(t);f.send('init');const entries=f.win.dataLayer;
 assert.equal(entries[0][0],'consent');assert.equal(entries[0][1],'default');assert.equal(entries[0][2].ad_storage,'granted');assert.equal(entries[1][1],'update');
 assert.equal(f.win.document.querySelectorAll('script[src]').length,1);assert.ok(f.win.document.querySelector('script[src]').src.includes('GTM-AB12'));
 f.send('event',{payload:{...purchase,user_data:{email:'PRIVATE@example.test',phone_number:'+420601234567'}}});
 assert.equal(entries.filter(p=>p.event==='purchase').length,1);assert.doesNotMatch(JSON.stringify(entries),/PRIVATE|601234567|"user_data"/);
 f.send('event',{generation:6,payload:purchase});assert.equal(entries.filter(p=>p.event==='purchase').length,1);
});
test('Klaro saved-choice adapter rejects drafts and unavailable services; disconnect revokes',()=>{
 let watcher;const sent=[];const manager={confirmed:false,savedConsents:{analytics:false},getConsent:()=>true,watch:value=>watcher=value,unwatch:value=>assert.equal(value,watcher)};
 const stop=bindKlaroConsent(manager,value=>sent.push(value));manager.confirmed=true;watcher.update();assert.deepEqual(sent.at(-1),{analytics:false,marketing:false});
 manager.savedConsents.analytics=true;watcher.update();assert.deepEqual(sent.at(-1),{analytics:true,marketing:false});manager.savedConsents.marketing=true;watcher.update();assert.deepEqual(sent.at(-1),{analytics:true,marketing:true});stop();assert.equal(sent.at(-1),false);
});
test('attribution retains allowed campaign/click IDs and drops credentials and private contexts',()=>{
 assert.equal(measurementOrigin(runtime),runtime);for(const bad of ['https://tenant.runtime.example',runtime+'/',runtime+'?x=1','http://localhost:3000'])assert.equal(measurementOrigin(bad),null);
 const result=attributionContext({page_location:parent+'/form/summer',page_referrer:'https://ref.example/private?token=SECRET#hash',gclid:'click',gbraid:'app',utm_term:'PRIVATE@example.test',token:'SECRET'});
 assert.deepEqual(result,{page_location:parent+'/form/summer',page_referrer:'https://ref.example/',gclid:'click',gbraid:'app'});
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
