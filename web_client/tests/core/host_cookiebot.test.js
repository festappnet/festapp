import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM,CookieJar} from 'jsdom';
import {readFileSync} from 'node:fs';
import {createCookiebotSource} from '../../src/embed/host_cookiebot.js';
import {consentScope,createConsentSourceRegistry} from '../../src/components/forms/measurement_consent_source.js';
import {cookiebotFixture,cookiebotConfig,consentRevision} from '../support/cookiebot_fixture.js';
const both={analytics:true,marketing:true},none={analytics:false,marketing:false};
const scope=consentScope({organization:1,unit:2,processing_revision:'technical',consent_revision:consentRevision});
const settle=(ms=0)=>new Promise(resolve=>setTimeout(resolve,ms));
function fixture(choice=both,input=cookiebotConfig,options={}) {
 const win=new JSDOM('',{url:cookiebotConfig.origin,runScripts:'outside-only',...options}).window;
 const cmp=cookiebotFixture(win,{choice});
 const source=createCookiebotSource(win,input),registry=createConsentSourceRegistry(),stop=registry.connect(source);
 // Lasting storage mismatches: move the clock past the write-in-progress window.
 const lasting=(ms=1600)=>{const now=win.Date.now.bind(win.Date);win.Date.now=()=>now()+ms};
 return {win,...cmp,source,registry,lasting,read:()=>registry.read(scope),close(){stop();win.close()}};
}
for(const choice of [both,none,{analytics:true,marketing:false},{analytics:false,marketing:true},{preferences:true,...none}])
 test('Cookiebot transfers saved choice '+JSON.stringify(choice),()=>{
  const f=fixture(choice);try{assert.deepEqual(f.read(),{analytics:choice.analytics,marketing:choice.marketing});
   assert.deepEqual(f.registry.read({...scope,processingRevision:'new-runtime'}),f.read());
  }finally{f.close()}
 });
for(const input of ['{',null,{}, {...cookiebotConfig,provider:'other'},
 ...[0,'1',-1].map(organization=>({...cookiebotConfig,organization})),{...cookiebotConfig,unit:0},
 {...cookiebotConfig,consentRevision:'x'},...['',undefined,'bad'].map(cbid=>({...cookiebotConfig,cbid})),
 ...['https://host.example/','http://host.example','https://host.example/path',undefined].map(origin=>({...cookiebotConfig,origin})),
 ...['2026-01-01','2026-02-31T00:00:00.000Z',undefined].map(consentValidFrom=>({...cookiebotConfig,consentValidFrom})),
 ...[0,-1,'100',365*86400+1,1.5,undefined].map(maxAgeSeconds=>({...cookiebotConfig,maxAgeSeconds}))])
 test('invalid Cookiebot config stays configured and denied '+JSON.stringify(input),()=>{
  const f=fixture(both,input);try{assert.equal(f.registry.configured,true);assert.equal(f.read(),null)}finally{f.close()}
 });
const invalid={
 'undecided':f=>f.choose(null),'implied':f=>f.cmp.consent.method='implied','missing method':f=>delete f.cmp.consent.method,
 'ambiguous response':f=>f.cmp.hasResponse='true','missing response':f=>delete f.cmp.hasResponse,
 'contradictory decline':f=>f.cmp.declined=true,'contradictory acceptance':f=>f.cmp.consented=false,
 'nonboolean category':f=>f.cmp.consent.statistics='true','necessary not accepted':f=>f.cmp.consent.necessary=false,
 'unknown regulation':f=>delete f.cmp.regulations,'GDPR not applicable':f=>f.cmp.regulations.gdprApplies=false,
 'CCPA opt-out':f=>f.cmp.regulations.ccpaApplies=true,'unknown LGPD':f=>delete f.cmp.regulations.lgpdApplies,
 'old policy cutoff':f=>{f.cmp.consentUTC=new f.win.Date('2025-01-01');const utc=f.cmp.consentUTC.getTime();f.store({stamp:'old',necessary:true,preferences:false,statistics:true,marketing:true,utc})},
 'future choice':f=>f.cmp.consentUTC=new f.win.Date(f.win.Date.now()+120000),
 'missing date':f=>delete f.cmp.consentUTC,'invalid date':f=>f.cmp.consentUTC=new f.win.Date('invalid'),
 'date string':f=>f.cmp.consentUTC=f.cmp.consentUTC.toISOString(),
 'expired cookie':f=>{f.win.document.cookie='CookieConsent=;max-age=0;path=/';f.lasting()},
 'different CBID':f=>f.script.setAttribute('data-cbid','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
 'missing CBID':f=>f.script.removeAttribute('data-cbid'),
 'duplicate loaders':f=>f.win.document.head.append(f.script.cloneNode(true)),
 'wrong loader origin':f=>f.script.src='https://consent.cookiebot.com.evil.example/uc.js',
 'insecure loader':f=>f.script.src='http://consent.cookiebot.com/uc.js',
 'no loader':f=>f.script.remove(),
 'opt-out account mode':f=>f.cmp.responseMode='optout','implied account mode':f=>f.cmp.responseMode='implied',
 'missing consent ID':f=>delete f.cmp.consentID,'undecided consent ID':f=>{f.cmp.consentID='0';f.cmp.consent.stamp='0'},
 'sentinel consent ID':f=>{f.cmp.consentID='-1';f.cmp.consent.stamp='-1'},
 'persisted record of another choice':f=>{f.store({stamp:'b3RoZXI=',necessary:true,preferences:false,statistics:false,marketing:false,method:'explicit',ver:1,utc:f.cmp.consentUTC.getTime()});f.lasting()},
 'per-service':f=>f.cmp.consent.services={ad:false},
 'ID mismatch':f=>f.cmp.consentID='different', 'stamp mismatch':f=>f.cmp.consent.stamp='different',
 'missing API':f=>delete f.win.Cookiebot,
 'throwing API':f=>Object.defineProperty(f.win,'Cookiebot',{get(){throw Error('broken')}}),
};
for(const [name,change] of Object.entries(invalid))test(name+' returns null',async()=>{
 const f=fixture();try{change(f);await settle();assert.equal(f.read(),null)}finally{f.close()}
});
test('organization, unit, semantic revision and configured origin bind the record',()=>{
 const f=fixture();try{
  for(const mismatch of [{organization:3},{unit:4},{consentRevision:undefined},{consentRevision:'b'.repeat(32)}])assert.equal(f.registry.read({...scope,...mismatch}),null);
 }finally{f.close()}
 const other=fixture(both,{...cookiebotConfig,origin:'https://other.example'});try{assert.equal(other.read(),null)}finally{other.close()}
});
test('expiry is enforced by elapsed age even while cookie and API remain present',()=>{
 const f=fixture();try{f.win.Date.now=()=>f.cmp.consentUTC.getTime()+cookiebotConfig.maxAgeSeconds*1000;assert.equal(f.read(),null)}finally{f.close()}
});
for(const cookie of ['-1','%zz',"{stamp:'-1',necessary:true,preferences:true,statistics:true,marketing:true,utc:1}",
 "{stamp:'x',stamp:'y'}","{stamp:'x',services:{ad:false}}",'{"statistics":true,}',
 "{stamp:(window.executed=true)}"])
 test('unsupported cookie never grants or executes '+cookie,()=>{
  const f=fixture();try{f.win.document.cookie='CookieConsent='+cookie+';path=/';f.lasting();assert.equal(f.read(),null);assert.equal(f.win.executed,undefined)}finally{f.close()}
 });
test('persisted record binds by consent ID only; other cookie fields are not interpreted',()=>{
 const f=fixture();try{
  const stamp=f.cmp.consentID,base={stamp,necessary:true,preferences:false,statistics:true,marketing:true,method:'explicit',ver:2147483647,utc:1,region:'cz'};
  f.store(base);assert.deepEqual(f.read(),both,'ver, utc and region are not policy or time sources');
  f.win.document.cookie='CookieConsent='+encodeURIComponent("{stamp:'"+stamp+"',necessary:true}")+';path=/';assert.deepEqual(f.read(),both,'plain URI encoding');
  for(const cookie of ["{stamp:'"+stamp+"x'}","{xstamp:'"+stamp+"'}","{stamp:'"+stamp+"',stamp:'"+stamp+"'}","{stamp:'"+stamp+"'","stamp:'"+stamp+"'}",
   '{"stamp":"'+stamp+'"}',"{stamp:'"+stamp.slice(1)+"'}"]){
   f.win.document.cookie='CookieConsent='+encodeURIComponent(cookie)+';path=/';f.lasting();assert.equal(f.read(),null,cookie);
  }
 }finally{f.close()}
});
test('renew keeps the saved choice until a new explicit choice replaces it',async()=>{
 const f=fixture(both),seen=[];const stop=f.source.subscribe(()=>seen.push(f.read()));
 try{
  f.renew();await settle();assert.equal(f.cmp.hasResponse,false);assert.deepEqual(f.read(),both);assert.deepEqual(seen,[]);
  f.choose({analytics:true,marketing:false});await settle();assert.deepEqual(seen,[{analytics:true,marketing:false}]);
  f.renew();f.choose(none);await settle();assert.deepEqual(seen.at(-1),none);
 }finally{stop();f.close()}
});
test('ordinary embed without data-type, data-level or blocking attributes transfers',()=>{
 const win=new JSDOM('',{url:cookiebotConfig.origin,runScripts:'outside-only'}).window;
 try{const cmp=cookiebotFixture(win,{choice:both,blocking:null});
  assert.deepEqual([...cmp.script.attributes].map(a=>a.name).sort(),['data-cbid','id','src','type']);
  const registry=createConsentSourceRegistry();registry.connect(createCookiebotSource(win,cookiebotConfig));assert.deepEqual(registry.read(scope),both);
 }finally{win.close()}
});
test('CBID query form, matching attribute and query, and auto/none blocking modes',()=>{
 const f=fixture();try{
  for(const blocking of ['auto','none']){
   f.script.setAttribute('data-blockingmode',blocking);f.script.src='https://consent.cookiebot.com/uc.js?cbid='+cookiebotConfig.cbid;
   assert.deepEqual(f.read(),both);f.script.removeAttribute('data-cbid');assert.deepEqual(f.read(),both);
  }
  f.script.setAttribute('data-cbid','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');assert.equal(f.read(),null);
  f.script.removeAttribute('data-cbid');f.script.src+='&cbid='+cookiebotConfig.cbid;assert.equal(f.read(),null);
 }finally{f.close()}
});
for(const tcf of ['api','IAB','TCF','query'])test('TCF '+tcf+' never grants blanket marketing',()=>{
 const f=fixture();try{
  if(tcf==='api')f.win.__tcfapi=()=>{};
  else if(tcf==='query')f.script.src+='?data-framework=TCF';
  else f.script.setAttribute('data-framework',tcf);
  assert.deepEqual(f.read(),{analytics:true,marketing:false});
 }finally{f.close()}
});
test('event bursts coalesce and unchanged events publish no messages',async()=>{
 const f=fixture(null),seen=[];const stop=f.source.subscribe(()=>seen.push(f.read()));
 try{
  f.choose(both);assert.equal(f.read(),null,'pending CMP transaction');await settle();assert.deepEqual(seen,[both]);
  for(const name of ['CookiebotOnConsentReady','CookiebotOnLoad','CookiebotOnAccept','CookiebotOnDecline','CookiebotOnDialogDisplay'])f.event(name);
  await settle();assert.deepEqual(seen,[both]);
  f.choose(none);f.choose({analytics:true,marketing:false});await settle();
  assert.deepEqual(seen,[both,{analytics:true,marketing:false}]);
 }finally{stop();f.close()}
});
test('poll detects removal and other-tab refusal despite stale API',async()=>{
 for(const otherTab of [false,true]){
  const jar=new CookieJar(),f=fixture(both,cookiebotConfig,{cookieJar:jar});let other;
  const seen=[];const stop=f.source.subscribe(()=>seen.push(f.read()));
  try{
   if(otherTab){other=fixture(null,cookiebotConfig,{cookieJar:jar});other.choose(none)}
   else f.win.document.cookie='CookieConsent=;max-age=0;path=/';
   await settle(1100);assert.deepEqual(seen,[],'write-in-progress window');
   await settle(1100);assert.deepEqual(seen,[null]);assert.equal(f.cmp.hasResponse,true);
  }finally{stop();other?.close();f.close()}
 }
});
test('last unsubscribe removes exactly the CMP listeners and its interval',async()=>{
 const f=fixture(),removed=[],cleared=[];
 const remove=f.win.removeEventListener.bind(f.win),clear=f.win.clearInterval.bind(f.win);
 f.win.removeEventListener=(name,listener)=>{removed.push(name);remove(name,listener)};
 f.win.clearInterval=id=>{cleared.push(id);clear(id)};
 let calls=0;const stop=f.source.subscribe(()=>calls++);stop();
 f.registry.connect({read:()=>null,subscribe:()=>()=>{}});
 try{assert.equal(removed.filter(name=>name.startsWith('Cookiebot')).length,5);assert.equal(cleared.length,1);
  f.choose(none);await settle(1100);assert.equal(calls,0);
 }finally{f.close()}
});
test('generated helper selects Cookiebot and invalid configuration never falls back to GCM',async()=>{
 for(const input of [cookiebotConfig,{...cookiebotConfig,cbid:'invalid'},'{']){
  const win=new JSDOM('',{url:cookiebotConfig.origin,runScripts:'outside-only',pretendToBeVisual:true}).window;
  try{
   cookiebotFixture(win,{choice:both});win.dataLayer=[['consent','default',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'}]];
   const script=win.document.createElement('script');script.src='https://tickets.example/embed.js';
   script.setAttribute('data-festapp-consent',typeof input==='string'?input:JSON.stringify(input));Object.defineProperty(win.document,'currentScript',{value:script});
   win.eval(readFileSync(new URL('../../public/embed.js',import.meta.url),'utf8'));
   let captured;const peer={closed:false,postMessage:data=>{captured=data}};win.open=()=>peer;
   win.document.body.innerHTML='<a target="_blank" data-festapp-consent-link href="https://tickets.example/form/test">Vstupenky</a>';
   win.document.querySelector('a').dispatchEvent(new win.MouseEvent('click',{bubbles:true,cancelable:true}));
   win.dispatchEvent(new win.MessageEvent('message',{origin:'https://tickets.example',source:peer,data:{namespace:'festapp-consent-link',protocol:1,type:'request',nonce:'a'.repeat(36),scope}}));
   assert.equal(captured?.type,input===cookiebotConfig?'response':'end');
   if(input===cookiebotConfig)assert.equal(captured.choice.analytics,true);
  }finally{win.close()}
 }
});

test('configuration is snapshotted and listener failures do not stop other consumers',async()=>{
 const input={...cookiebotConfig},f=fixture(both,input);let calls=0;
 const a=f.source.subscribe(()=>{throw Error('independent consumer')}),b=f.source.subscribe(()=>calls++);
 try{
  input.cbid='invalid';input.consentRevision='b'.repeat(32);assert.deepEqual(f.read(),both);
  f.choose(none);await settle();assert.equal(calls,1);assert.deepEqual(f.read(),none);
 }finally{a();b();f.close()}
});
test('ambiguous duplicate cookies fail closed',()=>{
 const f=fixture();try{
  const original=f.win.document.cookie;
  Object.defineProperty(f.win.document,'cookie',{configurable:true,get:()=>original+'; '+original});f.lasting();assert.equal(f.read(),null);
  delete f.win.document.cookie;assert.deepEqual(f.read(),both);
 }finally{f.close()}
});

test('a new choice written to the cookie before consentID follows is a write in progress',()=>{
 const f=fixture(both);try{
  assert.deepEqual(f.read(),both);
  // Measured order: categories, then cookie with the new stamp, then consentID/consentUTC.
  Object.assign(f.cmp.consent,{statistics:true,marketing:false,preferences:false});
  assert.deepEqual(f.read(),{analytics:true,marketing:false});
  f.store({stamp:'bmV3Y2hvaWNl',necessary:true,preferences:false,statistics:true,marketing:false,method:'explicit',ver:1,utc:f.win.Date.now(),region:'cz'});
  assert.deepEqual(f.read(),{analytics:true,marketing:false},'no transient null');
  f.cmp.consentID=f.cmp.consent.stamp='bmV3Y2hvaWNl';f.cmp.consentUTC=new f.win.Date(f.win.Date.now()+15);
  assert.deepEqual(f.read(),{analytics:true,marketing:false},'consentUTC a few ms ahead');
  f.store({stamp:'b3RoZXI=',necessary:true,preferences:false,statistics:false,marketing:false,method:'explicit',ver:1,utc:1,region:'cz'});
  f.lasting();assert.equal(f.read(),null,'a lasting mismatch is another decision');
 }finally{f.close()}
});
test('a mismatch present before any match never grants',()=>{
 const win=new JSDOM('',{url:cookiebotConfig.origin,runScripts:'outside-only'}).window;
 try{const cmp=cookiebotFixture(win,{choice:both});
  cmp.store({stamp:'b3RoZXI=',necessary:true,preferences:false,statistics:false,marketing:false,method:'explicit',ver:1,utc:1,region:'cz'});
  assert.equal(createCookiebotSource(win,cookiebotConfig).read(scope),null);
 }finally{win.close()}
});
