import test from 'node:test';
import assert from 'node:assert/strict';
import '../helpers/style_imports.js';
import { JSDOM } from 'jsdom';

test('organizer intent uses current rights, existing registration and signed-in admin, preserving auth fragment', async t => {
    const dom = new JSDOM('<!doctype html><div id="app"><main></main></div>', { url: 'https://vstupenky.online/?create=1&utm_source=organizers#auth-fragment' });
    for (const key of ['window', 'document', 'HTMLElement', 'customElements', 'Event', 'CustomEvent', 'DOMParser']) globalThis[key] = key === 'window' ? dom.window : dom.window[key];
    globalThis.localStorage = dom.window.localStorage;
    t.after(() => dom.window.close());
    const { handleOrganizerIntent } = await import('../../src/startup/organizer_intent.js');
    const { RightsService } = await import('../../src/services/rights_service.js');
    const { RouterService } = await import('../../src/services/router_service.js');
    const { AppConfig } = await import('../../src/app_config.js');
    AppConfig.webLink = 'https://vstupenky.online';
    let context = { organization: { IS_REGISTRATION_ENABLED: false } };
    t.mock.method(RightsService, 'updateAppData', async () => { RightsService._context = context; return true; });
    const admin = t.mock.method(RouterService, 'navigateToAdmin', async () => {});
    assert.equal(await handleOrganizerIntent(), 'catalog');
    assert.match(document.querySelector('[role=status]').textContent, /info@festapp.net/);
    assert.equal(locationHash(), '#auth-fragment');
    assert.equal(window.location.search, '?utm_source=organizers');
    context = { user_info: { id: 'user', units: [{ id: 27 }] }, organization: { IS_REGISTRATION_ENABLED: true } };
    window.history.replaceState(null, '', '/?create=1');
    assert.equal(await handleOrganizerIntent(), 'navigated');
    assert.deepEqual(admin.mock.calls[0].arguments, [27]);
    context = { organization: { IS_REGISTRATION_ENABLED: true } };
    window.history.replaceState(null, '', '/?create=1');
    assert.equal(await handleOrganizerIntent(), 'catalog');
    assert.equal(document.querySelector('login-modal').currentView, 'register');
    AppConfig.webLink = 'https://another.invalid';
    window.history.replaceState(null, '', '/?create=1');
    assert.equal(await handleOrganizerIntent(), false);
    function locationHash() { return window.location.hash; }
});
