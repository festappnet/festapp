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
    controls.edit(entry); entry.plus.click();
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
    controls.edit(entry); entry.minus.click();
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


test('standing controls stay hidden until area activation and after confirmation or release', async () => {
    const controls = new BlueprintCapacityControls(document.querySelector('main'),{document:layout,resources:{},messages,capacityPresentation:{[id]:{quantity:0,available:3,selectable:true}},onQuantityRequested:async()=>({accepted:true})});
    const entry = controls.entries.get(id);
    assert.equal(entry.group.hidden,true);
    assert.doesNotMatch(entry.count.getAttribute('aria-label'),/0/);
    controls.edit(entry);
    assert.equal(entry.count.textContent,'1');
    assert.equal(entry.state.quantity,0,'Opening the editor must not select or buy a ticket');
    await controls.confirm(entry);
    assert.equal(entry.count.textContent,'1 místo');
    controls.edit(entry); entry.minus.click();
    await controls.confirm(entry);
    assert.equal(entry.group.hidden,true);
    assert.equal(entry.group.classList.contains('has-selection'),false);
    controls.dispose();
});


test('outside activation dismisses the popover, discards the draft and preserves the outside click', () => {
    const content = document.querySelector('main');
    const area = document.createElement('button'); area.dataset.nodeId=id; content.append(area);
    const outside = document.createElement('button'); document.body.append(outside);
    let requested = false, clicked = false;
    outside.onclick = () => {clicked = true;};
    const controls = new BlueprintCapacityControls(content,{document:layout,resources:{},messages,capacityPresentation:{[id]:{quantity:2,available:5,selectable:true}},onQuantityRequested:()=>{requested=true;}});
    const entry = controls.entries.get(id);
    assert.equal(entry.group.hidden,true);
    area.click();
    assert.equal(entry.group.hidden,false); controls.step(entry,1);
    entry.plus.dispatchEvent(new dom.window.Event('pointerdown',{bubbles:true}));
    assert.equal(entry.editing,true,'Inside interaction keeps the dialog open');
    outside.dispatchEvent(new dom.window.Event('pointerdown',{bubbles:true}));
    assert.equal(entry.group.hidden,true); outside.click();
    assert.equal(clicked,true); assert.equal(requested,false); assert.equal(entry.state.quantity,2);
    area.click();
    assert.equal(entry.draft,2,'Reopening resets an unconfirmed draft');
    entry.count.dispatchEvent(new dom.window.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));
    assert.equal(entry.group.hidden,true); assert.equal(document.activeElement,area);
    area.click(); outside.click();
    assert.equal(entry.group.hidden,true,'Keyboard/outside click without pointerdown also dismisses');
    controls.dispose(); area.remove(); outside.remove();
});

test('dismiss during confirmation stays closed and does not steal outside focus', async () => {
    const outside = document.createElement('button'); document.body.append(outside);
    let resolve;
    const controls = new BlueprintCapacityControls(document.querySelector('main'),{document:layout,resources:{},messages,capacityPresentation:{[id]:{quantity:0,available:3,selectable:true}},onQuantityRequested:()=>new Promise(r=>resolve=r)});
    const entry=controls.entries.get(id); controls.edit(entry);
    const operation=controls.confirm(entry);
    outside.click(); outside.focus();
    assert.equal(entry.group.hidden,true);
    resolve({accepted:true}); await operation;
    assert.equal(entry.group.hidden,true); assert.equal(document.activeElement,outside);
    controls.dispose(); outside.remove();
});
