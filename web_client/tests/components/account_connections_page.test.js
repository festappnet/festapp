import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';
let dom, Page;
before(async () => {
    dom = new JSDOM('<div id="app"></div><div id="form-page-container"></div>', { url: 'https://vstupenky.online/settings/connections' });
    Object.assign(globalThis, { window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements });
    ({ AccountConnectionsPage: Page } = await import('../../src/components/users/account_connections_page.js'));
    const { LocalizationService } = await import('../../src/services/localization_service.js');
    LocalizationService.translations = JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json', import.meta.url)));
});
after(() => dom.window.close());
const connection = { id: 'owned-connection', client: '<img src=x onerror=alert(1)>', expiresAt: '2026-11-01T12:00:00Z',
    access: { type: 'selection', units: [{ unitId: 8, canCreateOccasions: true }], occasionIds: [99] }, permissions: ['festapp:orders:read','festapp:tickets:send'] };
function fixture({ authenticated = true, invoke, googleStatus = async () => ({ enabled: true, linked: true }) } = {}) {
    const calls = [], googleCalls = []; let listener; let unsubscribed = false;
    const client = { auth: { getSession: async () => ({ data: { session: authenticated ? { user: { id: 'verified', email: 'person@example.test' } } : null } }),
        onAuthStateChange: callback => { listener = callback; return { data: { subscription: { unsubscribe() { unsubscribed = true; } } } }; } },
        functions: { invoke: async (name, { body }) => { assert.equal(name, 'mcp-session-exchange'); calls.push(body); return invoke ? invoke(body) : { data: body.operation === 'connections.list' ? { connections: [connection] } : { connectionId: body.connectionId, revoked: true } }; } } };
    const container = document.getElementById('form-page-container');
    const page = new Page(container, { client, google: { identityStatus: googleStatus, start: async intent => { googleCalls.push(intent); } } });
    return { page, container, calls, googleCalls, emit: (event, session) => listener(event, session), unsubscribed: () => unsubscribed };
}
test('account page has independent identity and app sections; revoke requires exact inline confirmation', async () => {
    const f = fixture(); await f.page.init();
    assert.match(f.container.textContent, /Způsoby přihlášení/); assert.match(f.container.textContent, /Připojené aplikace/);
    assert.equal(f.container.querySelector('img'), null);
    assert.match(f.container.textContent, /Pořadatel #8/); assert.match(f.container.textContent, /Jednotlivá akce #99/);
    f.container.querySelector('[data-revoke]').click();
    assert.equal(f.calls.length, 1); assert.equal(document.activeElement.hasAttribute('data-confirm-revoke'), true);
    assert.match(f.container.textContent, /Již provedené změny/);
    await f.page.revoke(connection.id);
    assert.deepEqual(f.calls.at(-1), { operation: 'connections.revoke', connectionId: connection.id });
    assert.match(f.container.textContent, /Přístup aplikace byl odebrán/); assert.match(f.container.textContent, /Nemáte žádné aktivní/);
    assert.equal(f.container.querySelector('[data-google-action]').disabled, false); f.page.dispose();
});
test('Google failure does not hide or disable app revocation', async () => {
    const f = fixture({ googleStatus: async () => { throw new Error('unavailable'); } }); await f.page.init();
    assert.equal(f.page.googleState, 'error'); assert.equal(f.page.appsState, 'ready');
    f.container.querySelector('[data-revoke]').click(); await f.page.revoke(connection.id);
    assert.equal(f.page.connections.length, 0); f.page.dispose();
});
test('app failure does not block the existing Google verification flow', async () => {
    const f = fixture({ invoke: async () => { throw new Error('unavailable'); } }); await f.page.init();
    assert.equal(f.page.appsState, 'error'); assert.equal(f.page.googleState, 'ready');
    await f.page.startGoogle(); assert.deepEqual(f.googleCalls, ['unlink']); f.page.dispose();
    const unlinked = fixture({ googleStatus: async () => ({ enabled: true, linked: false }) }); await unlinked.page.init();
    await unlinked.page.startGoogle(); assert.deepEqual(unlinked.googleCalls, ['login']); unlinked.page.dispose();
});
test('logged-out page never reads private connections; signing out clears data immediately', async () => {
    const loggedOut = fixture({ authenticated: false }); await loggedOut.page.init(); assert.deepEqual(loggedOut.calls, []);
    assert.match(loggedOut.container.textContent, /Pro správu propojení se přihlaste/); loggedOut.page.dispose();
    const f = fixture(); await f.page.init(); f.emit('SIGNED_OUT', null);
    assert.equal(f.page.state, 'login'); assert.deepEqual(f.page.connections, []);
    assert.doesNotMatch(f.container.textContent, /owned-connection|Pořadatel #8/); f.page.dispose(); assert.equal(f.unsubscribed(), true);
});
test('late private response cannot overwrite a disposed or signed-out page', async () => {
    let release;
    const f = fixture({ invoke: () => new Promise(resolve => { release = resolve; }) }); const pending = f.page.init();
    await new Promise(r => setImmediate(r)); f.emit('SIGNED_OUT', null);
    const content = f.container.innerHTML; release({ data: { connections: [connection] } }); await pending;
    assert.equal(f.container.innerHTML, content); f.page.dispose();
});
test('failed revocation remains visible and cannot claim success', async () => {
    const f = fixture({ invoke: async body => ({ data: body.operation === 'connections.list' ? { connections: [connection] } : { connectionId: 'wrong', revoked: true } }) });
    await f.page.init(); f.container.querySelector('[data-revoke]').click(); await f.page.revoke(connection.id);
    assert.equal(f.page.connections.length, 1); assert.equal(f.page.notice, null); assert.match(f.container.textContent, /Načtení nebo změna se nepodařila/); f.page.dispose();
});
test('canonical route stays in web client on app tenants and disposes with navigation', async t => {
    const { RouterService } = await import('../../src/services/router_service.js');
    const { SupabaseService } = await import('../../src/services/supabase_service.js');
    const { AppConfig } = await import('../../src/app_config.js');
    const old = AppConfig.isAppSupported; AppConfig.isAppSupported = true; t.after(() => { AppConfig.isAppSupported = old; });
    t.mock.method(SupabaseService, 'getClient', () => ({ auth: { getSession: async () => ({ data: { session: null } }) } }));
    assert.equal(await RouterService.handleInitialLoad(), true); assert.equal(document.getElementById('app').hidden, true);
    const page = RouterService._accountConnectionsPage; const before = page.generation;
    RouterService.pushState('/'); assert(page.generation > before); assert.equal(RouterService._accountConnectionsPage, null);
    window.history.replaceState({}, '', '/settings/connections');
});
