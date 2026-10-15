import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);

async function setup(t) {
    const dom = new JSDOM('<div id="app" style="display:none"><user-header id="universal-header"></user-header></div><div id="form-page-container"></div>', { url: 'https://example.test/form/event' });
    Object.assign(globalThis, { window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement, CustomEvent: dom.window.CustomEvent });
    t.after(() => dom.window.close());
    const { FormPage } = await import('../../src/components/forms/form_page.js');
    return new FormPage('form-page-container');
}
test('admin offer preview does not request a customer token or show a failed overview', async t => {
    const page = await setup(t);
    page.waitlistScope = { offerId: '62daa12a-4165-4867-b1ee-000f30ea3400', token: null };
    let calls = 0;
    page.waitlistCommands = { overviewAccess: async () => { calls++; throw new Error('INVALID_CAPABILITY'); } };
    await page.attachOverview();
    assert.equal(calls, 0);
    assert.equal(page.host.querySelector('[role=alert]'), null);
});
test('overview exposes the existing site header and returns it when entering a form', async t => {
    const page = await setup(t);
    const header = document.getElementById('universal-header');
    page.setOverviewLayout(true);
    assert.equal(header.parentElement, document.body);
    assert.equal(header.nextElementSibling, page.host);
    assert.ok(page.host.classList.contains('order-overview-page'));
    page.setOverviewLayout(false);
    assert.equal(header.parentElement.id, 'app');
    assert.equal(page.host.classList.contains('order-overview-page'), false);
});
