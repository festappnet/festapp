import QRCode from 'qrcode';
import { AuthService } from '../../services/auth_service.js';
import { LocalizationService } from '../../services/localization_service.js';
import { PasskeyService } from '../../services/passkey_service.js';
import { CommonStrings } from '../shared/common_strings.js';

const text = key => LocalizationService.tr(`AccountSecurity.${key}`);

export class AccountRecoveryPanel extends HTMLElement {
    open(verification) {
        this.verification = verification;
        this.prompt = new AbortController();
        this.render();
        if (!verification.canReplace) return;
        void PasskeyService.methods(verification.session.access_token).then(methods => {
            if (this.prompt.signal.aborted) return;
            this.methods = [
                methods.totp?.offer && methods.totp.registration && ['totp', text('totp')],
                methods.webauthn?.offer && methods.webauthn.registration && PasskeyService.supportsRegistration() && ['webauthn', text('webauthn')],
            ].filter(Boolean);
            this.render();
        });
    }

    disconnectedCallback() {
        this.prompt?.abort();
        this.enrollment = null;
        this.replaceChildren();
    }

    render() {
        if (this.completed || !this.verification.canReplace || this.methods?.length === 0) {
            this.innerHTML = '<p role="status"></p>';
            this.firstElementChild.textContent = text(this.completed ? 'recoveryReplaced' : 'recoveryHeld');
            return;
        }
        if (!this.methods) {
            this.innerHTML = '<p role="status"></p>';
            this.firstElementChild.textContent = CommonStrings.loading;
            return;
        }
        const addingTotp = Boolean(this.enrollment);
        this.innerHTML = `
            <p id="account-recovery-hint">${text(addingTotp ? 'recoveryScan' : 'recoveryEnter')}</p>
            <form method="post" aria-labelledby="account-recovery-hint">
                ${addingTotp ? `
                    <img width="192" height="192" alt="${text('qr')}">
                    <p>${text('manual')} <code></code></p>
                    <label for="account-recovery-code">${CommonStrings.googleCode}</label>
                    <input id="account-recovery-code" name="otp" type="text" inputmode="numeric"
                           autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" required>
                ` : `
                    <label for="account-recovery-method">${text('recoveryMethod')}</label>
                    <select id="account-recovery-method" name="method"></select>
                    <label for="account-recovery-code">${text('recoveryCode')}</label>
                    <input id="account-recovery-code" name="recoveryCode" type="text" autocomplete="one-time-code"
                           autocapitalize="none" spellcheck="false" maxlength="43" pattern="[A-Za-z0-9_\\-]{43}" required>
                `}
                <button class="btn-primary" type="submit">${addingTotp ? CommonStrings.googleVerifyCode : text('recoveryStart')}</button>
                <p role="alert"></p>
            </form>`;
        if (addingTotp) {
            this.querySelector('img').src = this.enrollment.qr;
            this.querySelector('code').textContent = this.enrollment.secret;
        } else {
            const select = this.querySelector('select');
            for (const [value, label] of this.methods) {
                const option = this.ownerDocument.createElement('option');
                option.value = value;
                option.textContent = label;
                select.add(option);
            }
        }
        const form = this.querySelector('form');
        form.addEventListener('submit', event => {
            event.preventDefault();
            void this.submit(form);
        });
        this.querySelector('input').focus();
    }

    async submit(form) {
        if (this.busy) return;
        const fields = new this.ownerDocument.defaultView.FormData(form);
        const controls = [...form.elements];
        const alert = form.querySelector('[role="alert"]');
        const signal = this.prompt.signal;
        const checkSession = () => AuthService.requireRecoverySession(this.verification);
        const settings = { signal, token: this.verification.session.access_token };
        this.busy = true;
        alert.textContent = '';
        controls.forEach(control => { control.disabled = true; });
        try {
            await checkSession();
            let upgraded;
            if (this.enrollment) {
                const { receipt, factorId } = this.enrollment;
                upgraded = await PasskeyService.request('festapp/mfa/totp/verify', {
                    receipt, factorId, code: fields.get('otp'), recovery: true,
                }, settings);
            } else {
                const code = fields.get('recoveryCode');
                form.querySelector('input').value = '';
                const method = fields.get('method');
                const receipt = await PasskeyService.registrationReceipt(method, settings, code);
                await checkSession();
                if (method === 'totp') {
                    const factor = await PasskeyService.request('festapp/mfa/totp/enroll', { receipt, recovery: true }, settings);
                    const qr = await QRCode.toDataURL(factor.totp.uri, { margin: 2, width: 192 });
                    signal.throwIfAborted();
                    await checkSession();
                    this.enrollment = { receipt, factorId: factor.id, secret: factor.totp.secret, qr };
                    this.render();
                    return;
                }
                upgraded = await PasskeyService.enrollWebAuthn(receipt, settings, checkSession, true);
            }
            signal.throwIfAborted();
            await AuthService.installRecoveryReplacement(this.verification, upgraded);
            this.enrollment = null;
            this.completed = true;
            this.render();
        } catch {
            if (!signal.aborted) alert.textContent = text('recoveryError');
        } finally {
            this.busy = false;
            controls.forEach(control => { control.disabled = false; });
        }
    }
}

if (!customElements.get('account-recovery-panel')) customElements.define('account-recovery-panel', AccountRecoveryPanel);
