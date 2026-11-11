import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {createComplianzSource} from '../../src/embed/host_complianz.js';
import {createConsentSourceRegistry, consentScope} from '../../src/components/forms/measurement_consent_source.js';
import {complianzFixture, complianzConfig, consentRevision} from '../support/complianz_fixture.js';
const both={analytics:true,marketing:true}, none={analytics:false,marketing:false};
const scope=consentScope({organization:1,unit:2,processing_revision:'technical',consent_revision:consentRevision});
const settle=()=>new Promise(resolve=>setTimeout(resolve,0));
function fixture(choice=both, config=complianzConfig) {
 const dom=new JSDOM('',{url:'https://organizer.example'}), win=dom.window;
 const cmp=complianzFixture(win,{choice,prefix:'cmplz_rt_'});
 const source=createComplianzSource(win,config), registry=createConsentSourceRegistry();
 const stop=registry.connect(source);
 return {win,cmp,source,registry,read:()=>registry.read(scope),close(){stop();win.close()}};
}
for(const choice of [both,none,{analytics:true,marketing:false},{analytics:false,marketing:true}])
 test('saved scoped category choice '+JSON.stringify(choice),()=>{
  const f=fixture(choice);try {assert.deepEqual(f.read(),choice);assert.equal(f.registry.read({...scope,processingRevision:'new-build'}).analytics,choice.analytics);}
  finally{f.close()}
 });
const invalid={
 'undecided':f=>f.cmp.choose(null),
 'closed without category decisions':f=>{f.cmp.choose(null);f.cmp.cookie('banner-status','dismissed');f.cmp.cookie('policy_id','42')},
 'old saved CMP policy':f=>f.cmp.cookie('policy_id','41'),
 'changed current CMP policy':f=>f.win.complianz.current_policy_id='43',
 'optout defaults':f=>f.win.complianz.consenttype='optout',
 'other defaults':f=>f.win.complianz.consenttype='other',
 'forced statistics':f=>f.win.complianz.forceEnableStats=1,
 'ambiguous forced statistics flag':f=>f.win.complianz.forceEnableStats='false',
 'per-service scope':f=>f.cmp.cookie('consented_services','{"youtube":false}'),
 'missing API':f=>delete f.win.cmplz_has_consent,
 'broken API':f=>f.win.cmplz_get_cookie=()=>{throw Error('unavailable')},
 'malformed saved policy':f=>f.cmp.cookie('policy_id','42junk'),
 'expired cookie':f=>f.cmp.cookie('statistics',';max-age=0'),
 'malformed category':f=>f.cmp.cookie('statistics','granted'),
};
for(const [name,change] of Object.entries(invalid))test(name+' never grants',async()=>{
 const f=fixture();try {change(f);await settle();assert.equal(f.read(),null);assert.equal(f.registry.configured,true);}finally{f.close()}
});
for(const config of ['{',{}, {...complianzConfig,provider:'other'}, {...complianzConfig,consentRevision:'x'}, {...complianzConfig,policyId:0}])
 test('invalid configuration stays configured and denied '+JSON.stringify(config),()=>{
  const f=fixture(both,config);try{assert.equal(f.read(),null);assert.equal(f.registry.configured,true)}finally{f.close()}
 });
test('exact organization, unit and saved semantic revision are required',()=>{
 const f=fixture();try {
  for(const mismatch of [{organization:3},{unit:4},{consentRevision:'b'.repeat(32)},{consentRevision:undefined}])
   assert.equal(f.registry.read({...scope,...mismatch}),null);
 }finally{f.close()}
});
test('bot/category API cannot grant a denied raw cookie; TCF marketing stays denied',()=>{
 const f=fixture(none);try{
  f.win.cmplz_has_consent=()=>true;assert.deepEqual(f.read(),none);
  f.cmp.cookie('statistics','allow');f.cmp.cookie('marketing','allow');f.win.__tcfapi=()=>{};
  assert.deepEqual(f.read(),{analytics:true,marketing:false});
 }finally{f.close()}
});
test('CMP writes coalesce and publish no intermediate grant on decline or save',async()=>{
 const f=fixture();const seen=[];const stop=f.registry.subscribe(()=>seen.push(f.read()));
 try {
  f.cmp.choose(none);assert.equal(f.read(),null,'incomplete CMP transaction cannot be read');
  await settle();assert.deepEqual(seen,[none]);
  f.cmp.choose({analytics:true,marketing:false});await settle();
  assert.deepEqual(seen,[none,{analytics:true,marketing:false}]);
 }finally{stop();f.close()}
});
test('poll detects expiration and a replaced source retires CMP subscriptions',async()=>{
 const f=fixture();const seen=[];const stop=f.registry.subscribe(()=>seen.push(f.read()));
 try{
  f.cmp.cookie('policy_id',';max-age=0');await new Promise(resolve=>setTimeout(resolve,1100));
  assert.equal(seen.at(-1),null);
  f.registry.connect({read:()=>({processingRevision:'technical',...none}),subscribe:()=>()=>{}});
  const count=seen.length;f.cmp.choose(both);await settle();assert.equal(seen.length,count);
  assert.deepEqual(f.read(),none);
 }finally{stop();f.close()}
});

test('updated peers retain the stricter external processing-revision adapter contract',()=>{
 const registry=createConsentSourceRegistry();
 const stop=registry.connect({read:()=>({processingRevision:'technical',...both}),subscribe:()=>()=>{}});
 try {
  assert.deepEqual(registry.read(scope),both);
  assert.equal(registry.read({...scope,processingRevision:'new-deploy'}),null);
 }finally{stop()}
});
