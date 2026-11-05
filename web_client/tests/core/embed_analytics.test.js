import test from 'node:test';
import assert from 'node:assert/strict';
import {EmbedBridge} from '../../src/services/embed_bridge.js';

function bridge() {
    const sent=[];
    return {value:new EmbedBridge({parent:{postMessage:(...args)=>sent.push(args)}}),sent};
}

test('analytics queues only validated payloads, with a bounded pending queue',()=>{
    const {value,sent}=bridge();
    value.track({page_type:'product',language:'cs'});value.track({event:'page_view'});
    value.track({event:'purchase'});value.track('form_view');
    assert.deepEqual(value.pendingEvents,[{page_type:'product',user_type:'b2c',language:'cs'},{event:'page_view'}]);
    assert.deepEqual(sent,[]);
    for(let i=0;i<100;i++)value.track({event:'form_submit_error'});
    assert.equal(value.pendingEvents.length,32);
});

test('analytics sends whitelisted fields to the pinned parent only with opt-in',()=>{
    const {value,sent}=bridge();value.origin='https://host.invalid';value.instance='one';
    value.track({event:'page_view'});assert.deepEqual(sent,[]);
    value.dataLayer=true;
    value.track({event:'page_view',token:'private'});
    value.track({event:'generate_lead',lead_source:'waitlist',currency:'CZK',value:0,user_data:{email:'private'}});
    value.track({event:'form_submit_error',message:'private'});
    value.track({event:'purchase'});
    assert.deepEqual(sent,[{event:'page_view'},{event:'generate_lead',lead_source:'waitlist',currency:'CZK',value:0},{event:'form_submit_error'}].map(payload=>[
        {namespace:'festapp-embed',protocol:1,instance:'one',type:'analytics',payload},'https://host.invalid']));
});

test('child never queues contact before opt-in and strips it again after opt-out',()=>{
    const {value,sent}=bridge();
    const lead={event:'generate_lead',currency:'CZK',value:0,lead_source:'waitlist',user_data:{email:'JAN@EXAMPLE.TEST',token:'private'}};
    value.track(lead);assert.equal(value.pendingEvents[0].user_data,undefined);
    value.origin='https://host.invalid';value.instance='one';value.dataLayer=true;value.dataLayerUserData=true;
    value.track(lead);assert.deepEqual(sent.at(-1)[0].payload.user_data,{email:'jan@example.test'});
    value.dataLayerUserData=false;value.track(lead);assert.equal(sent.at(-1)[0].payload.user_data,undefined);
});
