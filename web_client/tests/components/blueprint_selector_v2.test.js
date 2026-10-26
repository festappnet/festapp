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
