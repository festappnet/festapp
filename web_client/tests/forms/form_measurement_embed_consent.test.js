import test from 'node:test';
import assert from 'node:assert/strict';
import {createEmbedConsentSource} from '../../src/components/forms/form_measurement_embed_consent.js';
const origin='https://host.example';
const policy={website_consent_bindings:[{websiteOrigin:origin}]};
const settle=()=>new Promise(r=>setImmediate(r));
test('managed iframe local save retires import without losing helper renewal; outer disposal retires both',async()=>{
 let disconnected=0, cleaned=0, receive, options, local=false, stopImport, setConsent;
 const bridge={origin,leaseId:'lease',leaseUntil:Date.now()+60000,
  connectConsent(p,fn){receive=fn;return ()=>disconnected++;}};
 const notices=[];
 const source=createEmbedConsentSource({bridge,model:{},loadNotice:async()=>({startMeasurementConsent(input){
  setConsent=input.setConsent;
  options={hasChoice:()=>{if(local)setConsent({analytics:true,marketing:false});return local;},
   accept:v=>{notices.push(v);setConsent(v)},revoke:()=>notices.push('revoke'),settled:()=>notices.push('local')};
  stopImport=input.remoteSource.connect(options);return ()=>cleaned++;
 }})});
 const values=[],stop=source.connect(policy,v=>values.push(v));await settle();
 receive(false);assert.deepEqual(notices,['revoke','local']);
 receive({analytics:true,marketing:true,leaseId:'lease',expiresAt:bridge.leaseUntil});
 assert.equal(values.at(-1).marketing,true);
 local=true;stopImport();assert.equal(disconnected,0);
 bridge.leaseUntil=Date.now()+50000;receive(false);
 assert.deepEqual(values.at(-1),{analytics:true,marketing:false,leaseId:'lease',expiresAt:bridge.leaseUntil});
 stop();assert.equal(disconnected,1);assert.equal(cleaned,1);
});
test('unmanaged hosts, website dataLayer and staff keep their existing adapter',()=>{
 let calls=0;
 const bridge={origin,connectConsent(){calls++;return ()=>{}}};
 const source=createEmbedConsentSource({bridge,loadNotice(){throw Error('unexpected notice')}});
 source.connect({},()=>{});source.connect({...policy,visitor_role:'staff'},()=>{});
 bridge.dataLayer=true;source.connect(policy,()=>{});
 assert.equal(calls,3);
});
test('disposal before lazy notice loading cannot start an import',async()=>{
 let resolve,calls=0;
 const source=createEmbedConsentSource({bridge:{origin},loadNotice:()=>new Promise(r=>resolve=r)});
 const stop=source.connect(policy,()=>{});stop();resolve({startMeasurementConsent:()=>calls++});await settle();assert.equal(calls,0);
});
