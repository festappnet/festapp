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
 assert.equal(entries[0][0],'consent');assert.equal(entries[0][1],'default');assert.equal(entries[0][2].ad_storage,'granted');assert.equal(entries[1][1],'update');assert.equal(entries[0][2].personalization_storage,'granted');assert.equal(entries[0][2].functionality_storage,'granted');assert.equal(entries[0][2].security_storage,'granted');
 assert.equal(f.win.document.querySelectorAll('script[src]').length,1);assert.ok(f.win.document.querySelector('script[src]').src.includes('GTM-AB12'));
 f.send('event',{payload:{...purchase,user_data:{email:'buyer@example.test',phone_number:'+420601234567',first_name:'PRIVATE'}}});
 assert.equal(entries.filter(p=>p.event==='purchase').length,1);assert.equal(JSON.stringify(entries.find(p=>p.event==='purchase').user_data),'{"email":"buyer@example.test","phone_number":"+420601234567"}');
 assert.doesNotMatch(JSON.stringify(entries),/PRIVATE/);assert.equal(entries.at(-1).user_data,null,'the contact does not carry over to later events');
 f.send('event',{generation:6,payload:purchase});assert.equal(entries.filter(p=>p.event==='purchase').length,1);
});
test('isolated Google tags receive cross-site cookie flags before loading without changing consent',t=>{
 const f=bootstrap(t,false);f.send('init');const entries=[...f.win.dataLayer];
 assert.ok(entries.some(p=>p[0]==='set' && p[1]==='ads_data_redaction' && p[2]===true));
 const cookieSettings=entries.findIndex(p=>p[0]==='set' && p[1]?.cookie_flags==='SameSite=None;Secure;Partitioned');
 assert(cookieSettings>=0,'framed Google tags require explicit cross-site cookie flags');
 assert(cookieSettings<entries.findIndex(p=>p.event==='gtm.js'));
 assert.equal(entries[0][2].analytics_storage,'denied');assert.equal(entries[1][2].analytics_storage,'denied');
 for(const entry of entries.slice(0,2)) assert.deepEqual({...entry[2]},{analytics_storage:'denied',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied',functionality_storage:'granted',security_storage:'granted',personalization_storage:'denied'},'every Consent Mode type is explicit');
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
 assert.equal(publicFormAttributionSearch(new URL(parent+'/form/summer?_gl=x&gtm_debug=1&utm_id=2')),'?utm_id=2&_gl=x&gtm_debug=1');
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
 const pageEvent=expected?'form_page_view':'page_view';
 f.send('event',{payload:{event:'page_view',form_embedded:!expected}});
 f.send('event',{payload:purchase});f.send('consent',{consent:true});
 assert.equal(entries.some(p=>p.event===(expected?'page_view':'form_page_view')),false);
 for(const event of [pageEvent,'purchase'])assert.equal(entries.find(p=>p.event===event).form_embedded,expected,'events carry context');
 assert.equal(attributionContext({page_location:parent+'/form/summer',form_embedded:value}).form_embedded,expected);
});

for(const embedded of [false,true])test('runtime preserves the wire page event across receiver upgrades: '+embedded,t=>{
 const f=fixture(t,embedded),r=f.transport,sent=[];r.activate(f.grant);
 r.frame.contentWindow.postMessage=data=>sent.push(data);f.message('ready');f.message('ack');
 assert.equal(r.track({event:'page_view'}),true);
 assert.deepEqual(sent.filter(m=>m.type==='event').map(m=>m.payload.event),['page_view']);
});

test('isolated runtime attaches its validated page context to each event',t=>{
 const f=bootstrap(t);f.send('init');
 f.send('event',{payload:{page_type:'sale_opening',language:'cs'}});
 f.send('event',{payload:{event:'form_start',page_type:'product',language:'de'}});
 const event=f.win.dataLayer.find(p=>p.event==='form_start');
 assert.equal(event.page_type,'sale_opening');assert.equal(event.language,'cs');
 f.send('event',{payload:{page_type:'checkout'}});
 f.send('event',{payload:{event:'form_submit_error'}});
 assert.equal(f.win.dataLayer.find(p=>p.event==='form_submit_error').language,null);
});

test('host identity is bounded, purpose filtered and read raw without decoding', async () => {
 const {measurementHostIdentity,measurementSignals}=await import('../../src/components/forms/form_measurement_contract.js');
 const {readHostMeasurementIdentity}=await import('../../src/embed/host_measurement.js');
 const cookies={_ga:'GA1.1.123.456',_ga_AB12:'GS2.1.s123$o1',_ga_bad:'bad',_gcl_aw:'GCL.123.click',_fbp:'fb.1.123.456',secret:'private',_fbc:'bad%20value',_gcl_au:'a'.repeat(513)};
 assert.deepEqual(measurementHostIdentity(cookies,false),{});
 assert.deepEqual(measurementHostIdentity(cookies,true),{_ga:cookies._ga,_ga_AB12:cookies._ga_AB12});
 assert.deepEqual(measurementHostIdentity(cookies,{marketing:true}),{_gcl_aw:cookies._gcl_aw,_fbp:cookies._fbp});
 assert.equal(Object.keys(measurementHostIdentity(Object.fromEntries(Array.from({length:20},(_,i)=>['_ga_A'+i,'x'])),true)).length,10);
 assert.deepEqual(readHostMeasurementIdentity({cookie:'_ga=GA1.1.123.456; _fbp=fb.1.123.456; _fbc=bad%20value'},true),{_ga:cookies._ga});
 assert.deepEqual(readHostMeasurementIdentity({get cookie(){throw Error('blocked');}},true),{});
 assert.deepEqual(measurementSignals({_gl:'1*abc._-1',gtm_debug:'x',gclid:'click'}),{_gl:'1*abc._-1',gtm_debug:'x'});
 for(const value of ['', 'a'.repeat(2049),'a@b','a\nb','a%20','a$b'])assert.equal(measurementSignals({_gl:value})._gl,undefined);
});
test('runtime init and updates retain identity only for embedded granted purposes',t=>{
 const f=fixture(t,true),sent=[];f.transport.activate({...f.grant,hostIdentity:{_ga:'GA1.1.123.456',_fbp:'fb.1.123.456',secret:'bad'}});
 f.transport.frame.contentWindow.postMessage=data=>sent.push(data);f.message('ready');
 assert.deepEqual(sent[0].hostIdentity,{_ga:'GA1.1.123.456',_fbp:'fb.1.123.456'});
 f.transport.updateConsent({marketing:true},{_ga:'GA1.1.123.456',_fbp:'fb.1.123.456'});
 assert.deepEqual(sent.at(-1).hostIdentity,{_fbp:'fb.1.123.456'});
 f.transport.updateConsent(false,{_ga:'GA1.1.123.456'});assert.deepEqual(sent.at(-1).hostIdentity,{});
});
// Model host-only/domain and partitioned/unpartitioned as distinct cookie slots.
function cookieJar(win) {
 const jar=new Map(),writes=[];
 const key=(name,domain,partition)=>JSON.stringify([name,domain,partition]);
 const seed=(name,value,domain=false,partition=false)=>jar.set(key(name,domain,partition),{name,value});
 Object.defineProperty(win.document,'cookie',{get:()=>[...jar.values()].map(x=>x.name+'='+x.value).join('; '),set:value=>{
  writes.push(value);const [pair]=value.split(';'),i=pair.indexOf('=');
  const slot=key(pair.slice(0,i),value.includes('; Domain='+win.location.hostname),value.includes('; Partitioned'));
  if(/; Max-Age=0(?:;|$)/.test(value))jar.delete(slot);else jar.set(slot,{name:pair.slice(0,i),value:pair.slice(i+1)});
 }});
 return {jar,writes,seed,values:name=>[...jar.values()].filter(x=>x.name===name).map(x=>x.value)};
}
test('bootstrap replaces all old cookie variants and removes foreign GA sessions and revoked tag cookies',t=>{
 const f=bootstrap(t),j=cookieJar(f.win),now=Math.floor(Date.now()/1000);
 for(const domain of [true,false])for(const partition of [true,false]) {
  j.seed('_ga','GA1.1.999.999',domain,partition);j.seed('_ga_OTHER','GS2.1.s999',domain,partition);
 }
 j.seed('unrelated','keep');
 f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:true},hostIdentity:{_ga:'GA1.1.123.456',_ga_AB:'GS2.1.s123$o1',_gcl_aw:`GCL.${now}.click-id`,_fbp:'fb.1.123.456'}});
 assert.deepEqual(j.values('_ga'),['GA1.1.123.456']);assert.deepEqual(j.values('_ga_OTHER'),[]);
 assert(j.writes.some(x=>x.includes('Max-Age=63072000; Domain='+f.win.location.hostname+'; Path=/; SameSite=None; Secure; Partitioned')));
 assert.equal(new URL(f.win.location.href).searchParams.has('gclid'),false);
 // A tag can write more domain cookies after the initial copy.
 for(const domain of [true,false])for(const partition of [true,false])j.seed('_gcl_au','1.2.3',domain,partition);
 f.send('consent',{consent:false});
 assert.deepEqual([...j.jar.values()],[{name:'unrelated',value:'keep'}]);
});
test('without a host _ga snapshot existing GA sessions remain intact while analytics is granted',t=>{
 const f=bootstrap(t),j=cookieJar(f.win);j.seed('_ga_OTHER','GS2.1.s999',true,false);
 f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:true},hostIdentity:{_fbp:'fb.1.123.456'}});
 assert.deepEqual(j.values('_ga_OTHER'),['GS2.1.s999']);
});
test('ambiguous readback triggers fallback even when one duplicate matches the copy',t=>{
 const f=bootstrap(t);
 Object.defineProperty(f.win.document,'cookie',{get:()=> '_ga=GA1.1.999.999; _ga=GA1.1.123.456',set:()=>{}});
 f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:true},hostIdentity:{_ga:'GA1.1.123.456'}});
 assert(f.win.dataLayer.some(x=>x[0]==='set'&&x[1]?.client_id==='123.456'));
});
test('advertising copies retain only the remaining timestamp lifetime',t=>{
 const f=bootstrap(t),j=cookieJar(f.win),now=Math.floor(Date.now()/1000),day=86400;
 f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:true},hostIdentity:{_gcl_aw:`GCL.${now-89*day}.click`,_fbc:`fb.1.${(now-91*day)*1000}.IwZX_aem-long`,_gcl_gb:'unknown',_gcl_au:`GCL.${now+day}.future`}});
 const age=name=>Number(/Max-Age=(\d+)/.exec(j.writes.filter(x=>x.startsWith(name+'=')).at(-1))[1]);
 assert(age('_gcl_aw')<=day && age('_gcl_aw')>=day-2);assert.equal(age('_fbc'),0);
 assert.equal(age('_gcl_gb'),7776000);assert.equal(age('_gcl_au'),7776000);
});
test('realistic long Meta and Ads values survive validation with safe delimiters only',async()=>{
 const {measurementHostIdentity}=await import('../../src/components/forms/form_measurement_contract.js');
 const {readHostMeasurementIdentity}=await import('../../src/embed/host_measurement.js');
 const click='IwZXh0bgNhZW0'+ 'Ab9-_'.repeat(55)+'_aem_X-y';
 const values={_fbc:'fb.1.1794300000000.'+click,_fbp:'fb.1.1794300000000.1234567890',_gcl_aw:'GCL.1794300000.'+click};
 assert.deepEqual(measurementHostIdentity(values,{marketing:true}),values);
 assert.equal(measurementHostIdentity({_fbc:'a'.repeat(512)},{marketing:true})._fbc.length,512);
 for(const value of ['a'.repeat(513),'x; secret=y','x%20','x=y','x\ny'])assert.deepEqual(measurementHostIdentity({_fbc:value},{marketing:true}),{});
 assert.deepEqual(readHostMeasurementIdentity({cookie:'_ga=GA1.1.123.456; _ga=GA1.1.789.012'},true),{});
});
test('identity-only refresh and unchanged choices are silent in the frame',t=>{
 const f=bootstrap(t),j=cookieJar(f.win);f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:true}});
 const count=f.win.dataLayer.length;
 f.send('identity',{hostIdentity:{_ga:'GA1.1.123.456'}});
 f.send('consent',{hostIdentity:{_ga:'GA1.1.123.789'}});
 assert.equal(f.win.dataLayer.length,count);assert.deepEqual(j.values('_ga'),['GA1.1.123.789']);
 f.send('consent',{consent:false});assert.equal(f.win.dataLayer.filter(x=>x.event==='festapp_consent_update').length,1);
});
test('blocked cookie writes use GA client ID fallback without an undocumented reset on revocation',t=>{
 const f=bootstrap(t);Object.defineProperty(f.win.document,'cookie',{get:()=>'',set:()=>{}});
 f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:true},hostIdentity:{_ga:'GA1.2.123.456'}});
 const entries=f.win.dataLayer,index=entries.findIndex(x=>x[0]==='set'&&x[1]?.client_id==='123.456');
 assert.ok(index>=0 && index<entries.findIndex(x=>x.event==='gtm.js'));
 f.send('consent',{consent:false});assert.equal(entries.filter(x=>x[0]==='set'&&Object.hasOwn(x[1],'client_id')).length,1);
});
for(const embedded of [true,false])test('linker signals reach only direct runtime URLs, never event context; embedded='+embedded,t=>{
 const f=bootstrap(t);f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:embedded,_gl:'1*abc._-1',gtm_debug:'x',gclid:'click'}});
 const url=new URL(f.win.location.href);assert.equal(url.searchParams.get('_gl'),embedded?null:'1*abc._-1');assert.equal(url.searchParams.get('gtm_debug'),embedded?null:'x');
 assert.equal(url.searchParams.get('gclid'),'click');assert.doesNotMatch(JSON.stringify(f.win.dataLayer),/_gl|gtm_debug/);
});
for(const embedded of [true,false])test('router and runtime preserve direct-only linker signals; embedded='+embedded,t=>{
 const f=fixture(t,embedded),sent=[];const url=new URL(parent+'/form/summer?_gl=1*safe&gtm_debug=x&gclid=click'+(embedded?'&embed=1':''));
 const normalized=publicFormAttributionSearch(url);
 assert.equal(normalized.includes('_gl'),!embedded);
 assert.equal(publicFormAttributionSearch(new URL(parent+'/form/summer?_gl=bad%24&gtm_debug=%00')),'');
 f.dom.window.history.replaceState(null,'',url.pathname+normalized);f.transport.activate(f.grant);
 f.transport.frame.contentWindow.postMessage=data=>sent.push(data);f.message('ready');
 assert.equal(sent[0].context._gl,embedded?undefined:'1*safe');
 assert.equal(sent[0].context.gtm_debug,embedded?undefined:'x');
 assert.doesNotMatch(sent[0].context.page_location,/_gl|gtm_debug/);
});

for(const analytics of [true,false])for(const marketing of [true,false])test('direct linker requires both purposes at both boundaries: '+analytics+','+marketing,t=>{
 const f=bootstrap(t,{analytics,marketing});f.send('init',{context:{page_location:parent+'/form/summer',_gl:'1*abc',gtm_debug:'x'}});
 assert.equal(new URL(f.win.location.href).searchParams.has('_gl'),analytics && marketing);
 f.send('consent',{consent:false});assert.equal(new URL(f.win.location.href).searchParams.has('_gl'),false);
 assert.equal(new URL(f.win.location.href).searchParams.get('gtm_debug'),'x');
 const r=fixture(t,false),sent=[];
 r.dom.window.history.replaceState(null,'','/form/summer?_gl=1*abc&gtm_debug=x');
 r.transport.activate({...r.grant,consent:{analytics,marketing}});r.transport.frame.contentWindow.postMessage=data=>sent.push(data);r.message('ready');
 assert.equal(sent[0].context._gl,analytics && marketing?'1*abc':undefined);
 r.transport.updateConsent(false);assert.equal(sent.at(-1).signals._gl,undefined);
});
test('revocation cleans legacy URL click and linker identifiers',t=>{
 const f=bootstrap(t);f.send('init',{context:{page_location:parent+'/form/summer',gclid:'legacy',_gl:'1*abc',gtm_debug:'x'}});
 f.send('consent',{consent:false});const url=new URL(f.win.location.href);
 assert.equal(url.searchParams.has('gclid'),false);assert.equal(url.searchParams.has('_gl'),false);
});

test('a choice made before ready filters linker from the eventual init message',t=>{
 const f=fixture(t,false),sent=[];f.dom.window.history.replaceState(null,'','/form/summer?_gl=1*abc&gtm_debug=x');
 f.transport.activate({...f.grant,consent:{analytics:true}});f.transport.updateConsent(false);
 f.transport.frame.contentWindow.postMessage=data=>sent.push(data);f.message('ready');
 assert.equal(sent[0].context._gl,undefined);assert.equal(sent[0].context.gtm_debug,'x');
});
test('later grant of both purposes can forward direct linker and revocation removes it',t=>{
 const f=bootstrap(t,false);f.send('init',{context:{page_location:parent+'/form/summer'}});
 f.send('consent',{consent:{analytics:true,marketing:true},signals:{_gl:'1*abc',gtm_debug:'x'}});
 assert.equal(new URL(f.win.location.href).searchParams.get('_gl'),'1*abc');
 f.send('consent',{consent:false,signals:{_gl:'1*abc'}});
 assert.equal(new URL(f.win.location.href).searchParams.has('_gl'),false);
});

test('a different GA cookie prefix for the same client keeps the frame session',t=>{
 const f=bootstrap(t),j=cookieJar(f.win);
 j.seed('_ga','GA1.1.123.456');j.seed('_ga_UNIT','GS2.1.s777$o1');
 f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:true},hostIdentity:{_ga:'GA1.2.123.456'}});
 assert.deepEqual(j.values('_ga_UNIT'),['GS2.1.s777$o1'],'GA1.2 and GA1.1 with the same client ID are one visitor');
});
test('same website client preserves extra GA sessions across refresh and a new frame',t=>{
 for(const existing of [false,true]) {
  const f=bootstrap(t),j=cookieJar(f.win);
  if(existing)j.seed('_ga','GA1.1.123.456');
  j.seed('_ga_UNIT','GS2.1.s777$o1');
  f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:true},hostIdentity:{_ga:'GA1.1.123.456'}});
  f.send('identity',{hostIdentity:{_ga:'GA1.1.123.456'}});
  assert.deepEqual(j.values('_ga_UNIT'),['GS2.1.s777$o1']);
  f.send('identity',{hostIdentity:{_ga:'GA1.1.999.888'}});
  assert.deepEqual(j.values('_ga_UNIT'),[]);
 }
});

test('withdrawal clears advertising storage and every click ID; granting restores URL values',t=>{
 const f=bootstrap(t,false),j=cookieJar(f.win);
 const clicks={gclid:'google',gbraid:'app',wbraid:'web',fbclid:'meta',msclkid:'bing',sznclid:'seznam',ttclid:'tiktok'};
 f.win.localStorage.setItem('_gcl_ls','join-id');f.win.localStorage.setItem('other','keep');
 j.seed('_gcl_dc','id');j.seed('_gcl_gs','id');
 f.send('init',{context:{page_location:parent+'/form/summer',utm_source:'search',...clicks}});
 assert.equal(f.win.localStorage.getItem('_gcl_ls'),null);assert.equal(f.win.localStorage.getItem('other'),'keep');
 assert.deepEqual(j.values('_gcl_dc'),[]);assert.deepEqual(j.values('_gcl_gs'),[]);
 for(const key of Object.keys(clicks))assert.equal(new URL(f.win.location.href).searchParams.has(key),false);
 f.send('consent',{consent:{marketing:true}});
 for(const [key,value] of Object.entries(clicks))assert.equal(new URL(f.win.location.href).searchParams.get(key),value);
 f.win.localStorage.setItem('_gcl_ls','join-id');f.send('consent',{consent:false});
 assert.equal(f.win.localStorage.getItem('_gcl_ls'),null);
 for(const key of Object.keys(clicks))assert.equal(new URL(f.win.location.href).searchParams.has(key),false);
 assert.equal(new URL(f.win.location.href).searchParams.get('utm_source'),'search');
});

test('website identity removes embedded self-referral from event context and frame URL',t=>{
 const f=bootstrap(t);
 f.send('init',{context:{page_location:parent+'/form/summer',form_embedded:true,page_referrer:'https://organizer.example/'},hostIdentity:{_ga:'GA1.1.123.456'}});
 f.send('event',{payload:{event:'page_view'}});
 assert.doesNotMatch(JSON.stringify(f.win.dataLayer),/organizer.example/);
 assert.doesNotMatch(f.win.location.href,/organizer.example/);
});

test('realistic multi-property linker survives routing and init, then leaves the form address',async t=>{
 const {measurementSignals}=await import('../../src/components/forms/form_measurement_contract.js');
 const gl='1*abc123*_ga*MTIzNDU2Nzg5MC4xNzMxMjM0NTY3*_ga_HOSTAAA1*czE3MzEyMzQ1NjckbzEkZzEkdDE3MzEyMzQ2MDckajYwJGwwJGgw*_ga_UNITBBB2*czE3MzEyMzQ1NjckbzIkZzEkdDE3MzEyMzQ2MDckajYwJGwwJGgw*_gcl_aw*'+('R0NMLjE3MzEyMzQ1Njcu'+ 'Q2xpY2tJRA'.repeat(20));
 assert(gl.length>350 && gl.length<500);
 assert.equal(measurementSignals({_gl:gl})._gl,gl);
 assert.equal(measurementSignals({_gl:'x'.repeat(2048)})._gl.length,2048);
 for(const bad of ['x'.repeat(2049),'bad%20value','bad/value','bad$value'])assert.equal(measurementSignals({_gl:bad})._gl,undefined);
 const f=fixture(t),sent=[];
 const url=new URL(parent+'/form/summer?_gl='+gl+'&gtm_debug=x#order-preview');
 f.dom.window.history.replaceState({keep:true},'',url.pathname+publicFormAttributionSearch(url)+url.hash);
 f.transport.activate(f.grant);f.transport.frame.contentWindow.postMessage=data=>sent.push(data);f.message('ready');
 assert.equal(sent[0].context._gl,gl);assert.equal(new URL(f.dom.window.location.href).searchParams.has('_gl'),false);
 assert.equal(f.dom.window.history.state.keep,true);assert.equal(f.dom.window.location.hash,'#order-preview');
 f.transport.updateConsent(false);f.transport.updateConsent({analytics:true,marketing:true});assert.equal(sent.at(-1).signals._gl,gl);
 const b=bootstrap(t);b.send('init',{context:{page_location:parent+'/form/summer',_gl:gl}});
 assert.equal(new URL(b.win.location.href).searchParams.get('_gl'),gl);
});

test('late website cookie travels through session, bridge, embed measurement and isolated bootstrap silently',async t=>{
 const {FormMeasurementSession}=await import('../../src/components/forms/form_measurement_session.js');
 const {EmbedBridge}=await import('../../src/services/embed_bridge.js');
 const f=fixture(t,true),bridge=new EmbedBridge(f.dom.window),b=bootstrap(t),j=cookieJar(b.win);
 bridge.origin='https://organizer.example';bridge.instance='host-instance';
 Object.defineProperty(f.dom.window.document,'referrer',{value:bridge.origin+'/checkout'});
 bridge.measurement.measurementProtocol=measurementProtocol;bridge.setMeasurementRuntime(f.transport);
 const session=new FormMeasurementSession({win:f.dom.window,model:{link:'summer',data:{}},transport:bridge,consentSource:{connect:(...args)=>bridge.connectConsent(...args)},policySource:async()=>({...policy,approved_hosts:[bridge.origin]}),identitySource:{read:()=> 'anonymous'}});
 t.after(()=>{session.dispose();bridge.measurement.destroy();});
 session.start();await session.refresh();
 const heartbeat=(hostIdentity,consent={analytics:true})=>bridge.measurement.receive({type:'measurement-consent',measurement:{protocol:measurementProtocol,manifest,leaseId:'lease',ttl:60000,consent,hostIdentity}});
 heartbeat({});
 const frame=f.transport.frame;assert(frame);
 frame.contentWindow.postMessage=data=>b.win.dispatchEvent(new b.win.MessageEvent('message',{source:b.win.parent,origin:parent,data}));
 f.message('ready');f.message('ack');
 assert.equal(f.transport.context.page_referrer,undefined);
 assert.doesNotMatch(JSON.stringify(b.win.dataLayer),/organizer.example/);
 assert.doesNotMatch(f.transport.frame.src,/organizer.example/);
 const before=b.win.dataLayer.length;
 heartbeat({_ga:'GA1.1.123.456'});
 assert.deepEqual(j.values('_ga'),['GA1.1.123.456']);assert.equal(f.transport.frame,frame);assert.equal(b.win.dataLayer.length,before);
 heartbeat({},false);heartbeat({_ga:'GA1.1.999.888'},false);assert.deepEqual(j.values('_ga'),[]);
 bridge.measurement.dataLayer=true;bridge.updateIdentity({_ga:'GA1.1.777.888'});assert(!j.values('_ga').includes('GA1.1.777.888'));
});


test('withdrawal deletes tag cookies on the runtime path as well as the root',t=>{
 const f=bootstrap(t);
 for(const name of ['_ga','_ga_UNIT','_gcl_dc','_gcl_gs','_fbp','_fbc'])
  for(const path of ['/','/runtime'])f.win.document.cookie=name+'=value; Path='+path+'; Secure';
 f.win.document.cookie='unrelated=keep; Path=/runtime; Secure';
 f.send('init',{consent:false});
 assert.equal(f.win.document.cookie,'unrelated=keep');
});
