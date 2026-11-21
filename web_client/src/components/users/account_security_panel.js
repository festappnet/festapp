import QRCode from 'qrcode';
import { AppConfig } from '../../app_config.js';
import { AuthService } from '../../services/auth_service.js';
import { LocalizationService } from '../../services/localization_service.js';
import { PasskeyService } from '../../services/passkey_service.js';
import { CommonStrings } from '../shared/common_strings.js';

const text = key => LocalizationService.tr(`AccountSecurity.${key}`);
const typeOf = factor => factor.factor_type;
const otp = /^[0-9]{6}$/;

export class AccountSecurityPanel {
    constructor(client, userId) {
        this.client = client;
        this.userId = userId;
        this.organization = AppConfig.organization;
        this.root = document.createElement('section');
        this.root.className = 'account-security';
        this.root.hidden = true;
        this.factors = [];
        this.passkeys = null;
        this.methods = {};
    }

    dispose() {
        this.disposed = true;
        this.operation?.abort();
        this.enrollment = null;
        this.root.replaceChildren();
    }

    async session(expected) {
        const { data, error } = await this.client.auth.getSession();
        const session = data?.session;
        if (this.disposed || error || session?.user?.id !== this.userId ||
            AppConfig.organization !== this.organization ||
            (expected && session.access_token !== expected.access_token)) throw new Error('invalid_session');
        return session;
    }

    async load(expected) {
        const session = await this.session(expected);
        const [result, methods, passkeys] = await Promise.all([
            this.client.auth.getUser(session.access_token),
            PasskeyService.methods(),
            PasskeyService.storedPasskeys({ token: session.access_token }),
        ]);
        await this.session(session);
        if (result.error || result.data?.user?.id !== this.userId) throw new Error('invalid_session');
        this.factors = (result.data.user.factors ?? []).filter(factor => factor.status === 'verified');
        this.methods = methods;
        this.passkeys = passkeys;
        this.render();
    }

    async requireFresh() {
        const session = await this.session();
        const { data, error } = await this.client.rpc('get_account_assurance_v1', {
            p_organization: this.organization, p_account_security: true,
        });
        await this.session(session);
        if (error) throw error;
        if (data === 'allowed') return session;
        if (data !== 'proof_required' && data !== 'mfa_required') throw new Error('invalid_session');
        this.proof = session;
        return null;
    }

    async verifyProof(kind, input, signal) {
        const session = await this.session(this.proof);
        if (kind === 'password' || kind === 'passkey') {
            const result = kind === 'passkey' ? await this.passkeyProof(session, signal)
                : await this.client.auth.signInWithPassword({ email: session.user.email, password: input });
            const { data, error } = result;
            if (error || data?.session?.user?.id !== this.userId) throw new Error('invalid_session');
            await this.session(data.session);
            this.passwordProof = false;
            this.proof = null;
            if (!await this.requireFresh()) return;
        } else if (typeOf(kind) === 'webauthn') {
            await AuthService.verifyWebAuthn({ session, webauthn: [kind] }, kind.id, signal);
        } else if (otp.test(input)) {
            await AuthService.verifyLogin({ session, factors: [kind] }, kind.id, input);
        }
        this.proof = null;
        this.notice = text('verified');
        await this.load();
    }

    async passkeyProof(session, signal) {
        const result = await PasskeyService.signIn(signal);
        signal?.throwIfAborted();
        await this.session(session);
        if (this.passwordProof || this.factors.length || result.requiresMfa !== false ||
            result.userId !== this.userId || result.organization !== this.organization) throw new Error('invalid_session');
        return this.client.auth.setSession(result.session);
    }

    async enroll(method, signal) {
        const session = await this.requireFresh();
        if (!session) return;
        const settings = { token: session.access_token, signal };
        const receipt = await PasskeyService.registrationReceipt(method, settings);
        await this.session(session);
        if (method === 'totp') {
            const factor = await PasskeyService.request('festapp/mfa/totp/enroll', { receipt }, settings);
            const qr = await QRCode.toDataURL(factor.totp.uri, { margin: 2, width: 256 });
            await this.session(session);
            this.enrollment = { receipt, session, factorId: factor.id, secret: factor.totp.secret, qr };
            return;
        }
        if (method === 'passkey') {
            const request = path => `festapp/passkey/registration/${path}`;
            const options = await PasskeyService.request(request('options'), { receipt }, settings);
            const credential = await PasskeyService.creation(options.options, signal);
            await this.session(session);
            await PasskeyService.request(request('verify'), { receipt, challengeId: options.challenge_id, credential }, settings);
        } else {
            const verified = await PasskeyService.enrollWebAuthn(receipt, settings, () => this.session(session));
            await this.install(session, verified);
        }
        this.notice = text('added');
        await this.load();
    }

    async verifyTotp(code, signal) {
        if (!this.enrollment || !otp.test(code)) return;
        const { receipt, session, factorId } = this.enrollment;
        await this.session(session);
        const verified = await PasskeyService.request('festapp/mfa/totp/verify', { receipt, factorId, code }, {
            token: session.access_token, signal,
        });
        this.enrollment = null;
        await this.install(session, verified);
        this.notice = text('added');
        await this.load();
    }

    async install(previous, upgraded) {
        await this.session(previous);
        const { data, error } = await this.client.auth.setSession({
            access_token: upgraded.access_token, refresh_token: upgraded.refresh_token,
        });
        if (error || data?.user?.id !== this.userId) throw new Error('invalid_session');
        await this.session(data.session);
    }

    async remove(factor, confirmDisable, signal) {
        const session = await this.requireFresh();
        if (!session) return;
        const result = await PasskeyService.request('festapp/mfa/factors/remove', {
            factorId: factor.id, confirmDisable,
        }, { token: session.access_token, signal });
        if (!result.removed) throw new Error('mfa_operation_refused');
        await this.session(session);
        this.pendingRemove = null;
        // Removing the factor that authenticated this session may revoke it.
        if (result.revokesSession) {
            await this.client.auth.signOut({ scope: 'local' });
            return;
        }
        this.notice = text('removed');
        await this.load();
    }

    async managePasskey(operation, passkey, signal, name) {
        const session = await this.requireFresh();
        if (!session) return;
        let result;
        try {
            result = await PasskeyService.request(`festapp/passkey/manage/${operation}`, {
                id: passkey.id, ...(name ? { name } : {}),
            }, { token: session.access_token, signal });
        } catch (error) {
            if (error.message !== 'password_proof_required') throw error;
            this.proof = session;
            this.passwordProof = true;
            return;
        }
        await this.session(session);
        this.editPasskey = null;
        this.pendingPasskeyRemoval = null;
        if (result.revokesSession) {
            await this.client.auth.signOut({ scope: 'local' });
            return;
        }
        await this.load();
    }

    async run(action) {
        if (this.operation || this.disposed) return;
        const controller = new AbortController();
        this.operation = controller;
        this.error = null;
        this.notice = null;
        this.render();
        try {
            await action(controller.signal);
        } catch (error) {
            if (!controller.signal.aborted) {
                this.error = error.name === 'NotAllowedError' ? CommonStrings.passkeyCancelled : text('error');
                if (error.message === 'invalid_session') this.enrollment = null;
                if (error.message === 'confirm_disable_mfa') {
                    this.pendingRemove = null;
                    await this.load().catch(() => {});
                }
            }
        } finally {
            this.operation = null;
            if (!this.disposed) this.render();
        }
    }

    render() {
        const eligible = method => this.methods[method]?.offer && this.methods[method]?.registration;
        this.root.hidden = !this.factors.length && !this.passkeys?.length && !['totp', 'webauthn', 'passkey'].some(eligible);
        this.root.replaceChildren();
        if (this.root.hidden) return;
        this.root.setAttribute('aria-labelledby', 'account-security-heading');
        this.root.setAttribute('aria-busy', String(Boolean(this.operation)));
        const add = (tag, label, parent = this.root) => {
            const element = document.createElement(tag);
            element.textContent = label;
            parent.append(element);
            return element;
        };
        const button = (label, action, parent = this.root) => {
            const element = add('button', label, parent);
            element.type = 'button';
            element.disabled = Boolean(this.operation);
            element.onclick = action;
            return element;
        };
        const form = (label, type, whenSubmitted, parent = this.root) => {
            const wrapper = add('form', '', parent);
            wrapper.method = 'post';
            const field = add('label', label, wrapper);
            const input = add('input', '', field);
            input.type = type === 'name' ? 'text' : type;
            input.required = true;
            input.disabled = Boolean(this.operation);
            input.autocomplete = type === 'password' ? 'current-password'
                : type === 'text' ? 'one-time-code' : 'off';
            if (type === 'text') {
                input.inputMode = 'numeric';
                input.pattern = '[0-9]{6}';
                input.maxLength = 6;
            }
            if (type === 'name') {
                input.value = this.editPasskey?.friendly_name ?? '';
                input.maxLength = 120;
            }
            const submit = button(type === 'text' ? CommonStrings.googleVerifyCode
                : type === 'name' ? CommonStrings.save : CommonStrings.signIn, null, wrapper);
            submit.type = 'submit';
            wrapper.onsubmit = event => {
                event.preventDefault();
                if (!input.reportValidity()) return;
                const value = input.value;
                input.value = '';
                void this.run(signal => whenSubmitted(value, signal));
            };
        };

        add('h2', text('title')).id = 'account-security-heading';
        if (this.error) add('p', this.error).setAttribute('role', 'alert');
        if (this.notice) add('p', this.notice).setAttribute('role', 'status');
        if (this.enrollment) {
            const image = add('img', '');
            image.src = this.enrollment.qr;
            image.width = image.height = 256;
            image.alt = text('qr');
            add('p', text('manual'));
            add('code', this.enrollment.secret);
            form(CommonStrings.googleCode, 'text', (code, signal) => this.verifyTotp(code, signal));
            button(CommonStrings.cancel, () => { this.enrollment = null; this.render(); });
            return;
        }
        if (this.proof) {
            add('p', text('freshProof'));
            if (this.passwordProof || this.factors.length === 0) {
                form(CommonStrings.password, 'password', (value, signal) => this.verifyProof('password', value, signal));
                const passkey = this.methods.passkey;
                if (!this.passwordProof && this.passkeys?.length && passkey?.offer && passkey.signIn && PasskeyService.credentialSupport()) {
                    button(CommonStrings.passkeySignIn, () => this.run(signal => this.verifyProof('passkey', null, signal)));
                }
            } else {
                for (const factor of this.factors) {
                    const item = add('div', '');
                    add('p', CommonStrings.mfaFactorName(factor.friendly_name, text(typeOf(factor))), item);
                    if (typeOf(factor) === 'totp') {
                        form(CommonStrings.googleCode, 'text', (code, signal) => this.verifyProof(factor, code, signal), item);
                    } else if (typeOf(factor) === 'webauthn' && PasskeyService.credentialSupport()) {
                        button(CommonStrings.mfaVerifySecurityKey, () => this.run(signal => this.verifyProof(factor, null, signal)), item);
                    }
                }
            }
            button(CommonStrings.cancel, () => { this.proof = null; this.passwordProof = false; this.render(); });
            return;
        }
        for (const factor of this.factors) {
            const item = add('div', '');
            add('p', CommonStrings.mfaFactorName(factor.friendly_name, text(typeOf(factor))), item);
            if (this.pendingRemove === factor) {
                const last = this.factors.length === 1;
                add('p', text(last ? 'disableConfirm' : 'removeConfirm'), item);
                button(text(last ? 'disable' : 'remove'), () => this.run(signal => this.remove(factor, last, signal)), item);
                button(CommonStrings.cancel, () => { this.pendingRemove = null; this.render(); }, item);
            } else {
                button(text('remove'), () => { this.pendingRemove = factor; this.render(); }, item);
            }
        }
        if (this.passkeys?.length || (this.passkeys && eligible('passkey'))) {
            add('h3', text('passkeys'));
            if (!this.passkeys.length) add('p', text('noPasskeys'));
            const formatter = new Intl.DateTimeFormat(LocalizationService.currentLocale, { dateStyle: 'medium' });
            const date = (key, value, parent) => {
                if (!value || !Number.isFinite(Date.parse(value))) return;
                add('p', `${text(key)} ${formatter.format(new Date(value))}`, parent);
            };
            for (const passkey of this.passkeys) {
                const item = add('div', '');
                add('p', passkey.friendly_name || text('passkey'), item);
                date('created', passkey.created_at, item);
                date('lastUsed', passkey.last_used_at, item);
                if (this.editPasskey?.id === passkey.id) {
                    form(text('passkeyName'), 'name', (name, signal) =>
                        this.managePasskey('rename', passkey, signal, name.trim()), item);
                    button(CommonStrings.cancel, () => { this.editPasskey = null; this.render(); }, item);
                } else if (this.pendingPasskeyRemoval?.id === passkey.id) {
                    add('p', text('passkeyRemoveConfirm'), item);
                    button(text('remove'), () => this.run(signal => this.managePasskey('remove', passkey, signal)), item);
                    button(CommonStrings.cancel, () => { this.pendingPasskeyRemoval = null; this.render(); }, item);
                } else {
                    button(CommonStrings.edit, () => {
                        this.pendingPasskeyRemoval = null; this.editPasskey = passkey; this.render();
                    }, item);
                    button(text('remove'), () => {
                        this.editPasskey = null; this.pendingPasskeyRemoval = passkey; this.render();
                    }, item);
                }
            }
        }
        for (const [method, label] of [['totp', 'addTotp'], ['webauthn', 'addKey'], ['passkey', 'addPasskey']]) {
            if (eligible(method) && (method === 'totp' || PasskeyService.supportsRegistration())) {
                button(text(label), () => this.run(signal => this.enroll(method, signal)));
            }
        }
    }
}
