import {measurementConsent} from '../../src/components/forms/form_measurement_contract.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {createManagedConsentSource, parseConsentExport} from '../../src/embed/host_consent_export.js';
import {consentScope, readConsentSource as readFullConsentSource} from '../../src/components/forms/measurement_consent_source.js';
import {complianzFixture, complianzConfig} from '../support/complianz_fixture.js';
import {cookiebotFixture, cookiebotConfig} from '../support/cookiebot_fixture.js';
import {cookieconsentFixture, cookieconsentConfig} from '../support/cookieconsent_fixture.js';
import {EmbedMeasurement} from '../../src/embed/measurement.js';
import {measurementManifest} from '../../src/components/forms/form_measurement_contract.js';
const readConsentSource=(...args)=>{const value=readFullConsentSource(...args);return value ? measurementConsent(value) : value;};
const HOST='https://host.example', SERVICE='https://tickets.example';
const binding={id:'11111111-1111-1111-1111-111111111111',version:1};
const policy={organization:1,unit:2,processing_revision:'technical',consent_revision:'a'.repeat(32),
 website_consent_bindings:[{...binding,websiteOrigin:HOST,effective:true}]};
const exported=config=>({schemaVersion:1,serviceOrigin:SERVICE,websiteOrigin:HOST,binding:{...binding},providerConfig:{...config,origin:HOST}});
for(const [name,config,fixture] of [['complianz',complianzConfig,complianzFixture],['cookiebot',cookiebotConfig,cookiebotFixture],['cookieconsent',cookieconsentConfig,cookieconsentFixture]]) {
 for(const choice of [null,{analytics:true,marketing:true},{analytics:false,marketing:false},{analytics:true,marketing:false}])
 test(`managed JSON delegates ${name} ${JSON.stringify(choice)}`,async()=>{
  const win=new JSDOM('',{url:HOST,runScripts:'outside-only',pretendToBeVisual:true}).window;
  try {
   const cmp=await fixture(win,{choice});
   const source=createManagedConsentSource(win,JSON.stringify(exported(config)),SERVICE);
   const scope=consentScope(policy,HOST);
   assert.deepEqual(readConsentSource(source,scope),choice);
   assert.equal(readConsentSource(source,{...scope,binding:{...binding,version:2}}),null,'old export cannot supply new version');
   assert.equal(readConsentSource(source,{...scope,binding:undefined}),null,'managed source cannot speak to old peer');
   assert.equal(readConsentSource(source,{...scope,websiteOrigin:'https://foreign.example'}),null);
   assert.equal(readConsentSource(source,{...scope,consentRevision:'b'.repeat(32)}),null);
   if(choice) {cmp.choose(null);await new Promise(r=>setTimeout(r,0));assert.equal(readConsentSource(source,scope),null,'revocation');}
  } finally {win.close();}
 });
}
for(const change of [{schemaVersion:2},{serviceOrigin:'https://evil.example'},{websiteOrigin:'https://evil.example'},
 {binding:{...binding,version:0}},{binding:undefined},{providerConfig:{}}, {providerConfig:{...complianzConfig,origin:HOST,unit:'2'}}])
 test('invalid export envelope '+JSON.stringify(change),()=>assert.equal(parseConsentExport({...exported(complianzConfig),...change},{serviceOrigin:SERVICE,websiteOrigin:HOST}),null));
test('managed origin cannot fall back to unbound legacy choices or inactive versions',()=>{
 const scope=consentScope(policy,HOST);
 const raw={read:()=>({consentRevision:'a'.repeat(32),analytics:true,marketing:true})};
 assert.equal(readConsentSource(raw,scope),null);
 assert.equal(consentScope({...policy,website_consent_bindings:[{...policy.website_consent_bindings[0],effective:false}]},HOST),null);
 assert.deepEqual(readConsentSource(raw,consentScope(policy,'https://unmanaged.example')),{analytics:true,marketing:true});
});
test('managed category names retain Unicode, spaces and exact UTF-16 bounds',async()=>{
 for(const name of ['statistika návštěv','😀'.repeat(64)]) {
  const win=new JSDOM('',{url:HOST,runScripts:'outside-only',pretendToBeVisual:true}).window;
  try {
   const cmp=await cookieconsentFixture(win,{config:{categories:{[name]:{},marketing:{}}}});cmp.cmp.acceptCategory([name]);
   const config={...cookieconsentConfig,categories:{analytics:name,marketing:'marketing'}};
   assert.deepEqual(readConsentSource(createManagedConsentSource(win,exported(config),SERVICE),consentScope(policy,HOST)),{analytics:true,marketing:false});
   config.categories.analytics='😀'.repeat(65);
   assert.equal(readConsentSource(createManagedConsentSource(win,exported(config),SERVICE),consentScope(policy,HOST)),null);
  }finally{win.close();}
 }
});
test('iframe receiver denies missing/mismatched binding but preserves local checkout lease',()=>{
 const win=new JSDOM('',{url:SERVICE}).window;
 try {
  const p={...policy,measurement_protocol:3,runtime_revision:1,policy_revision:1,profile:'gtm-v1',required_purposes:['analytics','marketing'],form_link:'test'};
  const embed=new EmbedMeasurement(win,{origin:HOST,instance:'test',send(){}});
  embed.measurementProtocol=3;
  const values=[];const cleanup=embed.connectConsent(p,v=>values.push(v));
  const reply=b=>embed.receive({type:'measurement-consent',measurement:{protocol:3,manifest:measurementManifest(p,'test'),leaseId:'lease',ttl:60000,binding:b,consent:{analytics:true,marketing:true}}});
  reply(binding);assert.equal(values.at(-1).analytics,true);
  reply(undefined);assert.equal(values.at(-1),false);assert.equal(embed.leaseId,'lease');
  reply({...binding,version:2});assert.equal(values.at(-1),false);
  embed.dataLayer=true;reply(undefined);assert.equal(values.at(-1).analytics,true,'website dataLayer mode retained');
  cleanup();embed.destroy();
 }finally{win.close();}
});
