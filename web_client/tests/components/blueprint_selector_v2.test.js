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

test('clicking the table selects and releases its available seats without intercepting individual seats', async t => {
    const tableId = '00000000-0000-4000-8000-000000000101';
    const seatIds = [102, 103, 104].map(n => '00000000-0000-4000-8000-000000000' + n);
    const layout = {...emptyLayout, nodes: [
        {id: tableId, kind: 'table', surface: {type: 'rect'}, width: 100, height: 40,
            transform: {x: 200, y: 200, rotation: 0}},
        ...seatIds.map((id, i) => ({id, kind: 'seat', parentId: tableId, width: 20, height: 20,
            transform: {x: -30 + 30 * i, y: 40, rotation: 0}})),
    ]};
    t.mock.method(DbForms, 'getBlueprint', async () => ({
        layout, products: [{id: 1, price: 380, currency_code: 'CZK'}],
        seatBindings: seatIds.map((nodeId, i) => ({nodeId, groupNodeId: tableId, spotId: i + 1, productId: 1})),
        spots: ['available', 'ordered', 'available'].map((state, i) => ({id: i + 1, state})),
    }));
    const identity = {a: 1, b: 0, c: 0, d: 1, e: 0, f: 0, inverse: () => identity};
    t.mock.method(dom.window.SVGElement.prototype, 'getScreenCTM', () => identity);
    t.mock.method(dom.window.SVGElement.prototype, 'getBoundingClientRect',
        () => ({left: 0, top: 0, right: 600, bottom: 400, width: 600, height: 400}));
    const oldPoint = globalThis.DOMPoint;
    globalThis.DOMPoint = class {
        constructor(x, y) { this.x = x; this.y = y; }
        matrixTransform() { return this; }
    };
    const calls = [];
    const selector = new BlueprintSelector();
    t.after(() => { selector.close?.(); globalThis.DOMPoint = oldPoint; });
    await selector.open({
        formModel: {key: 'form', secret: 'secret', blueprint: 1},
        async toggleSpotUnit(models, selecting) {
            calls.push([models.map(model => model.id), selecting]);
            return {spotIds: models.map(model => model.id)};
        },
    }, null);
    const svg = document.querySelector('.venue-layout-viewer > svg');
    assert.ok(svg);
    svg.setPointerCapture = () => {};
    const click = async (clientX, clientY) => {
        svg.dispatchEvent(new dom.window.MouseEvent('click', {clientX, clientY, bubbles: true, detail: 1}));
        await new Promise(resolve => setImmediate(resolve));
    };
    await click(200, 200);
    assert.deepEqual(calls, [[[1], true], [[3], true]]);
    assert.equal(selector.adapter.selectedSeats.length, 2);
    await click(200, 200);
    assert.deepEqual(calls.slice(2), [[[1], false], [[3], false]]);
    await click(170, 240);
    assert.deepEqual(calls.at(-1), [[1], true]);

    const pointer = (name, clientX) => svg.dispatchEvent(new dom.window.MouseEvent(name, {
        clientX, clientY: 200, bubbles: true,
    }));
    pointer('pointerdown', 200);
    pointer('pointermove', 230);
    pointer('pointermove', 200);
    pointer('pointerup', 200);
    const beforeDrag = calls.length;
    await click(200, 200);
    assert.equal(calls.length, beforeDrag, 'dragging out and back does not select a table');
});
