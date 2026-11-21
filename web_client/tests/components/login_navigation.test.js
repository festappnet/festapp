import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

// Exercise both sign-in completions without authentication or navigation side effects.
test('sign-in restores administration only from the generic home entry', async t => {
    const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://example.test/' });
    const browserGlobals = ['window', 'document', 'HTMLElement', 'customElements', 'sessionStorage'];
    const originalGlobals = Object.fromEntries(browserGlobals.map(key => [key, globalThis[key]]));
    Object.assign(globalThis, Object.fromEntries(browserGlobals.map(key => [key, dom.window[key]])));
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

    await t.test('Google security-key continuation submits an assertion instead of a code', async t => {
        const { PasskeyService } = await import('../../src/services/passkey_service.js');
        const { GoogleAuthService } = await import('../../src/services/google_auth_service.js');
        const modal = new LoginModal();
        modal.currentView = 'mfa';
        const options = { challenge: 'fixture' };
        const assertion = { id: 'fixture-credential' };
        const completed = { status: 'authenticated' };
        modal.googleResult = { status: 'needs_mfa', mfaMethod: 'webauthn', webAuthnOptions: options };
        const markup = modal._getContent();
        assert.match(markup, /id="webauthn-verify"/);
        assert.doesNotMatch(markup, /id="mfa-code"/);
        modal._runCredentialPrompt = callback => callback(new AbortController().signal);
        t.mock.method(PasskeyService, 'assertion', async passed => {
            assert.equal(passed, options);
            return assertion;
        });
        t.mock.method(GoogleAuthService, 'advance', async (operation, payload) => {
            assert.equal(operation, 'mfa_verify');
            assert.deepEqual(payload, { mfaAssertion: assertion });
            return completed;
        });
        const show = t.mock.method(modal, 'showGoogleResult', result => assert.equal(result, completed));
        await modal._advanceWebAuthn();
        assert.equal(show.mock.callCount(), 1);
    });

    await t.test('a held account can enroll a replacement without completing login', async t => {
        globalThis.window = dom.window;
        const { AppConfig } = await import('../../src/app_config.js');
        const { SupabaseService } = await import('../../src/services/supabase_service.js');
        const { PasskeyService } = await import('../../src/services/passkey_service.js');
        const initial = { access_token: 'held', user: { id: 'fixture-user' } };
        const upgraded = { ...initial, access_token: 'replacement', refresh_token: 'fixture-refresh' };
        const supportCode = 's'.repeat(43);
        const handoffCode = 'h'.repeat(43);
        const calls = [];
        let session = initial;
        const client = {
            rpc: async (name, payload) => {
                assert.equal(payload.p_organization, AppConfig.organization);
                return { data: name === 'get_account_assurance_v1' ? 'account_recovery' : { decision: 'allowed' } };
            },
            auth: {
                getSession: async () => ({ data: { session } }),
                setSession: async tokens => {
                    assert.equal(tokens.access_token, upgraded.access_token);
                    session = upgraded;
                    return { data: { session } };
                },
                signOut: async () => assert.fail('closing recovery revoked the session needed by support'),
            },
        };
        t.mock.method(SupabaseService, 'getClient', () => client);
        t.mock.method(PasskeyService, 'methods', async () => ({ totp: { offer: true, registration: true } }));
        t.mock.method(PasskeyService, 'request', async (route, payload, settings) => {
            assert.equal(settings.token, initial.access_token);
            calls.push({ route, payload });
            if (route.endsWith('/start')) return { callback: `${payload.redirectUri}?mfa_code=${handoffCode}` };
            if (route.endsWith('/claim')) return { method: 'totp', id: 'recovery-receipt' };
            if (route.endsWith('/enroll')) return {
                id: 'replacement-factor', totp: { secret: 'SETUPFIXTURE', uri: 'otpauth://totp/Fixture?secret=SETUPFIXTURE' },
            };
            return upgraded;
        });
        const verification = await AuthService.resumeVerification();
        assert.equal(verification.recovery, true);
        const modal = new LoginModal();
        document.body.append(modal);
        modal._showVerification(verification);
        const panel = modal.authContainer.querySelector('account-recovery-panel');
        await Promise.resolve();
        panel.querySelector('input').value = supportCode;
        await panel.submit(panel.querySelector('form'));
        assert.equal(calls[0].payload.recoveryCode, supportCode);
        assert.equal(calls[1].payload.recovery, true);
        assert.equal(calls[1].payload.code, handoffCode);
        assert.deepEqual(calls[2].payload, { receipt: 'recovery-receipt', recovery: true });
        assert.equal(panel.querySelector('code').textContent, 'SETUPFIXTURE');
        assert.notEqual(panel.querySelector('input').value, supportCode);
        panel.querySelector('input').value = '012345';
        await panel.submit(panel.querySelector('form'));
        assert.deepEqual(calls[3].payload, { receipt: 'recovery-receipt', factorId: 'replacement-factor', code: '012345', recovery: true });
        assert.equal(session, upgraded);
        assert.equal(panel.querySelector('form'), null);
        assert.ok(panel.querySelector('[role="status"]'));
        modal.modal.close();
        modal.remove();
    });
});

test('web password login waits for live MFA and preserves a leading zero in the code', async t => {
    const { AuthService } = await import('../../src/services/auth_service.js');
    const { SupabaseService } = await import('../../src/services/supabase_service.js');
    const first = { access_token: 'first-proof', user: { id: 'actor' } };
    const upgraded = { access_token: 'factor-proof', user: first.user };
    let active = first;
    const calls = [];
    const client = {
        rpc: async name => {
            assert.equal(name, 'get_account_assurance_v1');
            return { data: active === first ? 'mfa_required' : 'allowed' };
        },
        auth: {
            signInWithPassword: async () => ({ data: { session: first } }),
            getSession: async () => ({ data: { session: active } }),
            signOut: async () => calls.push('logout'),
            mfa: {
                listFactors: async () => ({ data: { totp: [{ id: 'factor' }] } }),
                challengeAndVerify: async params => {
                    calls.push(params);
                    active = upgraded;
                    return { data: upgraded };
                },
            },
        },
    };
    t.mock.method(SupabaseService, 'getClient', () => client);
    t.mock.method(AuthService, '_onLoginSuccess', async () => calls.push('ready'));

    const { verification } = await AuthService.login('fixture@example.invalid', 'unused');
    assert.deepEqual(calls, []);
    await AuthService.verifyLogin(verification, 'factor', '012345');
    assert.deepEqual(calls, [{ factorId: 'factor', code: '012345' }, 'ready']);
    await AuthService.cancelVerification(verification);
    await assert.rejects(AuthService.verifyLogin(verification, 'factor', '012345'), /invalid_session/);
    assert.deepEqual(calls, [{ factorId: 'factor', code: '012345' }, 'ready']);
});

test('web passkey sign-in waits for an independent verified WebAuthn factor', async t => {
    const { AuthService } = await import('../../src/services/auth_service.js');
    const { PasskeyService } = await import('../../src/services/passkey_service.js');
    const { SupabaseService } = await import('../../src/services/supabase_service.js');
    const { AppConfig } = await import('../../src/app_config.js');
    const first = { access_token: 'passkey-proof', refresh_token: 'first-refresh', user: { id: 'actor' } };
    const upgraded = { access_token: 'webauthn-proof', refresh_token: 'second-refresh', user: first.user };
    let session = null;
    let changeDuringPrompt = true;
    const calls = [];
    const client = {
        rpc: async () => ({ data: session === first ? 'mfa_required' : 'allowed' }),
        auth: {
            getSession: async () => ({ data: { session } }),
            setSession: async tokens => {
                calls.push(tokens.access_token);
                session = tokens.access_token === first.access_token ? first : upgraded;
                return { data: { session, user: session.user } };
            },
            mfa: { listFactors: async () => ({ data: { webauthn: [{ id: 'security-key' }] } }) },
        },
    };
    t.mock.method(SupabaseService, 'getClient', () => client);
    t.mock.method(PasskeyService, 'credentialSupport', () => true);
    t.mock.method(PasskeyService, 'signIn', async () => ({
        session: first, userId: first.user.id, organization: AppConfig.organization,
    }));
    t.mock.method(PasskeyService, 'request', async (path, body, settings) => {
        assert.equal(settings.token, first.access_token);
        assert.ok(path.startsWith('factors/security-key/'));
        calls.push(path);
        if (path.endsWith('/challenge')) {
            return { id: 'challenge', webauthn: { type: 'request', credential_options: { publicKey: {} } } };
        }
        assert.deepEqual(body.webauthn, { type: 'request', credential_response: { id: 'credential' } });
        return upgraded;
    });
    t.mock.method(PasskeyService, 'assertion', async () => {
        if (changeDuringPrompt) session = { access_token: 'other-actor' };
        return { id: 'credential' };
    });
    t.mock.method(AuthService, '_onLoginSuccess', async () => calls.push('ready'));

    const { verification } = await AuthService.loginWithPasskey();
    assert.deepEqual(calls, ['passkey-proof']);
    await assert.rejects(AuthService.verifyWebAuthn(verification, 'security-key'), /invalid_session/);
    assert.deepEqual(calls, ['passkey-proof', 'factors/security-key/challenge']);
    await assert.rejects(AuthService.loginWithPasskey(), /invalid_session/);
    session = first;
    changeDuringPrompt = false;
    await AuthService.verifyWebAuthn(verification, 'security-key');
    assert.deepEqual(calls.slice(-4), [
        'factors/security-key/challenge', 'factors/security-key/verify', 'webauthn-proof', 'ready',
    ]);
});

test('web passkey client exchanges a registered callback in place with its PKCE verifier', async t => {
    const { PasskeyService } = await import('../../src/services/passkey_service.js');
    const code = 'c'.repeat(43);
    const channel = { clientId: 'fixture', organization: 1, redirectUri: 'https://app.test/google-auth' };
    const { AppConfig } = await import('../../src/app_config.js');
    channel.organization = AppConfig.organization;
    const calls = [];
    let callbackOrigin = 'https://other.test';
    t.mock.method(PasskeyService, 'channel', () => channel);
    t.mock.method(PasskeyService, 'assertion', async () => ({ id: 'credential' }));
    t.mock.method(PasskeyService, 'request', async (path, body) => {
        const stage = path.split('/').at(-1);
        calls.push({ stage, body });
        if (stage === 'options') return { challenge_id: 'challenge', options: {} };
        if (stage === 'verify') return { callback: `${callbackOrigin}/google-auth?passkey_code=${code}` };
        return { userId: 'actor' };
    });
    await assert.rejects(PasskeyService.signIn(), /invalid_passkey_handoff/);
    assert.deepEqual(calls.map(call => call.stage), ['options', 'verify']);
    calls.length = 0;
    callbackOrigin = 'https://app.test';
    assert.deepEqual(await PasskeyService.signIn(), { userId: 'actor' });
    assert.deepEqual(calls.map(call => call.stage), ['options', 'verify', 'exchange']);
    const { body } = calls[2];
    assert.equal(body.code, code);
    assert.equal(body.clientId, channel.clientId);
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(body.codeVerifier));
    assert.equal(Buffer.from(digest).toString('base64url'), calls[0].body.codeChallenge);
});

test('account settings preserves the setup code and binds TOTP verification to the original session', async t => {
    const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://app.test/' });
    const originalDocument = globalThis.document;
    globalThis.document = dom.window.document;
    t.after(() => { globalThis.document = originalDocument; dom.window.close(); });
    const { AccountSecurityPanel } = await import('../../src/components/users/account_security_panel.js');
    const { PasskeyService } = await import('../../src/services/passkey_service.js');
    const user = { id: 'actor', factors: [] };
    const first = { access_token: 'initial', user };
    const next = { access_token: 'verified', user };
    let session = first;
    let decision = 'proof_required';
    let tokenInstalls = 0;
    const calls = [];
    const client = {
        rpc: async () => ({ data: decision }),
        auth: {
            getSession: async () => ({ data: { session } }),
            getUser: async () => ({ data: { user } }),
            setSession: async () => {
                tokenInstalls++;
                return { data: { user, session: session = next } };
            },
        },
    };
    t.mock.method(PasskeyService, 'methods', async () => ({ totp: { offer: true, registration: true } }));
    t.mock.method(PasskeyService, 'registrationReceipt', async () => 'receipt');
    t.mock.method(PasskeyService, 'request', async (route, body, settings) => {
        calls.push({ route, body, token: settings.token });
        return route.endsWith('enroll') ? { id: 'factor', totp: {
            secret: 'FIXTUREONLY123', uri: 'otpauth://totp/Fixture?secret=FIXTUREONLY123',
        } } : next;
    });
    const panel = new AccountSecurityPanel(client, user.id);
    await panel.load();
    await panel.enroll('totp');
    assert.equal(panel.proof, first);
    assert.deepEqual(calls, []);
    decision = 'allowed';
    panel.proof = null;
    await panel.enroll('totp');
    panel.render();
    assert.equal(panel.root.querySelector('code').textContent, 'FIXTUREONLY123');
    assert.match(panel.root.querySelector('img').src, /^data:image\/png/);
    session = { access_token: 'other', user: { id: 'other' } };
    await assert.rejects(panel.verifyTotp('012345'), /invalid_session/);
    session = first;
    await panel.verifyTotp('012345');
    assert.equal(calls[1].body.code, '012345');
    assert.equal(calls[1].token, first.access_token);
    assert.equal(panel.root.querySelector('code'), null);
    let selectedUser = 'another-account';
    t.mock.method(PasskeyService, 'signIn', async () => ({
        userId: selectedUser, organization: panel.organization, requiresMfa: false, session: next,
    }));
    panel.proof = next;
    await assert.rejects(panel.verifyProof('passkey'), /invalid_session/);
    assert.equal(tokenInstalls, 1);
    selectedUser = user.id;
    await panel.verifyProof('passkey');
    assert.equal(tokenInstalls, 2);
    assert.equal(panel.proof, null);
    panel.dispose();
});
