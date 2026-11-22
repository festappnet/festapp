import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { register } from 'node:module';
import test from 'node:test';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);
const dom = new JSDOM('<body></body>', { url: 'https://vstupenky.online/' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
    HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements });
const { AccountSecurityPanel } = await import('../../src/components/users/account_security_panel.js');
const { AppConfig } = await import('../../src/app_config.js');
const { LocalizationService } = await import('../../src/services/localization_service.js');
const { PasskeyService } = await import('../../src/services/passkey_service.js');
const { SupabaseService } = await import('../../src/services/supabase_service.js');
test.after(() => dom.window.close());

test('enrollment explains which change needs password verification and can be cancelled', async t => {
    AppConfig.appName = 'vstupenky.online';
    LocalizationService.translations = JSON.parse(readFileSync(
        new URL('../../../assets/translations/cs.json', import.meta.url), 'utf8'));
    t.mock.method(PasskeyService, 'supportsRegistration', () => true);

    const session = { user: { id: 'pilot' } };
    const panel = new AccountSecurityPanel({
        auth: { getSession: async () => ({ data: { session } }) },
        rpc: async () => ({ data: 'proof_required' }),
    }, 'pilot');
    panel.methods = {
        passkey: { offer: true, registration: true },
        totp: { offer: true, registration: true },
    };
    dom.window.document.body.append(panel.root);

    for (const [method, action] of [['passkey', 'Přidat passkey'], ['totp', 'Přidat ověřovací aplikaci']]) {
        await panel.run(signal => panel.enroll(method, signal));
        const password = panel.root.querySelector('input[type="password"]');
        assert.equal(password.autocomplete, 'current-password');
        const toggle = panel.root.querySelector('.toggle-password');
        assert.equal(toggle.type, 'button');
        assert.equal(toggle.getAttribute('aria-label'), 'Zobrazit nebo skrýt heslo');
        assert.equal(toggle.getAttribute('aria-pressed'), 'false');
        toggle.click();
        assert.equal(password.type, 'text');
        assert.equal(toggle.getAttribute('aria-pressed'), 'true');
        toggle.click();
        assert.equal(password.type, 'password');
        assert.equal(toggle.getAttribute('aria-pressed'), 'false');
        const buttons = [...panel.root.querySelectorAll('button:not(.toggle-password)')];
        assert.deepEqual(buttons.map(button => button.textContent), ['Ověřit totožnost', 'Zrušit']);
        assert.equal(panel.root.querySelector('h3').textContent, action);
        assert.match(panel.root.textContent, /heslo k účtu na vstupenky\.online/);
        buttons[1].click();
        assert.equal(panel.root.querySelector('form'), null);
        assert.ok([...panel.root.querySelectorAll('button')].some(button => button.textContent === action));
    }
});

test('passkey enrollment displays the mailbox and respects excluded credentials and duplicates', async t => {
    const originalOrganization = AppConfig.organization;
    const originalBackend = SupabaseService._backend;
    AppConfig.organization = 3;
    SupabaseService._backend = { supabaseUrl: 'https://auth.example.invalid', anonKey: 'test' };
    t.after(() => {
        AppConfig.organization = originalOrganization;
        SupabaseService._backend = originalBackend;
    });

    const session = { access_token: 'active', user: { id: 'pilot' } };
    const panel = new AccountSecurityPanel({
        auth: { getSession: async () => ({ data: { session } }) },
        rpc: async () => ({ data: 'allowed' }),
    }, 'pilot');
    panel.passkeys = [{ id: 'existing', friendly_name: 'Google Password Manager' }];
    t.mock.method(panel, 'load', async () => {});
    t.mock.method(PasskeyService, 'registrationReceipt', async () => 'receipt');

    const options = {
        user: { id: 'user-handle', name: '3+jana+ples@example.invalid', displayName: '3+jana+ples@example.invalid' },
        challenge: 'browser-challenge', excludeCredentials: [{ id: 'existing' }],
        rp: { id: 'vstupenky.online' },
    };
    const optionsResponse = { options, challenge_id: 'challenge-id' };
    let verificationStatus = 200;
    let verificationCalls = 0;
    t.mock.method(globalThis, 'fetch', async url => {
        if (url.pathname.endsWith('/options')) return Response.json(optionsResponse);
        assert.ok(url.pathname.endsWith('/verify'));
        verificationCalls++;
        return Response.json(verificationStatus === 422
            ? { code: 422, error_code: 'webauthn_credential_exists' }
            : {}, { status: verificationStatus });
    });

    const updatedLabels = [];
    globalThis.PublicKeyCredential = {
        signalCurrentUserDetails: async details => { updatedLabels.push(details); },
    };
    t.after(() => { delete globalThis.PublicKeyCredential; });
    let browserError = 'InvalidStateError';
    const create = t.mock.method(PasskeyService, 'creation', async () => {
        if (browserError) throw new DOMException('', browserError);
        return { id: 'new-passkey' };
    });
    const enroll = () => panel.run(signal => panel.enroll('passkey', signal));

    await enroll();
    assert.deepEqual(create.mock.calls[0].arguments[0], {
        ...options, user: { ...options.user, name: 'jana+ples@example.invalid', displayName: 'jana+ples@example.invalid' },
    });
    assert.match(panel.notice, /klíč už je zaregistrovaný/);
    assert.equal(panel.error, null);
    assert.equal(verificationCalls, 0);
    assert.deepEqual(updatedLabels, [{
        rpId: 'vstupenky.online', userId: 'user-handle',
        name: 'jana+ples@example.invalid', displayName: 'jana+ples@example.invalid',
    }]);

    browserError = 'NotAllowedError';
    await enroll();
    assert.match(panel.notice, /zrušeno nebo vypršelo/);
    assert.equal(verificationCalls, 0);

    browserError = null;
    verificationStatus = 422;
    options.user.displayName = 'Jana Nováková';
    await enroll();
    assert.equal(create.mock.calls[2].arguments[0].user.displayName, 'Jana Nováková');
    assert.match(panel.notice, /klíč už je zaregistrovaný/);
    assert.equal(panel.error, null);
    assert.equal(verificationCalls, 1);

    verificationStatus = 200;
    await enroll();
    assert.equal(panel.notice, 'Přihlašovací metoda byla přidána.');
    assert.equal(verificationCalls, 2);
});
