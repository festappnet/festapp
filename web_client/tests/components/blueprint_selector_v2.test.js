import assert from 'node:assert/strict';
import test from 'node:test';
import { emptyLayout } from '../helpers/venue_layout_kernel.js';
import { JSDOM } from 'jsdom';
import { DbForms } from '../../src/components/forms/db_forms.js';
const dom = new JSDOM('<html><body><button id="before">Form</button></body></html>', {url: 'http://localhost/form'});
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.CustomEvent = dom.window.CustomEvent;
globalThis.self = globalThis;
dom.window.SVGElement.prototype.getScreenCTM = () => null;
globalThis.ResizeObserver = class { observe() {} disconnect() {} };
const { BlueprintSelector } = await import('../../src/components/blueprint/blueprint_selector.js');

test('V2 selector keeps failed load repairable and disposes the shared viewer', async t => {
    let calls = 0;
    t.mock.method(DbForms, 'getBlueprint', async () => {
        if (++calls === 1) throw new Error('local network unavailable');
        return {layout: emptyLayout, products: [], spots: [], seatBindings: []};
    });
    document.getElementById('before').focus();
    const selector = new BlueprintSelector();
    await selector.open({formModel: {key: 'form',secret: 'secret',blueprint: 1}}, null, []);
    const modal = document.querySelector('[role="dialog"]');
    assert.ok(modal);
    assert.match(modal.textContent, /local network unavailable/);
    assert.equal(modal.querySelector('.btn-submit').disabled, true);
    const retry = modal.querySelector('.blueprint-content button');
    await retry.onclick();
    assert.equal(calls, 2);
    assert.equal(modal.querySelector('.btn-submit').disabled, false, modal.textContent);
    assert.ok(modal.querySelector('.venue-layout-viewer'), modal.textContent);
    const renderer = selector.renderer;
    selector.close();
    assert.equal(renderer.disposed, true);
    assert.equal(document.querySelector('[role="dialog"]'), null);
    assert.equal(document.activeElement.id, 'before');
});

test('shared V2 selector preserves embedded query and restores focus without another scroll', async t => {
    t.mock.method(DbForms, 'getBlueprint', async () => ({layout: emptyLayout, products: [], spots: [], seatBindings: []}));
    window.history.replaceState({}, '', '/form/demo?embed=1&preview=false');
    const steps = [];
    const onStep = event => steps.push(event.detail);
    window.addEventListener('festapp-embed-step', onStep);
    t.after(() => { window.removeEventListener('festapp-embed-step', onStep); window.history.replaceState({}, '', '/form'); });
    document.getElementById('before').focus();
    const selector = new BlueprintSelector();
    await selector.open({formModel: {key: 'form',secret: 'secret',blueprint: 1}}, null, []);
    assert.equal(window.location.search, '?embed=1&preview=false');
    assert.equal(window.location.hash, '#seat-selection');
    assert.ok(document.querySelector('.venue-layout-viewer'));
    selector.close();
    assert.equal(window.location.search, '?embed=1&preview=false');
    assert.equal(document.activeElement.id, 'before');
    assert.equal(steps.length, 1);
});

test('seat and quantity intent notify interaction, but opening and presentation updates do not', async t => {
    t.mock.method(DbForms, 'getBlueprint', async () => ({layout: emptyLayout, products: [], spots: [], seatBindings: []}));
    let interactions = 0;
    const selector = new BlueprintSelector();
    t.after(() => selector.close?.());
    await selector.open({formModel: {key: 'form', secret: 'secret', blueprint: 1}}, null, [], () => interactions++);
    assert.equal(interactions, 0, 'opening and initial reconciliation are silent');
    selector.adapter.onPresentationChanged({});
    selector.adapter.onCapacityChanged({});
    assert.equal(interactions, 0, 'passive reservation refresh is silent');

    // These are the real callbacks supplied to the viewer and capacity controls.
    const options = selector.capacityControls.options;
    let finishReservation;
    t.mock.method(selector.adapter, 'requestSelection', () => new Promise(resolve => {finishReservation = resolve;}));
    const pending = options.onSelectionRequested(['seat-1'], true);
    assert.equal(interactions, 1, 'visitor intent counts before reservation completes');
    finishReservation({accepted: false});
    await pending;
    t.mock.method(selector.adapter, 'requestQuantity', async () => ({accepted: true}));
    await options.onQuantityRequested('standing-1', 2);
    assert.equal(interactions, 2);
});
