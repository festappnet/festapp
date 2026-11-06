import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {runtimeSource} from '../../../workers/form-measurement/src/runtime_source.mjs';
import {serveMeasurement} from '../../../workers/form-measurement/src/worker.mjs';
import {FormMeasurementRuntime} from '../../src/components/forms/form_measurement_runtime.js';
import {bindKlaroConsent} from '../../src/components/forms/form_measurement_consent.js';
import {attributionContext,measurementPageLocation,campaignContext,measurementOrigin} from '../../src/components/forms/form_measurement_contract.js';
import {publicFormLocation,publicFormAttributionSearch} from '../../src/utils/public_form_location.js';
const runtime='https://festival-measurement.pages.dev',parent='https://tickets.example';
const policy={enabled:true,organization_allowed:true,privacy_url:"https://organizer.example/privacy",eligible:true,runtime_supported:true,organization:1,unit:2,runtime_origin:runtime,valid_for_seconds:60,policy_revision:1,configuration_revision:'one'};
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

test('frame starts without any consent, pins the handshake and survives renewals',()=>{
 const f=fixture(),t=f.transport;
 assert.equal(t.frame,undefined);assert.equal(t.track({event:'page_view'}),false);
 t.start();assert.equal(t.frame.getAttribute('sandbox'),'allow-scripts allow-same-origin');assert.equal(t.frame.referrerPolicy,'no-referrer');
 f.message('ack',{instance:'forged'});assert.equal(t.measurementAllowed(),false);
 f.message('ready');f.message('ack');assert.equal(f.ready(),1);assert.equal(t.measurementAllowed(),true);
 const instance=t.instance;t.updatePolicy();assert.equal(t.instance,instance);
 f.model.data.analytics.configuration_revision='two';t.updatePolicy();assert.equal(t.measurementAllowed(),false);assert.notEqual(t.instance,instance);
 f.message('ready');f.message('ack');assert.equal(t.measurementAllowed(),true);
 f.unsafe();f.dom.window.dispatchEvent(new f.dom.window.Event('hashchange'));assert.equal(t.frame,null);
 t.start();assert.equal(t.frame,null);t.destroy();f.dom.window.close();
});

test('policy expiry destroys the browsing context of a visible page rather than merely dropping sends',async()=>{
 const f=fixture(),t=f.transport;t.start();f.message('ack');t.updatePolicy(Date.now()+10);
 await new Promise(resolve=>setTimeout(resolve,30));assert.equal(t.frame,null);assert.equal(t.track({event:'page_view'}),false);
 t.destroy();f.dom.window.close();
});

test('a hidden page keeps its frame through expiry, without sending, so the container does not run twice',async()=>{
 const f=fixture(),t=f.transport;t.start();f.message('ack');const frame=t.frame;
 Object.defineProperty(f.dom.window.document,'hidden',{value:true,configurable:true});
 t.updatePolicy(Date.now()+10);await new Promise(resolve=>setTimeout(resolve,30));
 assert.equal(t.frame,frame);assert.equal(t.track({event:'page_view'}),false);
 Object.defineProperty(f.dom.window.document,'hidden',{value:false,configurable:true});
 t.updatePolicy(Date.now()+60000);assert.equal(t.frame,frame);assert.equal(t.measurementAllowed(),true);
 t.destroy();f.dom.window.close();
});

test('Klaro saved-choice adapter never grants from a draft and unbind revokes',()=>{
 const dom=new JSDOM('',{pretendToBeVisual:true}),sent=[];let watcher;
 const manager={confirmed:false,savedConsents:{analytics:false},getConsent:()=>true,watch:value=>watcher=value,unwatch:value=>assert.equal(value,watcher)};
 const stop=bindKlaroConsent(manager,value=>sent.push(value));assert.deepEqual(sent.at(-1),{analytics:false,marketing:false});
 manager.confirmed=true;watcher.update();assert.deepEqual(sent.at(-1),{analytics:false,marketing:false});
 manager.savedConsents.analytics=true;watcher.update();assert.deepEqual(sent.at(-1),{analytics:true,marketing:false},'a manager without marketing grants analytics only');
 manager.savedConsents.marketing=true;watcher.update();assert.deepEqual(sent.at(-1),{analytics:true,marketing:true});
 manager.savedConsents.analytics=false;watcher.update();assert.deepEqual(sent.at(-1),{analytics:false,marketing:true},'purposes are independent');
 manager.getConsent=()=>{throw Error('CMP failure')};watcher.update();assert.deepEqual(sent.at(-1),{analytics:false,marketing:false});
 stop();assert.equal(sent.at(-1),false);dom.window.close();
});

test('reserved public aliases use canonical form attribution and destroyed Auth context cannot be revived by a lease',()=>{
 const f=fixture(),t=f.transport;f.dom.reconfigure({url:parent+'/form/old-alias?gclid=valid123'});
 t.start();assert.equal(t.context.page_location,parent+'/form/summer');
 t.destroy();t.start();assert.equal(t.frame,null);assert.equal(t.measurementAllowed(),false);f.dom.window.close();
});

test('an organizer scope move ends the frame of the previous Unit',()=>{
 const f=fixture(),t=f.transport;t.start();f.message('ack');assert.equal(t.measurementAllowed(),true);
 f.model.data.analytics.unit=99;t.updatePolicy();assert.equal(t.frame,null);
 t.start();assert.equal(t.frame,null);assert.equal(t.measurementAllowed(),false);f.dom.window.close();
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

test('Google app, Sklik, TikTok and Microsoft click IDs pass every attribution gate with the shared validation',()=>{
 const ids={gbraid:'gb_1',wbraid:'wb_1',sznclid:'szn.1',ttclid:'tt-1',msclkid:'0123456789abcdef'};
 const search='?'+new URLSearchParams(ids);
 assert.deepEqual(campaignContext({...ids,token:'private'}),ids);
 for(const key of Object.keys(ids)){
  assert.deepEqual(campaignContext({[key]:'x'.repeat(256)}),{[key]:'x'.repeat(256)});
  for(const value of ['x'.repeat(257),'','mail@example.test','a\nb','a\u007fb',7])assert.deepEqual(campaignContext({[key]:value}),{},key);
 }
 const context=attributionContext({page_location:parent+'/form/summer',...ids});
 assert.deepEqual(context,{page_location:parent+'/form/summer',...ids});
 assert.deepEqual(Object.fromEntries(new URL(measurementPageLocation(context)).searchParams),ids);
 assert.equal(publicFormLocation(new URL(parent+'/form/summer'+search),{entry:true}),true);
 assert.equal(publicFormAttributionSearch(new URL(parent+'/form/summer'+search+'&token=private')),search);
 const embed=readFileSync(new URL('../../public/embed.js',import.meta.url),'utf8');
 for(const key of Object.keys(ids)){assert.ok(embed.includes(`'${key}'`),key);assert.ok(runtimeSource.includes(`"${key}"`),key);}
});

test('real runtime bootstrap validates the bare form URL before exposing a campaign URL',()=>{
 for(const suffix of ['', '?token=private']) {
  const dom=new JSDOM('<body><script id="measurement-config" type="application/json"></script></body>',{url:runtime+'/runtime',runScripts:'outside-only'});
  const win=dom.window;
  win.document.querySelector('#measurement-config').textContent=JSON.stringify({parent_origin:parent,form_link:'summer'});
  win.eval(runtimeSource);
  win.dispatchEvent(new win.MessageEvent('message',{source:win.parent,origin:parent,data:{namespace:'festapp-measurement',protocol:1,instance:'valid_instance',type:'init',consent:{analytics:true,marketing:false},context:{page_location:parent+'/form/summer'+suffix,utm_source:'Letní + akce',token:'private'}}}));
  if(suffix)assert.deepEqual(Array.from(win.dataLayer),[]);
  else {
   assert.equal(win.dataLayer[2].page_location,parent+'/form/summer?utm_source=Letn%C3%AD+%2B+akce');
   assert.equal(win.dataLayer[2].token,undefined);
  }
  win.close();
 }
});

function bootstrapped(consent,config={}){
 const dom=new JSDOM('<body><script id="measurement-config" type="application/json"></script></body>',{url:runtime+'/runtime',runScripts:'outside-only'});
 const win=dom.window,scripts=[];
 win.document.querySelector('#measurement-config').textContent=JSON.stringify({parent_origin:parent,form_link:'summer',gtm_container:'GTM-W9WRHWT9',...config});
 win.eval(runtimeSource);
 const append=win.document.head.append.bind(win.document.head);
 win.document.head.append=node=>{scripts.push(node.src||'inline');if(!node.src)append(node);};
 const send=data=>win.dispatchEvent(new win.MessageEvent('message',{source:win.parent,origin:parent,data:{namespace:'festapp-measurement',protocol:1,instance:'valid_instance',...data}}));
 send({type:'init',consent,context:{page_location:parent+'/form/summer'}});
 return{win,scripts,send,event:payload=>send({type:'event',payload})};
}
const contact={email:'visitor@example.test',phone_number:'+420601234567'},sale={event:'purchase',email:'private@example.test',user_data:{...contact,sha256_email_address:'a'.repeat(64),first_name:'private@example.test'},ecommerce:{currency:'CZK',transaction_id:'c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44',payment_type:'card',items:[{item_id:'product_1',item_name:'Ticket',price:100,quantity:1}]}};
const command=entry=>[entry[0],entry[1],{...entry[2]}];
const states=(analytics,ads)=>({analytics_storage:analytics,ad_storage:ads,ad_user_data:ads,ad_personalization:ads});

for(const [consent,analytics,ads] of [[undefined,'denied','denied'],[null,'denied','denied'],[{analytics:false,marketing:false},'denied','denied'],[{analytics:'true',marketing:1},'denied','denied'],[{analytics:true,marketing:false},'granted','denied'],[{analytics:false,marketing:true},'denied','granted'],[{analytics:true,marketing:true},'granted','granted']]) {
 test('bootstrap queues Consent Mode and loads tags whatever the choice: '+JSON.stringify(consent),()=>{
  const {win,scripts}=bootstrapped(consent,{scripts:'<script>window.unit=1</script>'});
  assert.equal(Object.prototype.toString.call(win.dataLayer[0]),'[object Arguments]','tag libraries ignore a plain array');
  assert.deepEqual(command(win.dataLayer[0]),['consent','default',states(analytics,ads)]);
  assert.deepEqual(command(win.dataLayer[1]),['consent','update',states(analytics,ads)],'a container default cannot replace the saved choice');
  assert.deepEqual({...win.dataLayer[2].festapp_consent},{analytics:analytics==='granted',marketing:ads==='granted'});
  assert.ok(scripts[0].startsWith('https://www.googletagmanager.com/gtm.js'));assert.equal(scripts.length,2,'Unit scripts run too');
  assert.ok(win.dataLayer.findIndex(x=>x.event==='gtm.js')>1);win.close();
 });
}

test('a changed choice updates Consent Mode and tells tags, in the same frame',()=>{
 const {win,scripts,send,event}=bootstrapped(undefined);
 send({type:'consent',consent:{analytics:true,marketing:false}});
 assert.deepEqual(command(win.dataLayer.at(-2)),['consent','update',states('granted','denied')]);
 assert.deepEqual({...win.dataLayer.at(-1)},{event:'festapp_consent_update',analytics:true,marketing:false});
 assert.equal(scripts.length,1,'the container is not loaded again');
 event({event:'page_view'});assert.deepEqual({...win.dataLayer.at(-1).festapp_consent},{analytics:true,marketing:false});
 send({type:'consent',consent:{analytics:false,marketing:false}});assert.deepEqual(command(win.dataLayer.at(-2)),['consent','update',states('denied','denied')]);
 const length=win.dataLayer.length;send({type:'consent',instance:'forged',consent:{analytics:true,marketing:true}});assert.equal(win.dataLayer.length,length);win.close();
});

test('bootstrap passes contact on conversions under any choice, rebuilt, then clears it',()=>{
 for(const consent of [undefined,{analytics:true,marketing:false},{analytics:true,marketing:true}]) {
  const {win,event}=bootstrapped(consent);event(sale);
  assert.deepEqual({...Array.from(win.dataLayer).find(x=>x.event==='purchase').user_data},contact);
  assert.equal(JSON.stringify(Array.from(win.dataLayer)).includes('private@example.test'),false);
  assert.deepEqual({...win.dataLayer.at(-1)},{user_data:null});win.close();
 }
});

test('changing a purpose keeps the frame and only informs it; refusal stops nothing',()=>{
 const f=fixture(),t=f.transport,sent=[];t.start();
 Object.defineProperty(t.frame,'contentWindow',{value:{postMessage:message=>sent.push(message)}});
 f.message('ready');assert.deepEqual(sent[0].consent,{analytics:false,marketing:false},'denied without a saved choice');f.message('ack');
 const frame=t.frame,instance=t.instance;
 t.setConsent({analytics:true,marketing:false});assert.equal(t.frame,frame);assert.equal(t.instance,instance);assert.equal(sent.at(-1).type,'consent');assert.deepEqual(sent.at(-1).consent,{analytics:true,marketing:false});
 const count=sent.length;t.setConsent({analytics:true,marketing:false});assert.equal(sent.length,count,'an unchanged state sends nothing');
 t.setConsent(false);assert.equal(t.frame,frame);assert.equal(t.measurementAllowed(),true);assert.deepEqual(sent.at(-1).consent,{analytics:false,marketing:false});
 t.destroy();f.dom.window.close();
});

test('a frame that never answers is not reloaded on every renewal',t=>{
 t.mock.timers.enable({apis:['setTimeout']});
 const f=fixture(),r=f.transport;const win=f.dom.window;let timeout;win.setTimeout=(fn,ms)=>{if(ms===8000)timeout=fn;return 0;};
 r.start();const instance=r.instance;timeout();assert.equal(r.frame,null);r.updatePolicy();assert.equal(r.frame,null);
 f.model.data.analytics.configuration_revision='next';r.updatePolicy();assert.ok(r.frame);assert.notEqual(r.instance,instance);r.destroy();win.close();
});

test('notice content and approved hosts stay out of the frame configuration',async()=>{
 const html=await (await serveMeasurement(request,env,async()=>({...config,policy:{...policy,consent_notice:{layout:'bar',title:'NOTICE_SENTINEL',text:'NOTICE_SENTINEL'},approved_hosts:['https://host.example']}}))).text();
 assert.equal(html.includes('NOTICE_SENTINEL'),false);assert.equal(html.includes('host.example'),false);
});
