import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
const bootstrap = new JSDOM('<body></body>', { url: 'https://tickets.invalid/' });
globalThis.window = bootstrap.window;
globalThis.document = bootstrap.window.document;
const { BlueprintSelector } = await import('../../src/components/blueprint/blueprint_selector.js');
bootstrap.window.close();
delete globalThis.window;
delete globalThis.document;
import { BlueprintRenderer } from '../../src/components/blueprint/blueprint_renderer.js';
import { DbForms } from '../../src/components/forms/db_forms.js';

function fixture(t) {
    const dom = new JSDOM('<body></body>', { url: 'https://tickets.invalid/form/test' });
    for (const key of ['window', 'document', 'ResizeObserver']) {
        const original = Object.getOwnPropertyDescriptor(globalThis, key);
        globalThis[key] = key === 'window' ? dom.window : key === 'document' ? dom.window.document : class { observe() {} disconnect() {} };
        t.after(() => original ? Object.defineProperty(globalThis, key, original) : delete globalThis[key]);
    }
    t.after(() => dom.window.close());
    t.mock.method(BlueprintRenderer.prototype, 'render', () => {});
    t.mock.method(BlueprintRenderer.prototype, 'destroy', () => {});
    return { selector: new BlueprintSelector(), session: { formModel: { blueprint: 87 } }, dom };
}

test('Escape uses browser Back once and removes its listener after the selector closes', async t => {
    const { selector, session, dom } = fixture(t);
    t.mock.method(DbForms, 'getBlueprint', async () => ({ objects: [], spots: [] }));
    const back = t.mock.method(window.history, 'back', () => {});
    await selector.open(session, null, []);
    const escape = () => document.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key: 'Escape', cancelable: true }));
    assert.equal(escape(), false);
    escape();
    assert.equal(back.mock.callCount(), 1);
    window.dispatchEvent(new dom.window.PopStateEvent('popstate'));
    assert.equal(document.querySelector('.blueprint-modal-container'), null);
    assert.equal(document.body.classList.contains('blueprint-active'), false);
    assert.equal(escape(), true);
    assert.equal(back.mock.callCount(), 1);
});

test('closing while seats load cannot create a renderer after the overlay has gone', async t => {
    const { selector, session, dom } = fixture(t);
    let deliver;
    t.mock.method(DbForms, 'getBlueprint', () => new Promise(resolve => { deliver = resolve; }));
    t.mock.method(window.history, 'back', () => window.dispatchEvent(new dom.window.PopStateEvent('popstate')));
    const pending = selector.open(session, null, []);
    document.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key: 'Escape', cancelable: true }));
    deliver({ objects: [], spots: [] });
    await pending;
    assert.equal(selector.renderer, null);
    assert.equal(document.querySelector('.blueprint-modal-container'), null);
});
