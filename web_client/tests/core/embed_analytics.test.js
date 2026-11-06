import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {FormDataLayer} from '../../src/components/forms/form_datalayer.js';
import {EmbedBridge} from '../../src/services/embed_bridge.js';
function fixture(){const sent=[];return {sent,value:new EmbedBridge({parent:{postMessage:(...a)=>sent.push(a)}})};}
test('no queue exists before initialization or purpose-specific consent',()=>{
 const {value,sent}=fixture();for(let i=0;i<100;i++)value.track({event:'page_view'});
 assert.equal(value.pendingEvents,undefined);assert.deepEqual(sent,[]);
 value.origin='https://host.invalid';value.instance='one';value.dataLayer=true;value.track({event:'page_view'});assert.deepEqual(sent,[]);
});
test('lease, opt-in, independent whitelist and pinned target are all required',()=>{
 const {value,sent}=fixture();Object.assign(value,{origin:'https://host.invalid',instance:'one',dataLayer:true,consentId:'lease',consentUntil:Date.now()+60000});
 value.track({event:'page_view',token:'private',user_data:{email:'private'}});
 assert.deepEqual(sent,[[{namespace:'festapp-embed',protocol:1,instance:'one',type:'analytics',consentId:'lease',payload:{event:'page_view'}},'https://host.invalid']]);
 value.track({event:'purchase'});value.dataLayer=false;value.track({event:'page_view'});assert.equal(sent.length,1);
 value.dataLayer=true;value.consentUntil=Date.now()-1;value.track({event:'page_view'});assert.equal(sent.length,1);
 value.consentUntil=Date.now()+60000;value.revokeMeasurement();value.track({event:'page_view'});assert.equal(sent.length,1);
});

test('host dataLayer grant notifies view after form registration',()=>{
 const {value}=fixture();let views=0;
 value.setMeasurementRuntime({setConsent:()=>{}},()=>views++);assert.equal(views,0);
 Object.assign(value,{origin:'https://host.invalid',instance:'one',dataLayer:true,consentId:'lease',consentUntil:Date.now()+60000});
 value.syncMeasurementRuntime();assert.equal(views,1);
 value.revokeMeasurement();value.syncMeasurementRuntime();assert.equal(views,1);
});

test('late host consent emits the initial funnel once and renewal keeps only context',()=>{
 const dom=new JSDOM('<html lang="cs"><body></body></html>',{url:'https://tickets.test/form/summer?embed=1'});
 const {value:bridge,sent}=fixture();
 const model={data:{analytics:{enabled:true,organization_allowed:true,runtime_supported:true,eligible:true,valid_for_seconds:60}},visibleFields:[{id:1,type:'product_type',options:[{id:1,title:'Koncert',price:100,currency:'CZK'}]}]};
 const layer=new FormDataLayer({win:dom.window,model,bridge,session:()=>false});
 bridge.setMeasurementRuntime({setConsent:()=>{}},()=>layer.view());layer.view();assert.equal(sent.length,0);
 Object.assign(bridge,{origin:'https://host.invalid',instance:'one',dataLayer:true,consentId:'lease',consentUntil:Date.now()+60000});
 bridge.syncMeasurementRuntime();bridge.syncMeasurementRuntime();
 assert.deepEqual(sent.map(([message])=>message.payload.event).filter(Boolean),['page_view','view_item']);
 layer.dispose();dom.window.close();
});
