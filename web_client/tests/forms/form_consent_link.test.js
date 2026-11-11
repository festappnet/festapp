import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {requestLinkedConsent} from '../../src/components/forms/form_consent_link.js';
import {consentScope,createConsentSourceRegistry} from '../../src/components/forms/measurement_consent_source.js';
import {installHostConsentLink} from '../../src/embed/host_consent_link.js';
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

test('standalone GCM defaults and updates never create a saved scoped source',()=>{
 const f=hostFixture();try {
  f.dispose();
  f.win.google_tag_data={ics:{entries:{analytics_storage:{default:true,update:true}}}};
  f.win.dataLayer=[(function(){return arguments})('consent','update',{analytics_storage:'granted'})];
  f.click();f.reply();assert.equal(f.replies.at(-1).data.type,'end');
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
