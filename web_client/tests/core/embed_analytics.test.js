import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {EmbedBridge} from '../../src/services/embed_bridge.js';
import {FormDataLayer} from '../../src/components/forms/form_datalayer.js';
import {FormMeasurementSession} from '../../src/components/forms/form_measurement_session.js';
import {measurementManifest} from '../../src/components/forms/form_measurement_contract.js';
import {policy,settle} from '../support/measurement_fixture.js';
function fixture(t){
 const dom=new JSDOM('<html lang="cs"><body></body></html>',{url:'https://tickets.test/form/summer?embed=1',pretendToBeVisual:true});const sent=[];
 Object.defineProperty(dom.window,'parent',{value:{postMessage:(...args)=>sent.push(args)}});
 const bridge=new EmbedBridge(dom.window);t.after(()=>{bridge.destroy();dom.window.close();});return{dom,sent,bridge};
}
test('no queue or host output exists before a live grant, including legacy opt-in',t=>{
 const {bridge,sent}=fixture(t);Object.assign(bridge,{origin:'https://host.invalid',instance:'one',dataLayer:true});
 for(let i=0;i<100;i++)assert.equal(bridge.track({event:'page_view'}),false);
 assert.equal(bridge.pendingEvents,undefined);assert.deepEqual(sent,[]);
});
test('host transport validates payload, pins target and carries revision/lease/generation',t=>{
 const {bridge,sent}=fixture(t);const manifest=measurementManifest(policy,'summer');
 Object.assign(bridge,{origin:'https://host.invalid',instance:'one',dataLayer:true,measurementProtocol:2,leaseId:'lease',leaseUntil:Date.now()+60000,modelPolicyApproved:()=>true});
 const grant={manifest,generation:1,leaseId:'lease',selection:'host',consent:{analytics:true,marketing:true},onReady(){}};
 bridge.start(grant);assert.equal(sent[0][0].type,'measurement-activate');assert.equal(bridge.track({event:'page_view'}),false,'ACK required');
 bridge.hostActive=true;assert.equal(bridge.track({event:'page_view',token:'PRIVATE',user_data:{email:'PRIVATE'}}),true);
 assert.deepEqual(sent.at(-1),[{namespace:'festapp-embed',protocol:1,instance:'one',type:'analytics',measurement:{protocol:2,manifest,generation:1,leaseId:'lease'},payload:{event:'page_view'}},'https://host.invalid']);
 assert.equal(bridge.track({event:'purchase'}),false);bridge.stop();assert.equal(bridge.track({event:'page_view'}),false);
});
test('real session activation waits for the host ACK and delivers initial funnel exactly once',async t=>{
 const {dom,bridge,sent}=fixture(t);const model={link:'summer',data:{analytics:policy},visibleFields:[{id:1,type:'product_type',options:[{id:1,title:'Koncert',price:100,currency:'CZK'}]}]};
 Object.assign(bridge,{origin:'https://host.invalid',instance:'one',dataLayer:true,measurementProtocol:2,leaseId:'lease',leaseUntil:Date.now()+60000,modelPolicyApproved:()=>true});
 let layer,activations=0;const session=new FormMeasurementSession({win:dom.window,model,transport:bridge,policySource:async()=>policy,
  consentSource:{connect(_policy,notify){notify({analytics:true,marketing:true,leaseId:'lease',expiresAt:bridge.leaseUntil});return ()=>{};}},
  identitySource:{read:()=> 'anonymous'},onActive:()=>{activations++;layer.activate({payload:{}});}});
 layer=new FormDataLayer({win:dom.window,model,sink:session});t.after(()=>{session.dispose();layer.dispose();});session.start();await settle();
 assert.equal(session.state,'starting');assert.equal(sent.some(([message])=>message.type==='analytics'),false);
 bridge.hostActive=true;bridge.grant.onReady();bridge.grant.onReady();assert.equal(activations,1,'onActive announces each usable grant once');
 assert.deepEqual(sent.filter(([message])=>message.type==='analytics').map(([message])=>message.payload.event).filter(Boolean),['page_view','view_item']);
});
