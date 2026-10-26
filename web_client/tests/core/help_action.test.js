import { readFileSync } from 'node:fs';
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
import { helpActionIntent, helpActionFromPath, helpActionPath, helpActionFromWebPath, helpActionWebPath, helpActionFlutterPath } from '../../src/services/help_action_routes.js';
register('../css_loader.mjs', import.meta.url);
const dom = new JSDOM('<!doctype html><body><div id="app"><main></main></div></body>', { url: 'https://tenant.invalid/events?help=orders' });
for (const key of ['window','document','HTMLElement','customElements','Event','CustomEvent','DOMParser']) globalThis[key] = key === 'window' ? dom.window : dom.window[key];
globalThis.localStorage = dom.window.localStorage;
after(() => dom.window.close());


test('help links retain only allowlisted intents across web auth and Flutter bootstrap', async () => {
    const { safeAuthReturnPath } = await import('../../src/services/google_auth_service.js');
    for (const intent of ['organization','bank-accounts','forms','seating','tickets','products','orders','report','settings','scanner-settings']) {
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


test('help actions agree across localized generators, web and Flutter destinations',()=>{
    const ui=JSON.parse(readFileSync(new URL('../../../automation/release/help/ui.json',import.meta.url),'utf8'));
    const dart=readFileSync(new URL('../../../lib/services/help_destination.dart',import.meta.url),'utf8');
    const destinations=[...dart.matchAll(/static const (?:sections|organizationSections) = <String, String>\{([\s\S]*?)\n  \};/g)]
        .flatMap(match=>[...match[1].matchAll(/'([a-z-]+)':/g)].map(key=>key[1]));
    destinations.push(dart.match(/static const scannerSettings = '([a-z-]+)'/)[1]);
    const intents=Object.keys(ui.cs.appActions).sort();
    assert.deepEqual(Object.keys(ui.en.appActions).sort(),intents);
    assert.deepEqual(destinations.sort(),intents);
    for(const intent of intents){
        assert.equal(helpActionIntent(intent),intent);
        assert.equal(helpActionFromPath(helpActionPath(intent)),intent);
    }
    for(const path of ['/help-action/orders?next=x','/help-action/orders#x','/help-action/../orders','https://evil.invalid/help-action/orders','//evil.invalid/help-action/orders','/help-action/unknown',null]){
        assert.equal(helpActionFromPath(path),null);
    }
});
