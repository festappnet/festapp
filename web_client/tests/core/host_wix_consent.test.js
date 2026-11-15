import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {createWixConsentSource} from '../../src/embed/host_wix_consent.js';
import {createManagedConsentSource} from '../../src/embed/host_consent_export.js';
import {consentScope,readConsentSource} from '../../src/components/forms/measurement_consent_source.js';
// Modeled Wix public API. Live host cookie/reset behavior is recorded separately.
const origin='https://website.example';
const config={provider:'wix',organization:1,unit:2,consentRevision:'a'.repeat(32),origin,consentValidFrom:'2026-01-01T00:00:00.000Z',maxAgeSeconds:86400};
const binding={id:'11111111-1111-1111-1111-111111111111',version:7};
const scope=consentScope({organization:1,unit:2,consent_revision:config.consentRevision,processing_revision:'runtime',binding,websiteOrigin:origin});
function fixture(t,changes={}) {
 const win=new JSDOM('',{url:origin}).window;t.after(()=>win.close());
 let record={defaultPolicy:false,createdDate:new win.Date(),policy:{essential:true,functional:false,analytics:true,advertising:true,dataToThirdParty:true},...changes};
 win.consentPolicyManager={getCurrentConsentPolicy:()=>record};
 const exported={schemaVersion:1,serviceOrigin:'https://tickets.example',websiteOrigin:origin,binding,providerConfig:config};
 const source=createManagedConsentSource(win,exported,exported.serviceOrigin);
 return {win,source,read:()=>readConsentSource(source,scope),record,setRecord:v=>record=v};
}
test('native Wix saved choice and refusal use confirmed scope and managed version',t=>{
 const f=fixture(t);assert.deepEqual(f.read(),{analytics:true,marketing:true});
 f.record.policy.analytics=false;f.record.policy.advertising=false;
 assert.deepEqual(f.read(),{analytics:false,marketing:false});
 assert.equal(readConsentSource(f.source,{...scope,binding:{...binding,version:8}}),null);
 assert.equal(readConsentSource(f.source,{...scope,binding:undefined}),null);
 assert.equal(readConsentSource(f.source,{...scope,consentRevision:'b'.repeat(32)}),null);
});
for(const [name,changes] of Object.entries({
 default:{defaultPolicy:true},'missing saved flag':{defaultPolicy:undefined},'missing creation date':{createdDate:undefined},
 'malformed date':{createdDate:'yesterday'},future:{createdDate:new Date(Date.now()+120000)},
 'missing policy':{policy:null},'nonboolean purposes':{policy:{essential:true,functional:false,analytics:'true',advertising:true,dataToThirdParty:true}},
})) test('native Wix '+name+' fails closed',t=>{const f=fixture(t,changes);assert.equal(f.read(),null);});
test('Wix requires third-party permission for marketing and clamps TCF',t=>{
 const f=fixture(t);f.record.policy.dataToThirdParty=false;assert.deepEqual(f.read(),{analytics:true,marketing:false});
 f.record.policy.dataToThirdParty=true;f.win.__tcfapi=()=>{};assert.deepEqual(f.read(),{analytics:true,marketing:false});
});
test('reset, deletion and API loss are reread before every grant, with focus and event notifications',async t=>{
 const f=fixture(t);let notices=0;const stop=f.source.subscribe(()=>notices++);t.after(stop);
 f.setRecord({defaultPolicy:true,policy:f.record.policy});assert.equal(f.read(),null);
 f.win.document.dispatchEvent(new f.win.Event('consentPolicyChanged'));await new Promise(r=>setImmediate(r));assert.equal(notices,1);
 f.setRecord(f.record);f.win.dispatchEvent(new f.win.Event('focus'));assert.equal(notices,2);assert.equal(f.read().analytics,true);
 f.win.consentPolicyManager=undefined;assert.equal(f.read(),null);
});
test('native Wix supports canonical ISO creation timestamp as well as SDK Date',t=>{
 const f=fixture(t,{createdDate:new Date().toISOString()});assert.equal(f.read().analytics,true);
});
test('invalid native mapping cannot echo requested notice revision',t=>{
 const f=fixture(t);const source=createWixConsentSource(f.win,{...config,consentRevision:'invalid'});
 assert.equal(source.read(scope),null);
});

test('Wix accepts provider-only and ignores legacy cutoff/age fields',t=>{
 const f=fixture(t,{createdDate:'2025-01-01T00:00:00.000Z'});
 const {consentValidFrom,maxAgeSeconds,...base}=config;
 for(const extra of [{},{consentValidFrom:'invalid',maxAgeSeconds:0}]) assert.equal(createWixConsentSource(f.win,{...base,...extra}).read().analytics,true);
});
