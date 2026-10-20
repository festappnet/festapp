import assert from 'node:assert/strict';
import test from 'node:test';
import { emptyLayout } from '../helpers/venue_layout_kernel.js';
import { JSDOM } from 'jsdom';
import { DbForms } from '../../src/components/forms/db_forms.js';
const dom = new JSDOM('<html><body><button id="before">Form</button></body></html>', {url: 'http://localhost/form'});
globalThis.window = dom.window;
globalThis.document = dom.window.document;
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
