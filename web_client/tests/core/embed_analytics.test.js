import test from 'node:test';
import assert from 'node:assert/strict';
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
