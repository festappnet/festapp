import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);

test('header mounted after initial account context immediately shows sign in', async t => {
    const dom = new JSDOM('<body></body>', { url: 'https://vstupenky.online/' });
    Object.assign(globalThis, { window: dom.window, document: dom.window.document,
        HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements });
    const { UserHeader } = await import('../../src/components/users/user_header.js');
    const { RightsService } = await import('../../src/services/rights_service.js');
    const previous = RightsService._context;
    t.after(() => { dom.window.close(); RightsService._context = previous; });
    const loadingHeader = new UserHeader();
    document.body.appendChild(loadingHeader);
    assert.equal(loadingHeader.querySelector('.btn-sign-in'), null, 'no guest button before account resolution');
    loadingHeader.remove();
    RightsService._context = { organization: { IS_REGISTRATION_ENABLED: true } };
    const header = new UserHeader();
    document.body.appendChild(header);
    assert.ok(header.querySelector('.btn-sign-in'), 'initial context must not require a second rights notification');
    header.remove();
    RightsService._context = { user_info: { id: 'user-1', name: 'Eva' } };
    const signedInHeader = new UserHeader();
    document.body.appendChild(signedInHeader);
    assert.ok(signedInHeader.querySelector('.avatar-circle'));
    assert.equal(signedInHeader.querySelector('.btn-sign-in'), null);
    RightsService._context = {};
    RightsService._notifyListeners();
    assert.ok(signedInHeader.querySelector('.btn-sign-in'), 'later account changes still update navigation');
});
