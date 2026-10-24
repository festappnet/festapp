import assert from 'node:assert/strict';
import test from 'node:test';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);

test('profile menu exposes organization settings only for a confirmed organization admin', async t => {
    const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://vstupenky.online/' });
    Object.assign(global, {
        window: dom.window, document: dom.window.document,
        HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements,
        localStorage: dom.window.localStorage,
    });
    const [{ UserHeader }, { RightsService }, { SupabaseService }, { RouterService },
        { AppConfig }, { GoogleAuthService }, { LocalizationService }] = await Promise.all([
        import('../../src/components/users/user_header.js'),
        import('../../src/services/rights_service.js'),
        import('../../src/services/supabase_service.js'),
        import('../../src/services/router_service.js'),
        import('../../src/app_config.js'),
        import('../../src/services/google_auth_service.js'),
        import('../../src/services/localization_service.js'),
    ]);
    t.after(() => dom.window.close());
    const originalOrganization = AppConfig.organization;
    const originalContext = RightsService._context;
    t.after(() => { AppConfig.organization = originalOrganization; RightsService._context = originalContext; });
    AppConfig.organization = 3;
    t.mock.method(LocalizationService, 'tr', key => key === 'Administration.organizationSettings'
        ? 'Nastavení organizace' : key);
    t.mock.method(GoogleAuthService, 'identityStatus', async () => ({ enabled: false }));
    let response;
    const requests = [];
    t.mock.method(SupabaseService, 'getClient', () => ({ rpc: async (name, params) => {
        requests.push({ name, params });
        return await response;
    } }));
    const destinations = [];
    t.mock.method(RouterService, 'navigateToFlutterRoute', async path => { destinations.push(path); });
    const header = new UserHeader();
    document.body.appendChild(header);
    t.after(() => header.remove());
    const flush = () => new Promise(resolve => setImmediate(resolve));
    const open = () => {
        RightsService._context = { user_info: { id: 'admin-user' }, is_admin: true };
        header.user = RightsService.currentUser;
        header.togglePopover(header);
    };
    for (const [data, error, visible] of [[true, null, true], [false, null, false],
        [null, null, false], [true, { message: 'denied' }, false]]) {
        response = { data, error };
        open();
        await flush();
        const action = document.querySelector('.popover-organization-settings');
        assert.equal(!!action, visible, `role result ${JSON.stringify(response)}`);
        assert.ok(document.querySelector('.popover-logout-row'), 'existing menu actions remain');
        if (visible) {
            assert.equal(action.textContent.includes('Nastavení organizace'), true);
            action.click();
            assert.deepEqual(destinations, ['/organizationEdit/3']);
            assert.equal(document.querySelector('#user-popover-wrapper'), null);
        } else document.querySelector('#user-popover-wrapper').remove();
    }
    assert.deepEqual(requests[0], {
        name: 'check_is_admin_of_organization', params: { organization_id: 3 },
    });
    let complete;
    response = new Promise(resolve => { complete = resolve; });
    open();
    await flush();
    RightsService._context = { user_info: { id: 'another-user' } };
    header.user = RightsService.currentUser;
    complete({ data: true, error: null });
    await flush();
    assert.equal(document.querySelector('.popover-organization-settings'), null,
        'an old identity response cannot add an administrator link');
    document.querySelector('#user-popover-wrapper').remove();

    response = Promise.resolve({ data: true, error: null });
    header.user = null;
    RightsService._context = null;
    const before = requests.length;
    header.togglePopover(header);
    await flush();
    assert.equal(requests.length, before, 'guests do not issue the role RPC');
    assert.equal(document.querySelector('.popover-organization-settings'), null);
});
