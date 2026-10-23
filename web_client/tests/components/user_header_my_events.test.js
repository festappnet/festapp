import assert from 'node:assert/strict';
import test from 'node:test';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';

register('../css_loader.mjs', import.meta.url);

test('ticketing account navigation does not require administration privileges', async t => {
    const dom = new JSDOM('<body></body>', { url: 'https://vstupenky.online/' });
    Object.assign(globalThis, {
        window: dom.window, document: dom.window.document,
        HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements,
    });
    const [{ UserHeader }, { RightsService }, { RouterService }, { AppConfig }] = await Promise.all([
        import('../../src/components/users/user_header.js'),
        import('../../src/services/rights_service.js'),
        import('../../src/services/router_service.js'),
        import('../../src/app_config.js'),
    ]);
    const originalContext = RightsService._context;
    const originalLink = AppConfig.webLink;
    t.after(() => {
        RightsService._context = originalContext;
        AppConfig.webLink = originalLink;
        dom.window.close();
    });
    let navigations = 0;
    t.mock.method(RouterService, 'navigateToAdmin', () => { navigations++; });
    for (const marketing of [false, true]) {
        AppConfig.webLink = 'https://vstupenky.online';
        RightsService._context = {
            user_info: { id: 'signed-in-account', name: 'Test', units: [] },
            capabilities: {},
        };
        const header = new UserHeader();
        if (marketing) header.setAttribute('data-marketing', '');
        document.body.appendChild(header);
        assert.equal(RightsService.canSeeAdmin(), false);
        assert.equal(RightsService.canSeeReservations(), false);
        const button = header.querySelector('.btn-admin');
        assert.ok(button, 'signed-in accounts can enter My events even without privileged capabilities');
        button.click();
        assert.equal(navigations, marketing ? 2 : 1, 'use the existing signed-in routing and access checks');
        assert.equal(RightsService.canSeeAdmin(), false, 'navigation grants no administration rights');
        RightsService._context = { organization: {} };
        RightsService._notifyListeners();
        assert.equal(header.querySelector('.btn-admin'), null, 'sign-out removes personal navigation');
        header.remove();
    }
    AppConfig.webLink = 'https://hvezdamorska.festapp.net';
    RightsService._context = { user_info: { id: 'ordinary-attendee' }, capabilities: {} };
    const header = new UserHeader();
    document.body.appendChild(header);
    assert.equal(header.querySelector('.btn-admin'), null, 'app tenants retain capability-based administration entry');
    header.remove();
});
