import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);

test('organizer intent uses current rights, existing registration and signed-in admin, preserving auth fragment', async t => {
    const dom = new JSDOM('<!doctype html><div id="app"><main></main></div>', { url: 'https://vstupenky.online/events?create=1&utm_source=organizers#auth-fragment' });
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
    const handoff = t.mock.method(RouterService, 'navigateToFlutterRoute', async () => {});
    assert.equal(await handleOrganizerIntent(), 'catalog');
    assert.match(document.querySelector('[role=status]').textContent, /info@festapp.net/);
    assert.equal(locationHash(), '#auth-fragment');
    assert.equal(window.location.search, '?create=1&utm_source=organizers');
    context = { user_info: { id: 'user', units: [{ id: 27 }] }, organization: { IS_REGISTRATION_ENABLED: true } };
    window.history.replaceState(null, '', '/events?create=1');
    assert.equal(await handleOrganizerIntent(), 'navigated');
    assert.equal(admin.mock.calls.length, 0, 'explicit creation bypasses the generic unit dashboard');
    const login = new URL(new URL(handoff.mock.calls.at(-1).arguments[0], window.location.origin).searchParams.get('redirect'), window.location.origin);
    assert.equal(login.searchParams.get('redirect'), '/organizer-action/create');
    context = { organization: { IS_REGISTRATION_ENABLED: true } };
    window.history.replaceState(null, '', '/events?create=1');
    assert.equal(await handleOrganizerIntent(), 'catalog');
    assert.equal(document.querySelector('login-modal').currentView, 'register');
    document.querySelector('login-modal').remove();
    context = { organization: { IS_REGISTRATION_ENABLED: false } };
    window.history.replaceState(null, '', '/events?login=1&utm_source=header#auth-fragment');
    assert.equal(await handleOrganizerIntent(), 'catalog');
    assert.equal(document.querySelector('login-modal').currentView, 'login', 'existing users can sign in even when registration is disabled');
    assert.equal(window.location.search, '?utm_source=header');
    assert.equal(locationHash(), '#auth-fragment');
    context = { user_info: { id: 'user', units: [{ id: 27 }] } };
    window.history.replaceState(null, '', '/events?login=1');
    assert.equal(await handleOrganizerIntent(), 'navigated');
    assert.deepEqual(admin.mock.calls.at(-1).arguments, [27]);
    AppConfig.webLink = 'https://another.invalid';
    window.history.replaceState(null, '', '/events?create=1');
    assert.equal(await handleOrganizerIntent(), false);
    context = { organization: { IS_REGISTRATION_ENABLED: false } };
    for (const link of ['https://vstupenky.online', 'https://tickets.festapp.net', 'https://festival.invalid']) {
        AppConfig.webLink = link;
        for (const route of ['/login?utm_source=docs#auth-fragment', '/login/', '/#/login?utm_source=help']) {
            document.querySelector('login-modal')?.remove();
            window.history.replaceState(null, '', route);
            assert.equal(await handleOrganizerIntent(), 'catalog', `${link}${route}`);
            assert.equal(document.querySelector('login-modal').currentView, 'login');
            assert.equal(window.location.pathname.startsWith('/login'), true);
            if (route.includes('utm_source')) assert.ok(window.location.search.includes('utm_source='));
        }
    }
    AppConfig.webLink = 'https://vstupenky.online';
    document.querySelector('login-modal')?.remove();
    context = { organization: { IS_REGISTRATION_ENABLED: true } };
    window.history.replaceState(null, '', '/login?create=1');
    assert.equal(await handleOrganizerIntent(), 'catalog');
    assert.equal(document.querySelector('login-modal').currentView, 'register');
    assert.equal(window.location.search, '?create=1', 'reload after registration preserves the create intent');
    context = { user_info: { id: 'new-user', units: [] } };
    assert.equal(await handleOrganizerIntent(), 'navigated');
    assert.ok(handoff.mock.calls.at(-1).arguments[0].startsWith('/flutter?redirect='), 'first-event setup uses the authenticated administration boundary without a /login loop');
    context = { organization: { IS_REGISTRATION_ENABLED: true } };
    document.querySelector('login-modal')?.remove();
    window.history.replaceState(null, '', '/login?redirect=%2Forganizer-action%2Fcreate');
    assert.equal(await handleOrganizerIntent(), 'catalog');
    assert.equal(window.location.search, '?create=1');
    assert.equal(document.querySelector('login-modal').currentView, 'register');
    function locationHash() { return window.location.hash; }
});
