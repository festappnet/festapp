import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM, CookieJar} from 'jsdom';
import {readFileSync} from 'node:fs';
import {createCookieConsentSource} from '../../src/embed/host_cookieconsent.js';
import {createConsentSourceRegistry,consentScope} from '../../src/components/forms/measurement_consent_source.js';
import {cookieconsentFixture,cookieconsentConfig,consentRevision} from '../support/cookieconsent_fixture.js';
const both={analytics:true,marketing:true},none={analytics:false,marketing:false};
const scope=consentScope({organization:1,unit:2,processing_revision:'technical',consent_revision:consentRevision});
const settle=(ms=0)=>new Promise(resolve=>setTimeout(resolve,ms));
async function fixture(choice=both, input=cookieconsentConfig, config={}, cookieJar) {
 const win=new JSDOM('',{url:'https://organizer.example',runScripts:'outside-only',pretendToBeVisual:true,cookieJar}).window;
 const cmp=await cookieconsentFixture(win,{choice,config});
 const source=createCookieConsentSource(win,input),registry=createConsentSourceRegistry();
 const stop=registry.connect(source);
 return {win,...cmp,source,registry,read:()=>registry.read(scope),close(){stop();win.close()}};
}
for(const choice of [both,none,{analytics:true,marketing:false},{analytics:false,marketing:true}])
 test('real CookieConsent saved choice '+JSON.stringify(choice),async()=>{
  const f=await fixture(choice);try{assert.deepEqual(f.read(),choice);assert.deepEqual(f.registry.read({...scope,processingRevision:'deploy'}),choice)}finally{f.close()}
 });
for(const input of ['{',null,{}, {...cookieconsentConfig,provider:'unknown'}, {...cookieconsentConfig,organization:0},
 {...cookieconsentConfig,unit:'2'}, {...cookieconsentConfig,consentRevision:'x'},
 ...[0,-1,1.5,'42',null].map(revision=>({...cookieconsentConfig,revision})),
 ...[null,{}, {analytics:'same',marketing:'same'}, {analytics:4,marketing:'marketing'}].map(categories=>({...cookieconsentConfig,categories}))])
 test('invalid configuration remains configured and denied '+JSON.stringify(input),async()=>{
  const f=await fixture(both,input);try{assert.equal(f.registry.configured,true);assert.equal(f.read(),null)}finally{f.close()}
 });
for(const [name,config] of Object.entries({
 'opt-out':{mode:'opt-out'},'disabled revisions':{revision:0},'other revision':{revision:43},
 'preselected analytics':{categories:{analytics:{enabled:true},marketing:{}}},
 'mandatory marketing':{categories:{analytics:{},marketing:{readOnly:true}}},
 'missing category':{categories:{analytics:{}}},
 'per-service analytics':{categories:{analytics:{services:{ga:{}}},marketing:{}}},
}))test(name+' returns null',async()=>{
 const f=await fixture(both,cookieconsentConfig,config);try{assert.equal(f.read(),null)}finally{f.close()}
});
test('undecided, closing banner and enabled opt-out defaults cannot establish a choice',async()=>{
 for(const config of [{},{mode:'opt-out',categories:{analytics:{enabled:true},marketing:{enabled:true}}}]){
  const f=await fixture(null,cookieconsentConfig,config);try{f.cmp.hide();assert.equal(f.read(),null)}finally{f.close()}
 }
});
test('exact semantic scope required; caller cannot relabel a stored record',async()=>{
 const f=await fixture();try{
  for(const change of [{organization:3},{unit:4},{consentRevision:'b'.repeat(32)},{consentRevision:undefined}])assert.equal(f.registry.read({...scope,...change}),null);
 }finally{f.close()}
});
for(const [name,change] of Object.entries({
 'stored revision':c=>c.revision=41,'missing categories':c=>delete c.categories,'malformed categories':c=>c.categories=[true],
 'missing ID':c=>delete c.consentId,'missing timestamp':c=>delete c.lastConsentTimestamp,
 'malformed timestamp':c=>c.consentTimestamp='invalid','expired record':c=>c.expirationTime=Date.now()-1,
 'missing expiry':c=>delete c.expirationTime,'malformed expiry':c=>c.expirationTime='tomorrow',
 'stored services':c=>c.services.analytics=['ga'],'missing services':c=>delete c.services,
}))test(name+' fails closed despite cached validConsent',async()=>{
 const f=await fixture();try{const c=f.cmp.getCookie();change(c);f.store(c);assert.equal(f.cmp.validConsent(),true);assert.equal(f.read(),null)}finally{f.close()}
});
test('missing/broken APIs and non-boolean category responses fail closed',async()=>{
 const f=await fixture();try{
  const original=f.win.CookieConsent;
  for(const method of ['validConsent','getCookie','getConfig','acceptedCategory']){
   f.win.CookieConsent={...original,[method]:undefined};assert.equal(f.read(),null);
   f.win.CookieConsent={...original,[method]:()=>{throw Error('broken')}};assert.equal(f.read(),null);
  }
  f.win.CookieConsent={...original,acceptedCategory:()=>1};assert.equal(f.read(),null);
  delete f.win.CookieConsent;assert.equal(f.read(),null);
 }finally{f.close()}
});
test('TCF preserves analytics and denies marketing',async()=>{
 const f=await fixture();try{f.win.__tcfapi=()=>{};assert.deepEqual(f.read(),{analytics:true,marketing:false})}finally{f.close()}
});
test('custom category mapping and localStorage work against real library',async()=>{
 const f=await fixture({statistics:true,ads:false},{...cookieconsentConfig,categories:{analytics:'statistics',marketing:'ads'}},
  {cookie:{useLocalStorage:true,name:'organizer_consent'},categories:{statistics:{},ads:{}}});
 try{assert.deepEqual(f.read(),{analytics:true,marketing:false});const c=f.cmp.getCookie();c.expirationTime=Date.now()-1;f.store(c);assert.equal(f.read(),null)}finally{f.close()}
});
test('real events coalesce, suppress duplicate snapshots and unsubscribe listeners/timer',async()=>{
 const f=await fixture(null);let ticks=0;const seen=[];
 const stop=f.source.subscribe(()=>{ticks++;seen.push(f.read())});
 try{
  f.choose(both);assert.equal(f.read(),null);await settle();assert.deepEqual(seen,[both]);
  for(const event of ['cc:onConsent','cc:onChange','cc:onFirstConsent'])f.event(event);
  await settle();assert.equal(ticks,1);
  f.choose(none);f.choose({analytics:true,marketing:false});await settle();
  assert.deepEqual(seen,[both,{analytics:true,marketing:false}]);
  stop();f.registry.connect({read:()=>null,subscribe:()=>()=>{}});
  f.choose(both);await settle(1100);assert.equal(ticks,2);
 }finally{stop();f.close()}
});
test('poll detects cookie removal, expiry and other-tab changes without CMP events',async()=>{
 for(const kind of ['removed','expired','other-tab']){
  const jar=new CookieJar(),f=await fixture(both,cookieconsentConfig,{},jar);let other;
  const seen=[];const stop=f.source.subscribe(()=>seen.push(f.read()));
  try{
   if(kind==='removed')f.cmp.eraseCookies(f.cmp.getConfig('cookie').name);
   if(kind==='expired'){const c=f.cmp.getCookie();c.expirationTime=Date.now()-1;f.store(c)}
   if(kind==='other-tab'){other=await fixture(null,cookieconsentConfig,{},jar);other.choose(none)}
   await settle(1100);assert.deepEqual(seen,[null]);assert.equal(f.cmp.validConsent(),true);
  }finally{stop();other?.close();f.close()}
 }
});
test('stored choice survives a page load through the real library',async()=>{
 const jar=new CookieJar(),a=await fixture(both,cookieconsentConfig,{},jar);a.close();
 const b=await fixture(null,cookieconsentConfig,{},jar);try{assert.deepEqual(b.read(),both)}finally{b.close()}
});
test('generated helper selects CookieConsent; invalid source never falls back to granted GCM',async()=>{
 for(const input of [cookieconsentConfig,{...cookieconsentConfig,revision:0},'{']){
  const win=new JSDOM('',{url:'https://organizer.example',runScripts:'outside-only',pretendToBeVisual:true}).window;
  try{
   await cookieconsentFixture(win,{choice:both});
   win.dataLayer=[['consent','default',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'}]];
   const script=win.document.createElement('script');script.src='https://tickets.example/embed.js';
   script.setAttribute('data-festapp-consent',typeof input==='string'?input:JSON.stringify(input));
   Object.defineProperty(win.document,'currentScript',{value:script});
   win.eval(readFileSync(new URL('../../public/embed.js',import.meta.url),'utf8'));
   let captured;
   // The real helper opens only a marked link; request carries the same scope.
   const peer={closed:false,postMessage:data=>{captured=data}};
   win.open=()=>peer;
   win.document.body.innerHTML='<a target="_blank" data-festapp-consent-link href="https://tickets.example/form/test">Vstupenky</a>';
   win.document.querySelector('a').dispatchEvent(new win.MouseEvent('click',{bubbles:true,cancelable:true}));
   win.dispatchEvent(new win.MessageEvent('message',{origin:'https://tickets.example',source:peer,data:{namespace:'festapp-consent-link',protocol:1,type:'request',nonce:'a'.repeat(36),scope}}));
   assert.equal(captured?.type,input===cookieconsentConfig?'response':'end');
   if(input===cookieconsentConfig)assert.equal(captured.choice.analytics,true);
  }finally{win.close()}
 }
});
