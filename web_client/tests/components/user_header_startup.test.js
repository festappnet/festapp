import assert from 'node:assert/strict';
import test from 'node:test';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';

register('../css_loader.mjs', import.meta.url);
import { AuthorizationCapabilities } from '../../src/services/authorization_capabilities.js';

test('header renders existing rights on connection and still follows later updates', async t => {
    const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://vstupenky.online/' });
    for (const key of ['window', 'document', 'HTMLElement', 'customElements']) {
        globalThis[key] = key === 'window' ? dom.window : dom.window[key];
    }
    const [{ UserHeader }, { RightsService }] = await Promise.all([
        import('../../src/components/users/user_header.js'),
        import('../../src/services/rights_service.js'),
    ]);
    const originalContext = RightsService._context;
    t.after(() => { RightsService._context = originalContext; dom.window.close(); });
    const guest = { organization: {} };
    const admin = { user_info: { id: 'admin', name: 'Admin' }, capabilities: { [AuthorizationCapabilities.navigationAdminWeb]: true } };
    t.mock.method(RightsService, 'updateAppData', () => assert.fail('connecting must not start a backend request'));

    for (const context of [guest, admin]) {
        RightsService._context = context;
        const header = new UserHeader();
        document.body.appendChild(header);
        assert.ok(header.querySelector(context === guest ? '.btn-sign-in' : '.btn-admin'),
            'rights published before connection must appear immediately');
        header.remove();
        RightsService._context = context === guest ? admin : guest;
        document.body.appendChild(header);
        assert.ok(header.querySelector(context === guest ? '.btn-admin' : '.btn-sign-in'),
            'reconnection must render the current rights');
        RightsService._context = context;
        RightsService._notifyListeners();
        assert.ok(header.querySelector(context === guest ? '.btn-sign-in' : '.btn-admin'));
        header.remove();
    }
    RightsService._context = null;
    const pendingHeader = new UserHeader();
    document.body.appendChild(pendingHeader);
    assert.equal(pendingHeader.querySelector('.btn-sign-in'), null, 'do not flash guest controls before rights resolve');
    RightsService._context = guest;
    RightsService._notifyListeners();
    assert.ok(pendingHeader.querySelector('.btn-sign-in'));
    pendingHeader.remove();
});
