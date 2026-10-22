import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {emptyLayout} from '../helpers/venue_layout_kernel.js';
import {BlueprintCapacityControls} from '../../src/components/blueprint/blueprint_capacity_controls.js';
import {LocalizationService} from '../../src/services/localization_service.js';
import fs from 'node:fs';
const dom = new JSDOM('<body><main></main></body>');
globalThis.document = dom.window.document;
LocalizationService.currentLocale = 'cs';
LocalizationService.translations = JSON.parse(fs.readFileSync(new URL('../../public/assets/translations/cs.json',import.meta.url)));
const id = '10000000-0000-4000-8000-000000000001';
const layout = {...emptyLayout,nodes:[{id,kind:'capacityArea',capacity:100,label:'Místa ke stání',transform:{x:300,y:200,rotation:0},width:250,height:150}]};
const messages={standing:'Standing',removeOne:'Remove one',addOne:'Add one',confirmQuantity:'Confirm',pending:'Loading',quantityRejected:'Rejected',availableCount:'{count} available'};

test('inline quantity preserves explicit confirmation, pending lock, rejection and authoritative limits', async () => {
    let resolve, requested;
    const controls = new BlueprintCapacityControls(document.querySelector('main'),{document:layout,resources:{},messages,capacityPresentation:{[id]:{quantity:2,available:3,selectable:true}},onQuantityRequested:(node,count)=>{requested={node,count};return new Promise(r=>resolve=r);}});
    const entry=controls.entries.get(id);
    assert.equal(entry.count.textContent,'2 místa');
    entry.count.click(); entry.plus.click();
    assert.equal(requested,undefined,'Draft does not change checkout');
    assert.equal(entry.plus.disabled,true,'Availability is the upper bound');
    const operation=controls.confirm(entry);
    assert.deepEqual(requested,{node:id,count:3});
    assert.equal(entry.count.disabled,true); assert.equal(entry.minus.disabled,true); assert.equal(entry.confirm.disabled,true);
    resolve({accepted:false,message:'Capacity changed'}); await operation;
    assert.equal(entry.message.textContent,'Capacity changed'); assert.equal(entry.editing,true);
    controls.update({[id]:{quantity:2,available:2,selectable:true}});
    assert.equal(entry.confirm.disabled,true,'Stale draft cannot be confirmed');
    entry.minus.click();
    const accepted=controls.confirm(entry); resolve({accepted:true}); await accepted;
    assert.equal(entry.count.textContent,'2 místa'); assert.equal(entry.editing,false);
    controls.update({[id]:{quantity:2,available:0,selectable:false,tooltip:'Sold out'}});
    entry.count.click(); entry.minus.click();
    assert.equal(entry.draft,0,'Existing selection can be released even after sale closes');
    assert.equal(entry.confirm.disabled,false); assert.equal(entry.plus.disabled,true);
    controls.dispose(); assert.equal(document.querySelector('.blueprint-capacity-layer'),null);
});

test('keyboard capacity activation is intercepted before generic below-map editor', () => {
    const content=document.querySelector('main');
    const controls=new BlueprintCapacityControls(content,{document:layout,resources:{},messages,capacityPresentation:{[id]:{quantity:0,available:3,selectable:true}}});
    const button=document.createElement('button');button.dataset.nodeId=id;content.append(button);
    let genericCalled=false;button.onclick=()=>{genericCalled=true;};button.click();
    assert.equal(genericCalled,false);assert.equal(controls.entries.get(id).editing,true);
    const event=new dom.window.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true});
    controls.entries.get(id).count.dispatchEvent(event);
    assert.equal(event.defaultPrevented,true);assert.equal(controls.entries.get(id).editing,false);
    controls.dispose();button.remove();
});


test('wheel over a quantity control reaches the map at the original cursor position', () => {
    const content = document.querySelector('main');
    content.innerHTML = '<div class="venue-layout-viewer"><svg></svg></div>';
    const svg = content.querySelector('svg');
    svg.getScreenCTM = () => null;
    let received;
    svg.addEventListener('wheel', event => { received = event; event.preventDefault(); });
    const controls = new BlueprintCapacityControls(content,{document:layout,resources:{},messages,capacityPresentation:{[id]:{quantity:2,available:3,selectable:true}}});
    const event = new dom.window.WheelEvent('wheel',{bubbles:true,cancelable:true,deltaY:120,clientX:100,clientY:200,ctrlKey:true});
    controls.entries.get(id).count.dispatchEvent(event);
    assert.ok(received, 'Map must still receive zoom gestures over controls');
    assert.equal(received.deltaY,120); assert.equal(received.clientX,100); assert.equal(received.clientY,200); assert.equal(received.ctrlKey,true);
    assert.equal(event.defaultPrevented,true);
    controls.dispose(); content.innerHTML = '';
});


test('empty selection offers an action, starts with a draft of one and restores the action after release', async () => {
    const controls = new BlueprintCapacityControls(document.querySelector('main'),{document:layout,resources:{},messages,capacityPresentation:{[id]:{quantity:0,available:3,selectable:true}},onQuantityRequested:async()=>({accepted:true})});
    const entry = controls.entries.get(id);
    assert.equal(entry.count.textContent,'Vybrat počet');
    assert.doesNotMatch(entry.count.getAttribute('aria-label'),/0/);
    entry.count.click();
    assert.equal(entry.count.textContent,'1');
    assert.equal(entry.state.quantity,0,'Opening the editor must not select or buy a ticket');
    await controls.confirm(entry);
    assert.equal(entry.count.textContent,'1 místo');
    entry.count.click(); entry.minus.click();
    await controls.confirm(entry);
    assert.equal(entry.count.textContent,'Vybrat počet');
    assert.equal(entry.group.classList.contains('has-selection'),false);
    controls.dispose();
});
