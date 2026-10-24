import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { BlueprintRenderer } from '../../src/components/blueprint/blueprint_renderer.js';
import { DbForms } from '../../src/components/forms/db_forms.js';

test('Escape closes seat selection after map interaction leaves focus on the document body', async t => {
    const dom = new JSDOM('<body><button id="opener">Select seats</button></body>', {url:'https://tickets.invalid/form/test?embed=1'});
    const keys=['window','document','CustomEvent','ResizeObserver'];
    const originals=Object.fromEntries(keys.map(key=>[key,Object.getOwnPropertyDescriptor(globalThis,key)]));
    Object.assign(globalThis,{window:dom.window,document:dom.window.document,CustomEvent:dom.window.CustomEvent,
        ResizeObserver:class {observe(){} disconnect(){}}});
    t.after(()=>{
        dom.window.close();
        for(const [key,descriptor] of Object.entries(originals)) {
            if(descriptor)Object.defineProperty(globalThis,key,descriptor);else delete globalThis[key];
        }
    });
    const {BlueprintSelector}=await import('../../src/components/blueprint/blueprint_selector.js');
    const {RouterService}=await import('../../src/services/router_service.js');
    t.mock.method(RouterService,'pushOverlayState',()=>{});
    t.mock.method(DbForms,'getBlueprint',async()=>({objects:[]}));
    t.mock.method(BlueprintRenderer.prototype,'render',()=>{});
    t.mock.method(BlueprintRenderer.prototype,'destroy',()=>{});
    window.scrollTo=()=>{};
    const opener=document.getElementById('opener');opener.focus();
    const reveals=[];
    window.addEventListener('festapp-embed-step',event=>reveals.push(event.detail));
    const picker=new BlueprintSelector();
    await picker.open({formModel:{blueprint:1}},null,[]);
    assert.equal(reveals.length,1,'opening brings the map into view');
    assert.equal(document.activeElement.className.includes('blueprint-btn-confirm'),true);
    const back=t.mock.method(window.history,'back',()=>{});
    document.activeElement.blur();
    assert.equal(document.activeElement,document.body);
    const escape=new window.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true});
    document.body.dispatchEvent(escape);
    document.body.dispatchEvent(new window.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true,repeat:true}));
    assert.equal(back.mock.calls.length,1,'Escape must close once even when focus is outside the map container');
    assert.equal(escape.defaultPrevented,true);
    window.dispatchEvent(new window.PopStateEvent('popstate'));
    assert.equal(document.querySelector('.blueprint-modal-container'),null);
    assert.equal(document.activeElement,opener,'keyboard focus returns to the opener');
    assert.equal(reveals.length,1,'closing must not scroll the opener to the top');
    document.body.dispatchEvent(new window.KeyboardEvent('keydown',{key:'Escape',bubbles:true}));
    assert.equal(back.mock.calls.length,1,'the closed picker must release its keyboard listener');
});
