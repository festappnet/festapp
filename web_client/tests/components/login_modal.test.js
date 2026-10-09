
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

    it('opens registration directly and switches both ways inside the same modal', () => {
        RightsService._context = { organization: { IS_REGISTRATION_ENABLED: true } };
        const modal = new LoginModal();
        modal.currentView = 'register';
        modal.googleEnabled = true;
        document.body.appendChild(modal);
        const dialog = modal.modal;

        assert.ok(modal.authContainer.querySelector('#register-form'));
        assert.ok(modal.authContainer.querySelector('#google-start'));
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

    it('shows tenant legal links below registration submit in every supported locale', async () => {
        const { LocalizationService } = await import('../../src/services/localization_service.js');
        const { AppConfig } = await import('../../src/app_config.js');
        const { readFile } = await import('node:fs/promises');
        const previous = LocalizationService.translations;
        try {
            for (const locale of ['cs', 'en', 'uk']) {
                LocalizationService.translations = JSON.parse(await readFile(new URL(`../../../assets/translations/${locale}.json`, import.meta.url), 'utf8'));
                const modal = new LoginModal();
                modal.currentView = 'register';
                document.body.appendChild(modal);
                const form = modal.authContainer.querySelector('#register-form');
                const notice = form.querySelector('.auth-registration-info');
                assert.equal(form.querySelector('button[type="submit"]').nextElementSibling, notice);
                assert.deepEqual([...notice.querySelectorAll('a')].map(a => a.getAttribute('href')), [AppConfig.termsUrl, AppConfig.privacyUrl]);
                assert.ok(!notice.textContent.includes('FeatureUser.'));
                modal.remove();
            }
        } finally { LocalizationService.translations = previous; }
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
});
