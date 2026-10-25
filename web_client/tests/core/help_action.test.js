import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
import { helpActionIntent, helpActionFromWebPath, helpActionWebPath, helpActionFlutterPath } from '../../src/services/help_action_routes.js';
register('../css_loader.mjs', import.meta.url);
const dom = new JSDOM('<!doctype html><body><div id="app"><main></main></div></body>', { url: 'https://tenant.invalid/events?help=orders' });
for (const key of ['window','document','HTMLElement','customElements','Event','CustomEvent','DOMParser']) globalThis[key] = key === 'window' ? dom.window : dom.window[key];
globalThis.localStorage = dom.window.localStorage;
after(() => dom.window.close());


test('help links retain only allowlisted intents across web auth and Flutter bootstrap', async () => {
    const { safeAuthReturnPath } = await import('../../src/services/google_auth_service.js');
    for (const intent of ['forms','seating','tickets','products','orders','report','settings','scanner-settings']) {
        const web = helpActionWebPath(intent);
        assert.equal(helpActionFromWebPath(web), intent);
        assert.equal(safeAuthReturnPath(web), web);
        const handoff = new URL(helpActionFlutterPath(intent), 'https://tenant.invalid');
        assert.equal(handoff.pathname, '/flutter');
        const login = new URL(handoff.searchParams.get('redirect'), handoff.origin);
        assert.equal(login.pathname, '/login');
        assert.equal(login.searchParams.get('redirect'), '/help-action/' + intent);
    }
    for (const value of ['unknown','orders?next=x','../orders',null]) assert.equal(helpActionIntent(value), null);
    for (const path of ['/events?help=orders&next=https://evil.invalid','/events?help=orders&help=forms','/events?help=orders#x','https://evil.invalid/events?help=orders','//evil.invalid/events?help=orders','/events?help=unknown']) {
        assert.equal(helpActionFromWebPath(path), null);
        assert.equal(safeAuthReturnPath(path), '/');
    }
});

test('help login uses the standard web modal and hands authenticated users to existing onboarding', async t => {
    const { handleHelpAction } = await import('../../src/startup/help_action.js');
    const { RightsService } = await import('../../src/services/rights_service.js');
    const { RouterService } = await import('../../src/services/router_service.js');
    const { GoogleAuthService } = await import('../../src/services/google_auth_service.js');
    const navigate = t.mock.method(RouterService, 'navigateToFlutterRoute', async () => {});
    t.mock.method(GoogleAuthService, 'capability', async () => false);
    RightsService._context = { organization: { IS_REGISTRATION_ENABLED: true } };
    assert.equal(await handleHelpAction(), 'catalog');
    const modal = document.querySelector('login-modal');
    assert.equal(modal.currentView, 'login');
    assert.ok(modal.authContainer.querySelector('#login-form'));
    assert.equal(navigate.mock.calls.length, 0);
    modal._setView('register');
    assert.equal(window.location.search, '?help=orders');
    modal._setView('login');
    RightsService._context = { user_info: { id: 'registered-user', units: [] } };
    assert.equal(await handleHelpAction(), 'navigated');
    assert.deepEqual(navigate.mock.calls[0].arguments, [helpActionFlutterPath('orders')]);
    window.history.replaceState(null, '', '/events?help=unknown');
    assert.equal(await handleHelpAction(), false);
});
