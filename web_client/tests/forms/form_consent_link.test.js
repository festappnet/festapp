import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {requestLinkedConsent, prepareConsentLink, isConsentLinkOrigin} from '../../src/components/forms/form_consent_link.js';
import {installHostConsentLink} from '../../src/embed/host_consent_link.js';
const gtagCmd=(...args)=>(function(){return arguments;})(...args);
const policy={organization:1,unit:2,processing_revision:'rev',measurement_consent_bridge:true,approved_hosts:['https://host.example']};
function fixture(options={}) {
 const dom=new JSDOM('<a data-festapp-consent-link target="_blank" href="https://tickets.example/form/test">Buy</a>',{url:'https://tickets.example/form/test',...(options.referrer === '' ? {} : {referrer:options.referrer??'https://host.example/event'})});
 const win=dom.window, sent=[],accepted=[];let saved=!!options.saved,timeout;
 win.name=options.legacy?'legacy':'festapp-consent-link-00000000-0000-0000-0000-000000000000';win.opener=options.noOpener?null:{postMessage:(data,origin)=>sent.push({data,origin})};
 win.setTimeout=fn=>{timeout=fn;return 1;};win.clearTimeout=()=>{};
 const peer=win.opener;
 const stop=requestLinkedConsent({win,policy:options.policy??policy,hasChoice:()=>saved,accept:(...args)=>accepted.push(args)});
 const reply=(extra={},source=peer,origin='https://host.example')=>win.dispatchEvent(new win.MessageEvent('message',{source,origin,data:{namespace:'festapp-consent-link',protocol:1,type:'response',nonce:sent[0]?.data.nonce,analytics:true,marketing:false,...extra}}));
 return {win,sent,accepted,reply,stop,save:()=>saved=true,expire:()=>timeout(),close:()=>dom.window.close()};
}
test('form validates origin, source, nonce and booleans; consumes exactly one response',()=>{
 const f=fixture();try {
 assert.equal(f.sent[0].origin,'https://host.example');assert.equal(f.sent[0].data.processing_revision,'rev');
 f.reply({},undefined,'https://evil.example');f.reply({},null);f.reply({nonce:'wrong'});f.reply({analytics:'true'});assert.equal(f.accepted.length,0);
 f.reply();f.reply();assert.equal(f.accepted.length,1);assert.deepEqual(f.accepted[0][0],{analytics:true,marketing:false});assert.equal(f.accepted[0][1].origin,'https://host.example');
 }finally{f.close();}
});
for(const options of [{noOpener:true},{referrer:'https://evil.example'},{saved:true}])test(`form skips unsafe or existing context ${JSON.stringify(options)}`,()=>{const f=fixture(options);assert.equal(f.sent.length,0);f.close();});
for(const action of ['expire','save','stop'])test(`form rejects late response after ${action}`,()=>{const f=fixture();f[action]();f.reply();assert.equal(f.accepted.length,0);f.close();});
function hostFixture() {
 const dom=new JSDOM('<a data-festapp-consent-link target="_blank" href="https://tickets.example/form/test">Buy</a>',{url:'https://host.example'}),win=dom.window,replies=[];
 const child={opener:win,postMessage:(data,origin)=>replies.push({data,origin})};win.open=()=>child;
 const stop=installHostConsentLink(win,'https://tickets.example');
 const click=()=>win.document.querySelector('a').dispatchEvent(new win.MouseEvent('click',{bubbles:true,cancelable:true}));
 const reply=(extra={},source=child,origin='https://tickets.example')=>win.dispatchEvent(new win.MessageEvent('message',{source,origin,data:{namespace:'festapp-consent-link',protocol:1,type:'request',nonce:win.crypto.randomUUID(),...extra}}));
 return {win,child,replies,click,reply,close:()=>{stop();win.close();}};
}
test('host trusts only tracked popup and script origin, sends only choice plus envelope once',()=>{
 const f=hostFixture();try {
 f.win.dataLayer=[gtagCmd('consent','update',{analytics_storage:'granted',ad_storage:'denied'})];
 f.reply();assert.equal(f.replies.length,0);f.click();f.reply({},f.child,'https://evil.example');f.reply({},f.win);f.reply({nonce:'bad'});assert.equal(f.replies.length,0);
 f.reply();f.reply();assert.equal(f.replies.length,1);assert.equal(f.replies[0].origin,'https://tickets.example');assert.deepEqual(Object.keys(f.replies[0].data).sort(),['analytics','marketing','namespace','nonce','protocol','type']);assert.equal(f.replies[0].data.analytics,true);
 }finally{f.close();}
});
test('unknown host state leaves normal choice available',()=>{const f=hostFixture();f.click();f.reply();assert.equal(f.replies[0].data.choice,null);f.close();});
test('import takes only purposes the CMP explicitly updated',()=>{
 for(const [label,setup,expected] of [
  ['unrelated security_storage update',win=>{win.dataLayer=[gtagCmd('consent','default',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'}),gtagCmd('consent','update',{security_storage:'granted'})];},null],
  ['only ads updated, analytics default granted',win=>{win.dataLayer=[gtagCmd('consent','default',{analytics_storage:'granted'}),gtagCmd('consent','update',{ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})];},{analytics:false,marketing:true}],
  ['ICS: analytics default granted, only ad_storage updated',win=>{win.google_tag_data={ics:{entries:{analytics_storage:{default:true},ad_storage:{default:false,update:true}}}};},{analytics:false,marketing:false}],
  ['ICS: all ad types updated',win=>{win.google_tag_data={ics:{entries:{analytics_storage:{default:true},ad_storage:{update:true},ad_user_data:{update:true},ad_personalization:{update:true}}}};},{analytics:false,marketing:true}],
  ['TCF page never imports marketing',win=>{win.__tcfapi=()=>{};win.dataLayer=[gtagCmd('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})];},{analytics:true,marketing:false}],
 ]){const f=hostFixture();try{setup(f.win);f.click();f.reply();
   if(expected===null) assert.equal(f.replies[0].data.choice,null,label);
   else {assert.equal(f.replies.length,1,label);assert.deepEqual({analytics:f.replies[0].data.analytics,marketing:f.replies[0].data.marketing},expected,label);}
 }finally{f.close();}}
});
test('a website default alone is not a choice; an explicit CMP update is',()=>{
 for(const [label,setup,expected] of [
  ['dataLayer default only',win=>{win.dataLayer=[gtagCmd('consent','default',{analytics_storage:'denied',ad_storage:'denied'})];},0],
  ['ICS default only',win=>{win.google_tag_data={ics:{entries:{analytics_storage:{default:false},ad_storage:{default:false}}}};},0],
  ['dataLayer update',win=>{win.dataLayer=[gtagCmd('consent','default',{analytics_storage:'denied'}),gtagCmd('consent','update',{analytics_storage:'denied',ad_storage:'denied'})];},1],
  ['ICS update',win=>{win.google_tag_data={ics:{entries:{analytics_storage:{default:false,update:true},ad_storage:{default:false,update:false}}}};},1],
 ]){const f=hostFixture();try{setup(f.win);f.click();f.reply();assert.equal(f.replies.filter(r=>r.data.choice!==null).length,expected,label);}finally{f.close();}}
});
for(const attrs of ['rel="noopener"','rel="noreferrer"','rel="NoOpener"','rel="NoReferrer"','referrerpolicy="no-referrer"','target="_self"','href="https://evil.example/form/test"'])test(`host preserves native navigation ${attrs}`,()=>{
 const f=hostFixture();let opened=false;f.win.open=()=>{opened=true;return f.child;};const [key,value]=attrs.split('=');f.win.document.querySelector('a').setAttribute(key,value.slice(1,-1));
 // Suppress JSDOM navigation after the bridge has seen the native click.
 f.win.document.addEventListener('click',e=>e.preventDefault());f.click();assert.equal(opened,false);f.close();
});

test('form rejects expired nonce even before the scheduled timer callback',()=>{
 const f=fixture(),now=Date.now;
 try {const start=Date.now();Date.now=()=>start+1501;f.reply();assert.equal(f.accepted.length,0);}finally{Date.now=now;f.close();}
});
test('host rejects an expired tracked window even when its cleanup timer was suspended',()=>{
 const f=hostFixture(),now=Date.now;
 try {
  const start=Date.now();Date.now=()=>start;f.win.dataLayer=[gtagCmd('consent','update',{analytics_storage:'granted'})];f.click();
  Date.now=()=>start+60001;f.reply();assert.equal(f.replies.length,0);
 }finally{Date.now=now;f.close();}
});
test('host accepts tracked window after early opener detachment',()=>{
 const f=hostFixture();try{f.win.dataLayer=[gtagCmd('consent','update',{analytics_storage:'granted'})];f.click();f.child.opener=null;f.reply();assert.equal(f.replies.length,1);}finally{f.close();}
});
test('host falls back to tracked WindowProxy when cross-origin opener read is blocked',()=>{
 const f=hostFixture();try{f.win.dataLayer=[gtagCmd('consent','update',{analytics_storage:'denied',ad_storage:'denied'})];f.click();Object.defineProperty(f.child,'opener',{get(){throw new Error('cross origin');}});f.reply();assert.equal(f.replies.length,1);assert.equal(f.replies[0].data.analytics,false);}finally{f.close();}
});

test('exchange clears opener on success, timeout, local choice, disposal and send failure',()=>{
 for(const action of ['reply','expire','save','stop']) {
  const f=fixture();try {f[action]();if(action==='save')f.reply();assert.equal(f.win.opener,null,action);}finally{f.close();}
 }
 const dom=new JSDOM('',{url:'https://tickets.example',referrer:'https://host.example'});
 dom.window.name='festapp-consent-link-00000000-0000-0000-0000-000000000000';dom.window.opener={postMessage(){throw Error('unavailable');}};
 let settled=0;
 requestLinkedConsent({win:dom.window,policy,hasChoice:()=>false,accept(){},settled:()=>settled++});
 assert.equal(dom.window.opener,null);assert.equal(settled,1);dom.window.close();
});
test('form waits at most 1500 ms and settles once',()=>{
 const dom=new JSDOM('',{url:'https://tickets.example',referrer:'https://host.example'});let delay,finish,count=0;
 dom.window.name='festapp-consent-link-00000000-0000-0000-0000-000000000000';dom.window.opener={postMessage(){}};
 dom.window.setTimeout=(fn,ms)=>{finish=fn;delay=ms;return 1;};dom.window.clearTimeout=()=>{};
 const stop=requestLinkedConsent({win:dom.window,policy,hasChoice:()=>false,accept(){},settled:()=>count++});
 assert.equal(stop.pending,true);assert.equal(delay,1500);finish();stop();assert.equal(count,1);dom.window.close();
});
test('production forms reject HTTP including loopback origins',()=>{
 for(const [origin,expected] of [['http://host.example',0],['http://localhost:8080',0],['http://127.0.0.1:8080',0],['https://host.example',1]]){
  const dom=new JSDOM('',{url:'https://tickets.example',referrer:origin});let count=0;
  dom.window.name='festapp-consent-link-00000000-0000-0000-0000-000000000000';dom.window.opener={postMessage(){count++;}};
  const stop=requestLinkedConsent({win:dom.window,policy:{...policy,approved_hosts:[origin]},hasChoice:()=>false,accept(){}});
  assert.equal(count,expected,origin);stop();dom.window.close();
 }
});
test('host consumes tracked window even when no choice was available',()=>{
 const f=hostFixture();try{f.click();f.reply();f.win.dataLayer=[gtagCmd('consent','update',{analytics_storage:'granted'})];f.reply();assert.equal(f.replies.length,1);assert.equal(f.replies[0].data.choice,null);}finally{f.close();}
});
test('host releases unresponsive windows after deadline',()=>{
 const f=hostFixture();let expire,delay;
 try{f.win.setTimeout=(fn,ms)=>{expire=fn;delay=ms;return 1;};f.click();assert.equal(delay,60000);expire();f.win.dataLayer=[gtagCmd('consent','update',{analytics_storage:'granted'})];f.reply();assert.equal(f.replies.length,0);}finally{f.close();}
});

for (const options of [{saved:true},{referrer:''},{referrer:'https://evil.example'},{policy:{...policy,measurement_consent_bridge:false}},{policy:{...policy,measurement_consent_bridge:undefined}}]) test(`helper detaches immediately when skipping ${JSON.stringify(options)}`,()=>{
 const f=fixture(options);try{assert.equal(f.sent.length,0);assert.equal(f.win.opener,null);assert.ok(!f.stop.pending);}finally{f.close();}
});
test('legacy windows retain opener and never delay notice',()=>{
 const f=fixture({legacy:true});try{assert.equal(f.sent.length,0);assert.ok(f.win.opener);assert.ok(!f.stop.pending);}finally{f.close();}
});
test('document no-referrer policy preserves native navigation',()=>{
 const f=hostFixture();try{const meta=f.win.document.createElement('meta');meta.name='referrer';meta.content='no-referrer';f.win.document.head.append(meta);let opened=false;f.win.open=()=>{opened=true};f.win.document.addEventListener('click',e=>e.preventDefault());f.click();assert.equal(opened,false);}finally{f.close();}
});
test('host names each helper popup with an unpredictable marker',()=>{
 const f=hostFixture();try{let name;f.win.open=(url,target)=>{name=target;return f.child};f.click();assert.match(name,/^festapp-consent-link-[a-f0-9-]{36}$/);}finally{f.close();}
});

test('loopback HTTP origins require a local development context',()=>{
 assert.equal(isConsentLinkOrigin('http://localhost:8080'),false);
 assert.equal(isConsentLinkOrigin('http://localhost:8080',true),true);
 assert.equal(isConsentLinkOrigin('http://host.example',true),false);
});
test('early bootstrap detaches helper independently of policy and CMP',()=>{
 const dom=new JSDOM('',{url:'https://tickets.example/form/test'});try{dom.window.name='festapp-consent-link-00000000-0000-0000-0000-000000000000';dom.window.opener={};prepareConsentLink(dom.window);assert.equal(dom.window.opener,null);}finally{dom.window.close();}
});
test('any explicit referrer policy keeps native navigation',()=>{
 for(const setup of [
  win=>win.document.querySelector('a').setAttribute('referrerpolicy','same-origin'),
  win=>win.document.querySelector('a').setAttribute('referrerpolicy','no-referrer'),
  win=>{const m=win.document.createElement('meta');m.name='Referrer';m.content='same-origin';win.document.head.append(m);},
 ]){const f=hostFixture();let opened=0;f.win.open=()=>{opened++;return f.child;};try{setup(f.win);const ok=f.win.document.querySelector('a').dispatchEvent(new f.win.MouseEvent('click',{bubbles:true,cancelable:true}));assert.equal(opened,0);assert.equal(ok,true,'native navigation is not prevented');}finally{f.close();}}
});
