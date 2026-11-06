import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {FormDataLayer} from '../../src/components/forms/form_datalayer.js';
import {EmbedBridge} from '../../src/services/embed_bridge.js';
function fixture(){const sent=[];return {sent,value:new EmbedBridge({parent:{postMessage:(...a)=>sent.push(a)}})};}
test('no queue exists before initialization',()=>{
 const {value,sent}=fixture();for(let i=0;i<100;i++)value.track({event:'page_view'});
 assert.equal(value.pendingEvents,undefined);assert.deepEqual(sent,[]);
});
test('host opt-in needs no consent; independent whitelist and pinned target remain',()=>{
 const {value,sent}=fixture();Object.assign(value,{origin:'https://host.invalid',instance:'one',dataLayer:true});
 value.track({event:'page_view',token:'private',user_data:{email:'private'}});
 assert.deepEqual(sent,[[{namespace:'festapp-embed',protocol:1,instance:'one',type:'analytics',payload:{event:'page_view'}},'https://host.invalid']]);
 value.track({event:'purchase'});assert.equal(sent.length,1,'invalid payload');value.dataLayer=false;value.track({event:'page_view'});assert.equal(sent.length,1,'no opt-in and no frame');
});

test('host transport notifies view after form registration and never starts the frame',()=>{
 const {value}=fixture();let views=0;
 const calls=[];value.setMeasurementRuntime({setConsent(){},start:()=>calls.push('start'),stop:()=>calls.push('stop'),revokeMeasurement(){}},()=>{views++;return true;});assert.equal(views,0);assert.deepEqual(calls,[],'the transport is unknown before the host answers');
 Object.assign(value,{origin:'https://host.invalid',instance:'one',dataLayer:true});
 value.syncMeasurementRuntime();value.syncMeasurementRuntime();assert.equal(views,1);assert.deepEqual([...new Set(calls)],['stop']);
});

test('the host handshake emits the initial funnel once',()=>{
 const dom=new JSDOM('<html lang="cs"><body></body></html>',{url:'https://tickets.test/form/summer?embed=1'});
 const {value:bridge,sent}=fixture();
 const model={data:{analytics:{enabled:true,organization_allowed:true,runtime_supported:true,eligible:true,valid_for_seconds:60}},visibleFields:[{id:1,type:'product_type',options:[{id:1,title:'Koncert',price:100,currency:'CZK'}]}]};
 const layer=new FormDataLayer({win:dom.window,model,bridge,session:()=>false});
 bridge.setMeasurementRuntime({setConsent(){},stop(){},revokeMeasurement(){}},()=>layer.view());layer.view();assert.equal(sent.length,0);
 Object.assign(bridge,{origin:'https://host.invalid',instance:'one',dataLayer:true});
 bridge.syncMeasurementRuntime();bridge.syncMeasurementRuntime();
 assert.deepEqual(sent.map(([message])=>message.payload.event).filter(Boolean),['page_view','view_item']);
 layer.dispose();dom.window.close();
});
