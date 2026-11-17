import test from 'node:test';
import assert from 'node:assert/strict';
import {createEmbedConsentSource} from '../../src/components/forms/form_measurement_embed_consent.js';

for (const dataLayer of [false, true]) for (const managed of [false, true]) {
 test(`iframe delegates consent and cleanup to the host bridge (dataLayer=${dataLayer}, managed=${managed})`,()=>{
  const origin='https://host.example';
  const policy=managed?{website_consent_bindings:[{websiteOrigin:origin}]}:{};
  let receive, disconnected=0;
  const stop=()=>disconnected++;
  const bridge={origin,dataLayer,connectConsent(actualPolicy,notify){
   assert.equal(this,bridge);
   assert.equal(actualPolicy,policy);
   receive=notify;
   return stop;
  }};
  const values=[],notify=value=>values.push(value);
  const cleanup=createEmbedConsentSource({bridge}).connect(policy,notify);
  assert.equal(receive,notify,'the bridge reports directly without a local-choice override');
  assert.equal(cleanup,stop,'the session owns the bridge lifecycle');
  const accepted={analytics:true,marketing:true,leaseId:'host',expiresAt:Date.now()+60000};
  const declined={...accepted,analytics:false,marketing:false};
  for(const value of [false,accepted,declined,null]){
   receive(value);
   assert.equal(values.at(-1),value,'choices, leases and source failure retain their meaning');
  }
  cleanup();assert.equal(disconnected,1);
 });
}
