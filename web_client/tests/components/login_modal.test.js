
import { test, describe, it, before, beforeEach, after, afterEach } from 'node:test';
import assert from 'node:assert';
import { JSDOM, VirtualConsole } from 'jsdom';


describe('LoginModal Conditional Registration', () => {
    let LoginModal;
    let RightsService;
    let CommonStrings;

    before(async () => {
        console.log('DEBUG: Setup JSDOM...');
        const virtualConsole = new VirtualConsole();
        
        const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
            url: 'http://localhost/',
            // pretendToBeVisual: true // CAUSES HANGS via requestAnimationFrame
        });
        global.window = dom.window;
        global.document = dom.window.document;
        global.HTMLElement = dom.window.HTMLElement;
        global.customElements = dom.window.customElements;
        global.Event = dom.window.Event;
        
        // Polyfill rAF to prevent crash but avoid indefinite loop
        global.requestAnimationFrame = (cb) => setTimeout(cb, 0);
        global.cancelAnimationFrame = (id) => clearTimeout(id);

        process.on('uncaughtException', (err) => {
            console.error('UNCAUGHT EXCEPTION:', err);
        });
        process.on('unhandledRejection', (reason) => {
            console.error('UNHANDLED REJECTION:', reason);
        });
        
        
        console.log('DEBUG: Importing CommonStrings...');
        const commonStringsModule = await import('../../src/components/shared/common_strings.js');
        CommonStrings = commonStringsModule.CommonStrings;

        console.log('DEBUG: Importing RightsService...');
        const rightsModule = await import('../../src/services/rights_service.js');
        RightsService = rightsModule.RightsService;
        
        console.log('DEBUG: Importing LoginModal...');
        try {
            const module = await import('../../src/components/users/login_modal.js');
            LoginModal = module.LoginModal;
            console.log('DEBUG: LoginModal Imported');
        } catch (e) {
            console.error('DEBUG: Failed to import LoginModal', e);
        }

        if (!customElements.get('app-modal')) {
             console.log('DEBUG: Defining app-modal mock');
            class AppModal extends HTMLElement {
                connectedCallback() {}
                open() {}
                close() {}
            }
            customElements.define('app-modal', AppModal);
        }
    });

    beforeEach(() => {
        console.log('DEBUG: beforeEach');
        RightsService._context = null;
        document.body.innerHTML = '';
    });

    afterEach(() => {
        // Cleanup DOM
        document.body.innerHTML = '';
    });

    after(() => {
        if (global.window) global.window.close();
    });

    it('should SHOW registration link when IS_REGISTRATION_ENABLED is true', async () => {
        try {
            console.log('DEBUG: Test 1 Start');
            // Mock Context
            RightsService._context = {
                organization: { IS_REGISTRATION_ENABLED: true }
            };

            const modal = new LoginModal();
            document.body.appendChild(modal);
            if (!modal.authContainer) modal._render();

            console.log('DEBUG: Test 1 Rendered');
            const html = modal.authContainer.innerHTML;
            console.log('DEBUG: Test 1 HTML Length:', html.length);
            
            assert.match(html, /id="link-register"/, 'Registration link should be visible');
            assert.match(html, /FeatureUser.createAccount/, 'Link text should be present');
            console.log('DEBUG: Test 1 Passed');
        } catch (e) {
            console.error('DEBUG: Test 1 FAILED', e);
            throw e;
        }
    });

    it('opens registration directly and switches both ways inside the same modal', async () => {
        RightsService._context = { organization: { IS_REGISTRATION_ENABLED: true } };
        const { LocalizationService } = await import('../../src/services/localization_service.js');
        LocalizationService.translations = { FeatureUser: {
            signupLegalNotice: 'By clicking {button}, you agree to {terms} and acknowledge {privacy}.',
            signupTerms: 'terms of use', signupPrivacy: 'privacy policy',
        } };
        const modal = new LoginModal();
        modal.currentView = 'register';
        modal.googleEnabled = true;
        document.body.appendChild(modal);
        const dialog = modal.modal;

        assert.ok(modal.authContainer.querySelector('#register-form'));
        assert.ok(modal.authContainer.querySelector('#google-start'));
        const legalInfo = modal.authContainer.querySelector('.auth-registration-info');
        assert.doesNotMatch(legalInfo.textContent, /Michael Bujnovský/);
        assert.match(legalInfo.textContent, /agree to terms of use and acknowledge privacy policy/);
        assert.equal(legalInfo.previousElementSibling.type, 'submit');
        assert.deepEqual([...legalInfo.querySelectorAll('a')].map(link => link.href), [
            'https://vstupenky.online/terms/',
            'https://vstupenky.online/privacy/',
        ]);
        for (const link of legalInfo.querySelectorAll('a')) {
            assert.equal(link.target, '_blank');
            assert.equal(link.rel, 'noopener noreferrer');
        }
        for (const [id, autocomplete] of [
            ['email', 'email'], ['firstName', 'given-name'], ['lastName', 'family-name'],
        ]) {
            const input = modal.authContainer.querySelector(`#${id}`);
            assert.equal(input.autocomplete, autocomplete);
            assert.ok(input.placeholder);
        }
        modal.authContainer.querySelector('[data-auth-mode="login"]').click();
        assert.ok(modal.authContainer.querySelector('#login-form'));
        assert.ok(modal.authContainer.querySelector('#google-start'));
        modal.authContainer.querySelector('[data-auth-mode="register"]').click();
        assert.ok(modal.authContainer.querySelector('#register-form'));
        assert.equal(modal.modal, dialog);
        assert.equal(document.activeElement, modal.authContainer);
    });

    it('keeps the reset form and password across loading despite an unnamed username input', () => {
        const modal = new LoginModal();
        modal._render();
        modal.resetToken = '00000000-0000-4000-8000-000000000001';
        const input = modal.authContainer.querySelector('#newPassword');
        assert.equal(input.minLength, 8);
        input.value = 'a-valid-local-password';
        assert.ok(modal.authContainer.querySelector('input[name="username"]:not([id])'));
        modal._setLoading(true);
        modal._setLoading(false);
        assert.ok(modal.authContainer.querySelector('#reset-password-form'));
        assert.equal(modal.authContainer.querySelector('#newPassword').value, 'a-valid-local-password');
        assert.equal(modal.authContainer.querySelector('.error'), null);
    });

    it('prefills Google proof email and preserves manual edits across retry rendering', () => {
        const modal = new LoginModal();
        modal._render();
        modal.showGoogleResult({status: 'needs_account_proof', email: 'provider@example.com'});
        let email = modal.authContainer.querySelector('#email');
        assert.equal(email.value, 'provider@example.com');
        email.value = 'existing@example.com';
        email.dispatchEvent(new Event('input'));
        modal.googleError = 'account_proof_failed';
        modal._updateContent();
        email = modal.authContainer.querySelector('#email');
        assert.equal(email.value, 'existing@example.com');
    });

    it('should HIDE registration link when IS_REGISTRATION_ENABLED is false', () => {
        // Mock Context
        RightsService._context = {
            organization: { IS_REGISTRATION_ENABLED: false }
        };

        const modal = new LoginModal();
        document.body.appendChild(modal);
        if (!modal.authContainer) modal._render();

        const html = modal.authContainer.innerHTML;
        assert.doesNotMatch(html, /id="link-register"/, 'Registration link should be HIDDEN');
        assert.doesNotMatch(html, /<span>\|<\/span>/, 'Separator should be HIDDEN');
    });

    it('should SHOW registration link by DEFAULT (backwards compatibility)', () => {
        // Mock Context empty or missing flag
        RightsService._context = {
            organization: {} // Missing flag
        };

        const modal = new LoginModal();
        document.body.appendChild(modal);
        if (!modal.authContainer) modal._render();

        const html = modal.authContainer.innerHTML;
        assert.match(html, /id="link-register"/, 'Registration link should be visible by default');
    });
    it('registration confirms only this address, survives rerender, revokes on edits and never auto-submits', async (t) => {
        const { AuthService } = await import('../../src/services/auth_service.js');
        const { ToastHelper } = await import('../../src/components/ui/toast.js');
        let requests = 0;
        t.mock.method(AuthService, 'register', async () => { requests++; });
        t.mock.method(ToastHelper, 'showSuccess', () => null);
        const modal = new LoginModal(); modal._render(); modal._setView('register');
        document.body.appendChild(modal.authContainer);
        const value = (id, text) => { const input = modal.authContainer.querySelector('#' + id); input.value = text; input.dispatchEvent(new Event('input', { bubbles: true })); };
        value('email', 'a@example.czz'); value('firstName', 'A'); value('lastName', 'B');
        await modal._handleRegister({ preventDefault() {} });
        assert.equal(requests, 0);
        let warning = modal.authContainer.querySelector('[data-email-suffix-warning]');
        assert.equal(warning.hidden, false);
        warning.querySelector('button').click();
        assert.equal(requests, 0);
        modal._updateContent(true);
        assert.equal(modal.authContainer.querySelector('[data-email-suffix-warning]').hidden, true);
        value('email', 'b@example.czz');
        await modal._handleRegister({ preventDefault() {} });
        assert.equal(requests, 0);
        modal.authContainer.querySelector('[data-email-suffix-warning] button').click();
        await modal._handleRegister({ preventDefault() {} });
        assert.equal(requests, 1);
        modal._setView('register');
        value('email', 'b@example.czz'); value('firstName', 'A'); value('lastName', 'B');
        await modal._handleRegister({ preventDefault() {} });
        assert.equal(requests, 1, 'new registration session needs confirmation again');
        value('email', 'a@example.рф');
        await modal._handleRegister({ preventDefault() {} });
        assert.equal(requests, 1);
        assert.equal(modal.authContainer.querySelector('[data-email-suffix-warning]').hidden, false);
        modal.authContainer.querySelector('[data-email-suffix-warning] button').click();
        await modal._handleRegister({ preventDefault() {} });
        assert.equal(requests, 2, 'accepted Unicode input has an overridable warning');
    });

    it('login, reset and Google proof accept unknown suffixes without confirmation', async (t) => {
        const { AuthService } = await import('../../src/services/auth_service.js');
        const { GoogleAuthService } = await import('../../src/services/google_auth_service.js');
        const { ToastHelper } = await import('../../src/components/ui/toast.js');
        let login = 0, reset = 0, proof = 0;
        t.mock.method(AuthService, 'login', async () => { login++; });
        t.mock.method(AuthService, 'resetPasswordForEmail', async () => { reset++; });
        t.mock.method(GoogleAuthService, 'advance', async () => { proof++; return { status: 'needs_account_proof' }; });
        t.mock.method(ToastHelper, 'showSuccess', () => null);
        const modal = new LoginModal(); modal._render();
        modal.modal.close = () => {};
        const fill = () => { modal.authContainer.querySelector('#email').value = 'a@example.czz'; const password = modal.authContainer.querySelector('#password'); if (password) password.value = 'password123'; };
        fill(); await modal._handleLogin({ preventDefault() {} });
        modal._setView('forgot'); fill(); await modal._handleReset({ preventDefault() {} });
        modal.showGoogleResult({ status: 'needs_account_proof' }); fill();
        await modal._advanceGoogle({ preventDefault() {} }, 'prove_existing');
        assert.equal(login, 1); assert.equal(reset, 1); assert.equal(proof, 1);
        assert.equal(modal.authContainer.querySelector('[data-email-suffix-warning]'), null);
    });

});
