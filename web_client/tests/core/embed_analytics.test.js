import {measurementProtocol, measurementManifest} from '../../src/components/forms/form_measurement_contract.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {EmbedBridge} from '../../src/services/embed_bridge.js';
import {FormDataLayer} from '../../src/components/forms/form_datalayer.js';
import {FormMeasurementSession} from '../../src/components/forms/form_measurement_session.js';
import {policy,settle} from '../support/measurement_fixture.js';
function fixture(t) {
    const dom=new JSDOM('<html lang="cs"><body></body></html>',{url:'https://tickets.test/form/summer?embed=1',pretendToBeVisual:true});
    const sent=[], parent={postMessage:(...args)=>sent.push(args)};
    Object.defineProperty(dom.window,'parent',{value:parent});
    dom.window.ResizeObserver=class {observe(){} disconnect(){}};
    const bridge=new EmbedBridge(dom.window); bridge.start();
    const message=(type,values={})=>dom.window.dispatchEvent(new dom.window.MessageEvent('message',{
        source:parent,origin:'https://host.invalid',data:{namespace:'festapp-embed',protocol:1,instance:'one',type,...values}}));
    message('init',{viewportHeight:600,dataLayer:true,measurementProtocol});
    const consent=()=>message('measurement-consent',{measurement:{protocol:measurementProtocol,
        manifest:measurementManifest(policy,'summer'),leaseId:'lease',ttl:60000,consent:{analytics:true,marketing:true}}});
    t.after(()=>{bridge.destroy();dom.window.close();});
    return {dom,sent,bridge,message,consent};
}
test('no queue or host output exists before a live grant, including legacy opt-in',t=>{
    const {bridge,sent}=fixture(t), before=sent.length;
    for(let i=0;i<100;i++)assert.equal(bridge.track({event:'page_view'}),false);
    assert.equal(bridge.pendingEvents,undefined);assert.equal(sent.length,before);
});
test('host transport validates payload, pins target and carries revision/lease/generation',t=>{
    const {bridge,sent,message,consent}=fixture(t), manifest=measurementManifest(policy,'summer');
    bridge.connectConsent(policy,()=>{}); consent();
    const grant={host:{origin:'https://host.invalid',instance:'one'},manifest,generation:1,leaseId:'lease',selection:'host',consent:{analytics:true,marketing:true},onReady(){}};
    bridge.activate(grant);assert.equal(sent.at(-1)[0].type,'measurement-activate');
    assert.equal(bridge.track({event:'page_view'}),false,'ACK required');
    message('measurement-ack',{measurement:sent.at(-1)[0].measurement});
    assert.equal(bridge.track({event:'page_view',token:'PRIVATE',user_data:{email:'PRIVATE'}}),true);
    assert.deepEqual(sent.at(-1),[{namespace:'festapp-embed',protocol:1,instance:'one',type:'analytics',measurement:{protocol:measurementProtocol,manifest,generation:1,leaseId:'lease'},payload:{event:'page_view'}},'https://host.invalid']);
    assert.equal(bridge.track({event:'purchase'}),false);bridge.stop();assert.equal(bridge.track({event:'page_view'}),false);
});
test('real session activation waits for the host ACK and delivers initial funnel exactly once',async t=>{
    const {dom,bridge,sent,message,consent}=fixture(t);
    const model={link:'summer',data:{analytics:{...policy,approved_hosts:['https://host.invalid']}},visibleFields:[{id:1,type:'product_type',options:[{id:1,title:'Koncert',price:100,currency:'CZK'}]}]};
    let layer,activations=0;
    const session=new FormMeasurementSession({win:dom.window,model,transport:bridge,policySource:async()=>model.data.analytics,
        consentSource:{connect:(policy,notify)=>bridge.connectConsent(policy,notify)},
        identitySource:{read:()=> 'anonymous'},onActive:()=>{activations++;layer.activate({payload:{}});}});
    layer=new FormDataLayer({win:dom.window,model,sink:session});t.after(()=>{session.dispose();layer.dispose();});
    session.start();await settle();consent();await settle();
    assert.equal(session.state,'starting');assert.equal(sent.some(([message])=>message.type==='analytics'),false);
    const activation=sent.findLast(([message])=>message.type==='measurement-activate')[0];
    message('measurement-ack',{measurement:activation.measurement});
    message('measurement-ack',{measurement:activation.measurement});
    assert.equal(activations,1,'onActive announces each usable grant once');
    assert.deepEqual(sent.filter(([message])=>message.type==='analytics').map(([message])=>message.payload.event).filter(Boolean),['page_view','view_item']);
});
