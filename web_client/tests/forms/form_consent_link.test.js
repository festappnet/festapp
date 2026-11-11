import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {requestLinkedConsent} from '../../src/components/forms/form_consent_link.js';
import {consentScope,createConsentSourceRegistry} from '../../src/components/forms/measurement_consent_source.js';
import {installHostConsentLink} from '../../src/embed/host_consent_link.js';
import {createHostConsentMode} from '../../src/embed/host_consent_mode.js';
const policy={organization:1,unit:2,processing_revision:'rev',measurement_consent_bridge:true,approved_hosts:['https://host.example']};
const scope=consentScope(policy);
function childFixture(options={}) {
 const dom=new JSDOM('',{url:'https://tickets.example/form/test',referrer:options.referrer??'https://host.example/event'}),win=dom.window;
 win.name=options.legacy?'':'festapp-consent-link-00000000-0000-0000-0000-000000000000';
 const sent=[],accepted=[];let revoked=0,settled=0,saved=false;
 const peer={closed:false,postMessage:data=>sent.push(data)};win.opener=peer;
 const stop=requestLinkedConsent({win,policy:options.policy??policy,hasChoice:()=>saved,accept:(...v)=>accepted.push(v),revoke:()=>revoked++,settled:()=>settled++});
 const reply=(extra={},source=peer,origin='https://host.example')=>win.dispatchEvent(new win.MessageEvent('message',{source,origin,data:{...sent[0],type:'response',sequence:1,expiresAt:Date.now()+60000,choice:{analytics:true,marketing:false},...extra}}));
 return {win,sent,accepted,stop,reply,closePeer:()=>peer.closed=true,save:()=>saved=true,get revoked(){return revoked},get settled(){return settled},close(){stop();win.close()}};
}
function hostFixture() {
 const dom=new JSDOM('<a data-festapp-consent-link target="_blank" href="https://tickets.example/form/test">Buy</a>',{url:'https://host.example'}),win=dom.window;
 const replies=[],child={closed:false,postMessage:(data,origin)=>replies.push({data,origin})};win.open=()=>child;
 let value={processingRevision:'rev',analytics:true,marketing:false},notify;
 const registry=createConsentSourceRegistry();
 const dispose=registry.connect({read:s=>s.unit===2?value:null,subscribe:fn=>{notify=fn;return ()=>{notify=null}}});
 const stop=installHostConsentLink(win,'https://tickets.example',registry);
 const click=()=>win.document.querySelector('a').dispatchEvent(new win.MouseEvent('click',{bubbles:true,cancelable:true}));
 const request={namespace:'festapp-consent-link',protocol:1,type:'request',nonce:win.crypto.randomUUID(),scope};
 const reply=(extra={},source=child,origin='https://tickets.example')=>win.dispatchEvent(new win.MessageEvent('message',{source,origin,data:{...request,...extra}}));
 return {win,replies,child,registry,dispose,click,reply,change(v){value=v;notify?.()},close(){stop();win.close()}};
}
test('linked visit validates peer, origin, nonce, scope, sequence and finite TTL',()=>{
 const f=childFixture();try{
 assert.equal(f.win.opener,null);assert.equal(f.stop.pending,true);
 f.reply({},{});f.reply({},undefined,'https://evil.example');f.reply({nonce:'wrong'});f.reply({scope:{...scope,unit:3}});f.reply({sequence:0});f.reply({expiresAt:Infinity});f.reply({expiresAt:Date.now()+600000});
 assert.equal(f.accepted.length,0);f.reply();assert.equal(f.accepted.length,1);assert.equal(f.stop.pending,false);
 assert.equal(f.accepted[0][1].leaseId,f.sent[0].nonce);assert.ok(f.accepted[0][1].expiresAt>Date.now());
 f.reply({choice:{analytics:false,marketing:false}});assert.equal(f.accepted.length,1,'out of order is inert');
 f.reply({sequence:2,choice:{analytics:false,marketing:false}});assert.deepEqual(f.accepted.at(-1)[0],{analytics:false,marketing:false});
 }finally{f.close()}
});
test('source end is terminal and remote updates cannot overwrite a local save',()=>{
 for(const local of [false,true]) {const f=childFixture();try{f.reply();if(local)f.save();f.reply({type:'end',sequence:2});f.reply({sequence:3});assert.equal(f.accepted.length,1);assert.equal(f.revoked,local?0:1);assert.equal(f.settled,1)}finally{f.close()}}
});
test('absolute lease expiry revokes before a suspended timer runs',()=>{
 const f=childFixture(),now=Date.now;try{f.reply({expiresAt:Date.now()+1000});const start=Date.now();Date.now=()=>start+1001;f.reply({sequence:2});assert.equal(f.revoked,1);assert.equal(f.accepted.length,1)}finally{Date.now=now;f.close()}
});
test('host requires saved revision-aware records, streams withdrawal, and ends on disconnect',()=>{
 const f=hostFixture();try{
 f.reply();assert.equal(f.replies.length,0);f.click();f.reply({},f.child,'https://evil.example');f.reply();assert.equal(f.replies.length,1);
 assert.equal(f.replies[0].data.choice.analytics,true);assert.ok(f.replies[0].data.expiresAt<=Date.now()+60000);
 f.change({processingRevision:'rev',analytics:false,marketing:false});assert.equal(f.replies.at(-1).data.choice.analytics,false);assert.equal(f.replies.at(-1).data.sequence,2);
 f.dispose();assert.equal(f.replies.at(-1).data.type,'end');f.reply();assert.equal(f.replies.length,3);
 }finally{f.close()}
});
test('mismatched revision, source replacement and page departure terminate the visit',()=>{
 for(const action of ['revision','replacement','pagehide']) {const f=hostFixture();try{
 f.click();f.reply();
 if(action==='revision')f.change({processingRevision:'other',analytics:true,marketing:true});
 if(action==='replacement')f.registry.connect({read:()=>({processingRevision:'rev',analytics:true,marketing:true}),subscribe:()=>()=>{}});
 if(action==='pagehide')f.win.dispatchEvent(new f.win.Event('pagehide'));
 assert.equal(f.replies.at(-1).data.type,'end',action);
 }finally{f.close()}}
});
test('global source failure remains configured and retired callbacks are inert',()=>{
 const r=createConsentSourceRegistry();let old;const dispose=r.connect({read:()=>({processingRevision:'rev',analytics:true,marketing:true}),subscribe:fn=>{old=fn;return ()=>{}}});
 assert.equal(r.read(scope).analytics,true);r.connect({read:()=>({processingRevision:'rev',analytics:true,marketing:true}),subscribe(){throw Error('broken')}});
 dispose();old();assert.equal(r.configured,true);assert.equal(r.read(scope),null);
});
for(const attrs of ['rel="noopener"','rel="noreferrer"','referrerpolicy="no-referrer"','target="_self"','href="https://evil.example/form/test"'])test('host preserves native navigation '+attrs,()=>{
 const f=hostFixture();try{let opened=false;f.win.open=()=>{opened=true;return f.child};const [key,value]=attrs.split('=');f.win.document.querySelector('a').setAttribute(key,value.slice(1,-1));f.win.document.addEventListener('click',e=>e.preventDefault());f.click();assert.equal(opened,false)}finally{f.close()}
});
for(const options of [{legacy:true},{referrer:'https://evil.example'},{policy:{...policy,measurement_consent_bridge:false}}])test('unapproved links use ordinary local consent '+JSON.stringify(options),()=>{
 const f=childFixture(options);try{assert.equal(f.sent.length,0);assert.equal(f.stop.pending,false)}finally{f.close()}
});
test('initial timeout is bounded and settles once',()=>{
 const f=childFixture(),now=Date.now;try{const start=Date.now();Date.now=()=>start+1501;f.reply();f.stop();assert.equal(f.accepted.length,0);assert.equal(f.settled,1)}finally{Date.now=now;f.close()}
});

test('a delayed unused renewal retains sender expiry instead of gaining a new TTL',()=>{
 const f=childFixture(),now=Date.now;try{
 const start=Date.now();Date.now=()=>start;f.reply();
 Date.now=()=>start+59000;f.reply({sequence:2,expiresAt:start+80000});
 assert.equal(f.accepted.at(-1)[1].expiresAt,start+80000);
 Date.now=()=>start+80001;f.reply({sequence:3,expiresAt:start+100000});
 assert.equal(f.revoked,1);assert.equal(f.accepted.length,2);
 }finally{Date.now=now;f.close()}
});

function gcmHostFixture({tcf=false}={}) {
 const dom=new JSDOM('<a data-festapp-consent-link target="_blank" href="https://tickets.example/form/test">Buy</a>',{url:'https://host.example'}),win=dom.window;
 const replies=[],child={closed:false,postMessage:(data,origin)=>replies.push({data,origin})};win.open=()=>child;
 if(tcf)win.__tcfapi=()=>{};
 const registry=createConsentSourceRegistry(),consentMode=createHostConsentMode(win,{linked:true});
 const stop=installHostConsentLink(win,'https://tickets.example',registry,consentMode);
 const click=()=>win.document.querySelector('a').dispatchEvent(new win.MouseEvent('click',{bubbles:true,cancelable:true}));
 const request={namespace:'festapp-consent-link',protocol:1,type:'request',nonce:win.crypto.randomUUID(),scope};
 const reply=(extra={},source=child)=>win.dispatchEvent(new win.MessageEvent('message',{source,origin:'https://tickets.example',data:{...request,...extra}}));
 const gtag=function(){win.dataLayer.push(arguments)};win.dataLayer=[];
 return {win,replies,child,registry,click,reply,gtag,close(){stop();win.close()}};
}
const all=v=>({analytics_storage:v,ad_storage:v,ad_user_data:v,ad_personalization:v});
const linked=(setup,options)=>{const f=gcmHostFixture(options);try{setup(f);f.click();f.reply();return f.replies[0].data.type==='response'?f.replies[0].data.choice:null}finally{f.close()}};
const icsAll=(v,extra={})=>({analytics_storage:{default:v,...extra},ad_storage:{default:v,...extra},ad_user_data:{default:v,...extra},ad_personalization:{default:v,...extra}});
test('a decided website is read exactly like the embed bridge',()=>{
 const decided=[
  f=>{f.gtag('consent','default',all('denied'));f.gtag('consent','update',all('granted'))},
  f=>{f.gtag('consent','default',all('denied'));f.gtag('consent','update',{...all('granted'),ad_personalization:'denied'})},
  f=>{f.gtag('consent','default',all('denied'));f.gtag('consent','update',all('denied'))},
  f=>{f.win.google_tag_data={ics:{entries:icsAll(true)}}},
  f=>{f.win.google_tag_data={ics:{entries:{...icsAll(false),analytics_storage:{default:true}}}}},
  f=>{f.win.google_tag_data={ics:{entries:icsAll(false,{update:false})}}},
  f=>{f.win.google_tag_data={ics:{entries:{analytics_storage:{default:false,update:true},ad_storage:{default:true}}}}},
 ];
 for(const [i,setup] of decided.entries()) {
  const f=gcmHostFixture();setup(f);const embed=createHostConsentMode(f.win).read();f.close();
  assert.deepEqual(linked(setup),embed,'case '+i);
 }
 assert.deepEqual(linked(decided[3]),{analytics:true,marketing:true},'saved Complianz accept in the default is taken over');
 assert.deepEqual(linked(decided[4]),{analytics:true,marketing:false},'saved statistics-only default takes over analytics');
 assert.deepEqual(linked(decided[1]),{analytics:true,marketing:false},'marketing needs all three ad types');
 assert.deepEqual(linked(decided[2]),{analytics:false,marketing:false},'a dataLayer denial update is taken over without a notice');
 assert.deepEqual(linked(decided[5]),{analytics:false,marketing:false},'a Google tag denial update is taken over without a notice');
});
test('an undecided website keeps the local notice although the embed bridge reads it as denied',()=>{
 const undecided={
  'fresh visit with denied Google tag defaults':f=>{f.win.google_tag_data={ics:{entries:icsAll(false)}}},
  'dataLayer denied default only':f=>f.gtag('consent','default',all('denied')),
  'regional granted default without update':f=>f.gtag('consent','default',{...all('granted'),region:['CZ']}),
  'no Consent Mode':()=>{},
  // A Google tag without Consent Mode creates implicit-only entries (verified in Chromium).
  'Google tag without Consent Mode':f=>{f.win.google_tag_data={ics:{entries:{ad_storage:{implicit:true},analytics_storage:{implicit:true},ad_user_data:{implicit:true},ad_personalization:{implicit:false}},usedDefault:false,usedUpdate:false}}},
  'empty Google consent state':f=>{f.win.google_tag_data={ics:{entries:{}}}},
 };
 for(const [name,setup] of Object.entries(undecided)) assert.equal(linked(setup),null,name);
 const f=gcmHostFixture();f.gtag('consent','default',all('denied'));
 assert.deepEqual(createHostConsentMode(f.win).read(),{analytics:false,marketing:false},'the iframe bridge is unchanged');f.close();
});
test('a website becoming undecided during the visit ends the import; a denial update keeps it',async()=>{
 const f=gcmHostFixture();try{
 f.win.google_tag_data={ics:{entries:icsAll(true)}};f.click();f.reply();assert.deepEqual(f.replies[0].data.choice,{analytics:true,marketing:true});
 f.win.google_tag_data={ics:{entries:icsAll(false,{update:false})}};await new Promise(r=>setTimeout(r,400));
 assert.equal(f.replies.at(-1).data.type,'response');assert.deepEqual(f.replies.at(-1).data.choice,{analytics:false,marketing:false});
 f.win.google_tag_data={ics:{entries:icsAll(false)}};await new Promise(r=>setTimeout(r,400));
 assert.equal(f.replies.at(-1).data.type,'end','a cleared state is undecided');
 }finally{f.close()}
});
test('Consent Mode link streams withdrawal, keeps TCF marketing denied and yields to an explicit source',async()=>{
 const f=gcmHostFixture();try{
 f.gtag('consent','update',all('granted'));f.click();f.reply();assert.deepEqual(f.replies[0].data.choice,{analytics:true,marketing:true});
 f.gtag('consent','update',all('denied'));await new Promise(r=>setTimeout(r,1100));
 assert.deepEqual(f.replies.at(-1).data.choice,{analytics:false,marketing:false});assert.equal(f.replies.at(-1).data.sequence,2);
 f.registry.connect({read:()=>({processingRevision:'rev',analytics:true,marketing:true}),subscribe:()=>()=>{}});
 assert.equal(f.replies.at(-1).data.type,'end','a later explicit source ends the automatic visit');
 }finally{f.close()}
 assert.deepEqual(linked(f=>f.gtag('consent','update',all('granted')),{tcf:true}),{analytics:true,marketing:false});
});
test('a configured explicit source never falls back to Consent Mode',()=>{
 const f=gcmHostFixture();try{
 f.gtag('consent','update',all('granted'));
 const dispose=f.registry.connect({read:()=>null,subscribe:()=>()=>{}});dispose();
 f.click();f.reply();assert.equal(f.replies[0].data.type,'end');
 }finally{f.close()}
});
test('a closed website tab revokes the linked visit without an end message',async()=>{
 const f=childFixture();try{f.reply();assert.equal(f.accepted.length,1);
 f.closePeer();await new Promise(r=>setTimeout(r,1100));assert.equal(f.revoked,1);
 }finally{f.close()}
});

test('a terminal end from an unloading website revokes even without the peer source',()=>{
 const f=childFixture();try{f.reply();assert.equal(f.accepted.length,1);
 f.reply({type:'end',sequence:2,choice:undefined},null);assert.equal(f.revoked,1);
 }finally{f.close()}
 const g=childFixture();try{g.reply();g.reply({sequence:2,choice:{analytics:true,marketing:true}},null);assert.equal(g.accepted.length,1,'a grant still needs the exact peer');
 g.reply({type:'end',sequence:3,nonce:'wrong'},null);assert.equal(g.revoked,0,'end still needs the nonce');
 }finally{g.close()}
});
