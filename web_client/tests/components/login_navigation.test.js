import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

// Exercise both sign-in completions without authentication or navigation side effects.
test('sign-in restores administration only from the generic home entry', async t => {
    const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://example.test/' });
    const originalGlobals = Object.fromEntries(['window', 'document', 'HTMLElement', 'customElements'].map(k => [k, globalThis[k]]));
    Object.assign(globalThis, { window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements });
    const { LoginModal } = await import('../../src/components/users/login_modal.js');
    const { RightsService } = await import('../../src/services/rights_service.js');
    const { RouterService } = await import('../../src/services/router_service.js');
    const { AuthService } = await import('../../src/services/auth_service.js');
    const { ToastHelper } = await import('../../src/components/ui/toast.js');
    const originals = [RightsService.canSeeAdmin, RouterService.navigateToAdmin, AuthService.login, ToastHelper.showSuccess];
    t.after(() => {
        [RightsService.canSeeAdmin, RouterService.navigateToAdmin, AuthService.login, ToastHelper.showSuccess] = originals;
        Object.assign(globalThis, originalGlobals);
        dom.window.close();
    });
    let navigations;
    let admin = true;
    RightsService.canSeeAdmin = () => admin;
    RouterService.navigateToAdmin = async () => navigations.push('remembered');
    AuthService.login = async () => {};
    ToastHelper.showSuccess = () => {};
    for (const [path, isAdmin, expected] of [['/', true, 'remembered'], ['/', false, 'reload'], ['/form/tickets', true, 'reload']]) {
        await t.test(`email: ${path}, organizer=${isAdmin}`, async () => {
            navigations = [];
            admin = isAdmin;
            globalThis.window = { location: { pathname: path, reload: () => navigations.push('reload') } };
            const modal = new LoginModal();
            modal._validateForm = () => true;
            modal._setLoading = () => {};
            modal.authContainer = { querySelector: () => ({ value: 'test' }) };
            modal.modal = { close() {} };
            await modal._handleLogin({ preventDefault() {} });
            assert.deepEqual(navigations, [expected]);
        });
    }
    for (const [path, isAdmin, expected] of [['/', true, 'remembered'], ['/', false, '/'], ['/unit/5/edit', true, '/unit/5/edit'], ['/form/tickets', true, '/form/tickets']]) {
        await t.test(`Google: ${path}, organizer=${isAdmin}`, () => {
            navigations = [];
            admin = isAdmin;
            globalThis.window = { location: { replace: target => navigations.push(target) } };
            new LoginModal().showGoogleResult({ status: 'authenticated', returnPath: path });
            assert.deepEqual(navigations, [expected]);
        });
    }
});
