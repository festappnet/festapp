import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {runtimeSource} from '../../../workers/form-measurement/src/runtime_source.mjs';
import {serveMeasurement} from '../../../workers/form-measurement/src/worker.mjs';
import {FormMeasurementRuntime} from '../../src/components/forms/form_measurement_runtime.js';
import {bindKlaroConsent} from '../../src/components/forms/form_measurement_consent.js';
import {attributionContext,measurementPageLocation,campaignContext,measurementOrigin} from '../../src/components/forms/form_measurement_contract.js';
const runtime='https://festival-measurement.pages.dev',parent='https://tickets.example';
const policy={enabled:true,organization_allowed:true,eligible:true,runtime_supported:true,organization:1,unit:2,runtime_origin:runtime,valid_for_seconds:60,policy_revision:1,configuration_revision:'one'};
const config={organization:1,unit:2,form_id:3,form_link:'summer',runtime_origin:runtime,parent_origin:parent,profile:'gtm-v1',ancestor_origins:[parent],collector_origins:['https://www.google-analytics.com'],policy,gtm_container:'GTM-W9WRHWT9',scripts:'</script><script>window.test=1</script>'};
const request=new Request(runtime+'/runtime?form=summer&parent='+encodeURIComponent(parent));
const env={ORGANIZATION_ID:1,UNIT_ID:2};

test('runtime server binds stored organization/form/origin and escapes its scoped configuration',async()=>{
 let args;const response=await serveMeasurement(request,env,async value=>{args=value;return config});
 assert.equal(response.status,200);assert.deepEqual(args,{p_form_link:'summer',p_organization:1,p_unit:2,p_runtime_origin:runtime,p_parent_origin:parent});
 const html=await response.text();assert.ok(!html.includes(config.scripts));assert.ok(html.includes('\\u003c/script>'));
 const csp=response.headers.get('content-security-policy');
 for(const directive of ["worker-src 'none'","frame-src 'none'","object-src 'none'","form-action 'none'",'frame-ancestors '+parent])assert.ok(csp.includes(directive));
 assert.equal(response.headers.get('cache-control'),'no-store');assert.equal(response.headers.get('referrer-policy'),'no-referrer');
 for(const bad of [{...config,organization:2},{...config,form_link:'other'},{...config,parent_origin:'https://other.example'},
  {...config,runtime_origin:'https://other.pages.dev'},{...config,policy:{...policy,eligible:false}},
  {...config,collector_origins:[parent]},{...config,collector_origins:['https://api.festapp.net']},
  {...config,collector_origins:['https://collect.example; script-src *']},{...config,scripts:'x'.repeat(5001)}]){
  assert.equal((await serveMeasurement(request,env,async()=>bad)).status,404);
 }
 assert.equal((await serveMeasurement(new Request('https://worker.account.workers.dev/runtime?form=summer&parent='+parent),env,async()=>config)).status,404);
 assert.equal((await serveMeasurement(request,env,async()=>{throw Error('SECRET')})).status,404);
});

test('Pages canonical project sites alone are accepted and attribution is rebuilt without raw URLs',()=>{
 assert.equal(measurementOrigin(runtime),runtime);
 for(const value of ['https://tenant.runtime.example','https://tenant.festival-measurement.pages.dev',runtime+'/',runtime+'?x=1','http://localhost:3000'])assert.equal(measurementOrigin(value),null);
 const result=attributionContext({page_location:parent+'/form/summer',page_referrer:'https://ref.example/private?token=secret#hash',gclid:'valid-123',utm_source:'newsletter',utm_term:'email@private.example',token:'secret'});
 assert.deepEqual(result,{page_location:parent+'/form/summer',page_referrer:'https://ref.example/',utm_source:'newsletter',gclid:'valid-123'});
 assert.equal(attributionContext({page_location:parent+'/form/summer?token=secret'}),null);
});

function fixture(){
 const dom=new JSDOM('<body></body>',{url:parent+'/form/summer?gclid=valid123',pretendToBeVisual:true});let ready=0;
 const model={link:'summer',data:{analytics:{...policy}}};let safe=true;
 const transport=new FormMeasurementRuntime({win:dom.window,model,canRun:()=>safe,onReady:()=>ready++});
 const message=(type,extra={})=>dom.window.dispatchEvent(new dom.window.MessageEvent('message',{source:transport.frame?.contentWindow,origin:runtime,data:{namespace:'festapp-measurement',protocol:1,type,instance:transport.instance,...extra}}));
 return{dom,model,transport,message,ready:()=>ready,unsafe:()=>safe=false};
}

test('frame starts only on grant, pins handshake and preserves epoch across renewals',()=>{
 const f=fixture(),t=f.transport;
 assert.equal(t.frame,undefined);assert.equal(t.track({event:'page_view'}),false);
 t.setConsent(true);assert.equal(t.frame.getAttribute('sandbox'),'allow-scripts allow-same-origin');assert.equal(t.frame.referrerPolicy,'no-referrer');
 f.message('ack',{instance:'forged'});assert.equal(t.measurementAllowed(),false);
 f.message('ready');f.message('ack');assert.equal(f.ready(),1);assert.equal(t.measurementAllowed(),true);
 const epoch=t.measurementEpoch();t.setConsent(true);assert.equal(t.measurementEpoch(),epoch);
 f.model.data.analytics.configuration_revision='two';t.updatePolicy();assert.equal(t.measurementAllowed(),false);assert.notEqual(t.instance,epoch);
 f.message('ready');f.message('ack');assert.equal(t.measurementAllowed(),true);
 f.unsafe();f.dom.window.dispatchEvent(new f.dom.window.Event('hashchange'));assert.equal(t.frame,null);
 t.setConsent(true);assert.equal(t.frame,null);t.destroy();f.dom.window.close();
});

test('policy and consent expiry destroy the browsing context rather than merely dropping sends',async()=>{
 const f=fixture(),t=f.transport;t.setConsent(true);f.message('ack');t.updatePolicy(Date.now()+10);
 await new Promise(resolve=>setTimeout(resolve,30));assert.equal(t.frame,null);assert.equal(t.track({event:'page_view'}),false);
 t.destroy();f.dom.window.close();
});

test('Klaro saved-choice adapter never grants from a draft and unbind revokes',()=>{
 const dom=new JSDOM('',{pretendToBeVisual:true}),sent=[];let watcher;
 const manager={confirmed:false,savedConsents:{analytics:false},getConsent:()=>true,watch:value=>watcher=value,unwatch:value=>assert.equal(value,watcher)};
 const stop=bindKlaroConsent(manager,value=>sent.push(value),{win:dom.window});assert.equal(sent.at(-1),false);
 manager.confirmed=true;watcher.update();assert.equal(sent.at(-1),false);
 manager.savedConsents.analytics=true;watcher.update();assert.equal(sent.at(-1),true);
 manager.getConsent=()=>{throw Error('CMP failure')};watcher.update();assert.equal(sent.at(-1),false);
 stop();assert.equal(sent.at(-1),false);dom.window.close();
});

test('reserved public aliases use canonical form attribution and destroyed Auth context cannot be revived by a lease',()=>{
 const f=fixture(),t=f.transport;f.dom.reconfigure({url:parent+'/form/old-alias?gclid=valid123'});
 t.setConsent(true);assert.equal(t.context.page_location,parent+'/form/summer');
 t.destroy();t.setConsent(true);assert.equal(t.frame,null);assert.equal(t.measurementAllowed(),false);f.dom.window.close();
});

test('an organizer scope move cannot recycle consent saved for the previous Unit',()=>{
 const f=fixture(),t=f.transport;t.setConsent(true);f.message('ack');assert.equal(t.measurementAllowed(),true);
 f.model.data.analytics.unit=99;t.updatePolicy();assert.equal(t.frame,null);
 t.setConsent(true);assert.equal(t.frame,null);assert.equal(t.measurementAllowed(),false);f.dom.window.close();
});

test('campaign URLs preserve human labels while excluding contacts, controls and unknown parameters',()=>{
 const input={page_location:parent+'/form/summer',utm_source:'Letní kampaň + A|B',utm_campaign:'ž'.repeat(256),utm_content:'x'.repeat(257),utm_term:'mail@example.test',gclid:'a\u007fb',fbclid:'a\nb',token:'private'};
 assert.deepEqual(campaignContext(input),{utm_source:input.utm_source,utm_campaign:input.utm_campaign});
 const location=new URL(measurementPageLocation(input));
 assert.equal(location.searchParams.get('utm_source'),input.utm_source);
 assert.equal(location.searchParams.get('utm_campaign'),input.utm_campaign);
 assert.deepEqual([...location.searchParams.keys()],['utm_source','utm_campaign']);
 assert.equal(measurementPageLocation({...input,page_location:input.page_location+'?token=private'}),null);
});

test('real runtime bootstrap validates the bare form URL before exposing a campaign URL',()=>{
 for(const suffix of ['', '?token=private']) {
  const dom=new JSDOM('<body><script id="measurement-config" type="application/json"></script></body>',{url:runtime+'/runtime',runScripts:'outside-only'});
  const win=dom.window;
  win.document.querySelector('#measurement-config').textContent=JSON.stringify({parent_origin:parent,form_link:'summer'});
  win.eval(runtimeSource);
  win.dispatchEvent(new win.MessageEvent('message',{source:win.parent,origin:parent,data:{namespace:'festapp-measurement',protocol:1,instance:'valid_instance',type:'init',context:{page_location:parent+'/form/summer'+suffix,utm_source:'Letní + akce',token:'private'}}}));
  if(suffix)assert.deepEqual(Array.from(win.dataLayer),[]);
  else {
   assert.equal(win.dataLayer[0].page_location,parent+'/form/summer?utm_source=Letn%C3%AD+%2B+akce');
   assert.equal(win.dataLayer[0].token,undefined);
  }
  win.close();
 }
});
