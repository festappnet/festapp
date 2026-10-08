
import { GoogleAuthService } from '../../services/google_auth_service.js';
import { GOOGLE_AUTH_STYLES, GOOGLE_G } from './google_auth_styles.js';
import { AuthService } from '../../services/auth_service.js';
import { CommonStrings } from '../shared/common_strings.js';
import { ToastHelper } from '../ui/toast.js';
import { Modal } from '../ui/modal.js';
import { RightsService } from '../../services/rights_service.js';
import { AppConfig } from '../../app_config.js';
import { SHARED_MODAL_STYLES } from '../shared/modal_styles.js';
import { RouterService } from '../../services/router_service.js';
// import './login_modal.css'; // Removed in favor of inline styles for test compatibility

const LOGIN_MODAL_STYLES = SHARED_MODAL_STYLES + GOOGLE_AUTH_STYLES;

export class LoginModal extends HTMLElement {
    constructor() {
        super();
        this.currentView = 'login'; // login, register, forgot
        this.isLoading = false;
        this.googleEnabled = false;
        this.googleResult = null;
        this.googleError = '';
        
        // Bind methods
        this._render = this._render.bind(this);
        this._handleReset = this._handleReset.bind(this);
        this._handleChangePassword = this._handleChangePassword.bind(this);
        this._togglePasswordVisibility = this._togglePasswordVisibility.bind(this);
        this._handleLogin = this._handleLogin.bind(this);
        this._handleRegister = this._handleRegister.bind(this);
    }

    _isRegistrationEnabled() {
        const orgSettings = RightsService.context?.organization;
        // Check exact boolean false to disable, otherwise default directly to enabled (legacy/fallback)
        if (orgSettings && typeof orgSettings.IS_REGISTRATION_ENABLED === 'boolean') {
            return orgSettings.IS_REGISTRATION_ENABLED;
        }
        return true; 
    }

    set resetToken(token) {
        this._resetToken = token;
        // If token is set, automatically switch to reset_password view
        if (token) {
            this._setView('reset_password');
        }
    }

    connectedCallback() {
        this._handleKeyDown = this._handleKeyDown.bind(this);
        window.addEventListener('keydown', this._handleKeyDown);
        this._previousFocus = document.activeElement;
        this._render();
        GoogleAuthService.capability().then(enabled => {
            if (!this.isConnected) return;
            this.googleEnabled = enabled;
            this._updateContent(true);
        });
    }
    
    disconnectedCallback() {
        window.removeEventListener('keydown', this._handleKeyDown);
    }
    
    _handleKeyDown(e) {
        if (e.key === 'Tab' && this.authContainer) {
            const items = [...this.authContainer.querySelectorAll('button:not(:disabled),input:not(:disabled),a[href]')];
            const first = items[0], last = items.at(-1);
            if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last?.focus(); }
            else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first?.focus(); }
        }
        if (e.key === 'Escape') {
            // Respect the mandatory reset check inside modal.close()
            if (this.modal) this.modal.close();
        }
    }

    _render() {
        this.innerHTML = `<style>${LOGIN_MODAL_STYLES}</style>`;
        
        this.modal = document.createElement('app-modal');
        // Create container programmatically to ensure we have a reference and it's attached correctly
        this.authContainer = document.createElement('div');
        this.authContainer.className = 'auth-container';
        
        this.modal.appendChild(this.authContainer);
        this.appendChild(this.modal);
        
        this.modal.open();
        
        this._updateContent();
        this.authContainer.tabIndex = -1;
        this.authContainer.focus();
        
        const originalClose = this.modal.close.bind(this.modal);
        this.modal.close = () => {
            // Prevent closing if we are in the middle of a forced reset
            if (this._resetToken || this.currentView === 'reset_password') {
                return;
            }
            
            // Dismiss sticky toast if exists
            if (this._stickyToast) {
                this._stickyToast.hide();
                this._stickyToast = null;
            }

            GoogleAuthService.cancel();
            originalClose();
            this._previousFocus?.focus?.();
            setTimeout(() => {
                if(this.parentNode) this.parentNode.removeChild(this);
            }, 300);
        };
    }
    
    _updateContent(preserveFields = false) {
        const previousFields = preserveFields && this.authContainer ? [...this.authContainer.querySelectorAll('input')].map(input => ({ id: input.id, value: input.value, checked: input.checked, focused: input === document.activeElement })) : [];

        if (!this.authContainer) return;
        
        try {
            this.authContainer.innerHTML = this._getContent();
            
            // Re-add Close Button as innerHTML wipe removes it
            // Only show if closable (not mandatory reset)
            const isMandatoryReset = this._resetToken || this.currentView === 'reset_password';
            
            if (!isMandatoryReset) {
                const closeBtn = document.createElement('button');
                closeBtn.className = 'modal-close-btn';
                closeBtn.type = 'button';
                closeBtn.setAttribute('aria-label', CommonStrings.googleClose);
                closeBtn.textContent = '×';
                closeBtn.onclick = () => this.modal.close();
                this.authContainer.appendChild(closeBtn);
            }

            this.authContainer.setAttribute('role', 'dialog');
            this.authContainer.setAttribute('aria-modal', 'true');
            this.authContainer.setAttribute('aria-label', this.authContainer.querySelector('h2')?.textContent || CommonStrings.signIn);
            this.authContainer.setAttribute('aria-busy', String(this.isLoading));
            this._attachListeners();
            this._initPasswordToggles();
            for (const previous of previousFields) {
                const input = this.authContainer.querySelector(`#${previous.id}`);
                if (input) { input.value = previous.value; input.checked = previous.checked; if(previous.focused) input.focus(); }
            }
        } catch (e) {
            console.error("LoginModal render error:", e);
            this.authContainer.innerHTML = `<p class="error">Error rendering form. Please try again.</p>`;
        }
    }

    _getContent() {
        // Helper to generate a validated field wrapper
        const validatedField = (id, label, type = 'text', required = true, minlength = 0, placeholder = '', autocomplete = 'on') => {
            const isPassword = type === 'password';
            const example = placeholder || ({
                email: CommonStrings.emailExample,
                firstName: CommonStrings.firstNameExample,
                lastName: CommonStrings.lastNameExample,
                password: CommonStrings.passwordPlaceholder,
            })[id] || '';

            
            return `
            <div class="form-field-container" data-field="${id}">
                <div class="form-group ${isPassword ? 'password-group' : ''}">
                    <label for="${id}">${label}</label>
                    <div class="input-wrapper">
                        <input 
                            type="${type}" 
                            id="${id}" 
                            name="${id}" 
                            ${required ? 'required' : ''} 
                            ${minlength > 0 ? `minlength="${minlength}"` : ''}
                            ${example ? `placeholder="${example}"` : ''}
                            autocomplete="${autocomplete}"
                            ${type === 'email' ? 'inputmode="email" autocapitalize="none" spellcheck="false"' : ''}
                        >
                        ${isPassword ? `
                        <button type="button" class="btn-icon toggle-password" data-target="${id}" aria-label="${CommonStrings.googlePasswordVisibility}">
                            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="feather feather-eye"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                        </button>
                        ` : ''}
                    </div>
                </div>
                <div class="form-field-error" id="${id}-error"></div>
            </div>
            `;
        };

        const googleAction = this.googleEnabled ? `<button type="button" class="google-button" id="google-start" ${this.isLoading ? 'disabled' : ''}>${GOOGLE_G}<span>${this.isLoading ? CommonStrings.googleOpening : CommonStrings.googleContinue}</span></button><div class="auth-divider">${CommonStrings.emailAlternative}</div>` : '';
        const feedback = this.googleError ? `<div class="auth-feedback" role="alert">${this._googleErrorText()}</div>` : '';
        if (this.currentView === 'google_completing') return `<h2>${CommonStrings.signIn}</h2><p role="status">${CommonStrings.googleCompleting}</p>`;
        if (this.currentView === 'google_mfa') return `<h2>${CommonStrings.signIn}</h2><p>${CommonStrings.googleMfa}</p>${feedback}<form id="google-mfa-form" novalidate>${validatedField('mfa-code', CommonStrings.googleCode, 'text', true)}<button type="submit" class="btn-primary" ${this.isLoading ? 'disabled' : ''}>${CommonStrings.googleVerifyCode}</button></form>`;
        if (this.currentView === 'google_proof') return `<h2>${this.googleResult?.intent === 'unlink' ? CommonStrings.googleUnlink : CommonStrings.googleLink}</h2><p class="auth-subtitle">${this.googleResult?.intent === "unlink" ? CommonStrings.googleUnlinkProof : CommonStrings.googleProof}</p>${feedback}<form id="google-proof-form" novalidate>${validatedField('email', CommonStrings.email, 'email', true, 0, '', 'username')}${validatedField('password', CommonStrings.password, 'password', true, 0, '', 'current-password')}<button type="submit" class="btn-primary" ${this.isLoading ? 'disabled' : ''}>${this.isLoading ? CommonStrings.loading : this.googleResult?.intent === 'unlink' ? CommonStrings.googleUnlink : CommonStrings.googleLink}</button><div class="auth-links"><button type="button" class="btn-link" id="link-forgot">${CommonStrings.forgotPassword}</button><button type="button" class="btn-link" id="google-restart">${CommonStrings.googleRetry}</button></div></form>`;
        if (this.currentView === 'google_profile') return `<h2>${CommonStrings.googleProfile}</h2>${feedback}<form id="google-profile-form" novalidate><div class="form-row">${validatedField('firstName', CommonStrings.firstName, 'text', true, 0, '', 'given-name')}${validatedField('lastName', CommonStrings.lastName, 'text', true, 0, '', 'family-name')}</div><p id="google-profile-email"></p>${this.googleResult?.mailboxRequired ? `<p>${CommonStrings.googleMailbox}</p><button type="button" class="btn-secondary" id="google-send-code">${CommonStrings.googleSendCode}</button>${validatedField('mailbox-code',CommonStrings.googleCode,'text',false)}<button type="button" class="btn-secondary" id="google-verify-code">${CommonStrings.googleVerifyCode}</button>` : ''}<label class="auth-consent"><input type="checkbox" id="google-consent" required><span>${CommonStrings.googleConsent} <a href="${AppConfig.termsUrl}" target="_blank" rel="noopener noreferrer">${CommonStrings.googleTerms}</a> <a href="${AppConfig.privacyUrl}" target="_blank" rel="noopener noreferrer">${CommonStrings.googlePrivacy}</a></span></label><div class="google-profile-actions"><button type="submit" class="btn-primary" ${this.isLoading || this.googleResult?.mailboxRequired ? 'disabled' : ''}>${this.isLoading ? CommonStrings.loading : CommonStrings.googleCreate}</button><button type="button" class="btn-link" id="google-link">${CommonStrings.googleLink}</button></div></form>`;
        if (this.currentView === 'login') {
            return `
                <h2>${CommonStrings.signIn}</h2>
                ${feedback}${googleAction}
                <form id="login-form" novalidate>
                    ${validatedField('email', CommonStrings.email, 'email', true, 0, '', 'username')}
                    ${validatedField('password', CommonStrings.password, 'password', true, 0, '', 'current-password')}
                    <button type="submit" class="btn-primary" ${this.isLoading ? 'disabled' : ''}>
                        ${this.isLoading ? CommonStrings.loading : CommonStrings.signIn}
                    </button>
                    <div class="auth-links">
                        <button type="button" class="btn-link" id="link-forgot">${CommonStrings.forgotPassword}</button>
                    </div>
                </form>
                ${this._isRegistrationEnabled() ? `<div class="auth-switch-footer"><span>${CommonStrings.newAccountPrompt}</span><button type="button" class="btn-link" id="link-register" data-auth-mode="register">${CommonStrings.createAccount}</button></div>` : ''}
            `;
        } else if (this.currentView === 'register') {
             return `
                <h2>${CommonStrings.createAccount}</h2>
                ${feedback}${googleAction}
                <form id="register-form" autocomplete="on" novalidate>
                    ${validatedField('email', CommonStrings.email, 'email', true, 0, '', 'email')}
                    <div class="form-row">
                        <div style="flex:1">
                            ${validatedField('firstName', CommonStrings.firstName, 'text', true, 0, '', 'given-name')}
                        </div>
                         <div style="flex:1">
                            ${validatedField('lastName', CommonStrings.lastName, 'text', true, 0, '', 'family-name')}
                        </div>
                    </div>
                    <button type="submit" class="btn-primary" ${this.isLoading ? 'disabled' : ''}>
                        ${this.isLoading ? CommonStrings.loading : CommonStrings.createAccount}
                    </button>
                </form>
                <div class="auth-switch-footer"><span>${CommonStrings.existingAccountPrompt}</span><button type="button" class="btn-link" data-auth-mode="login">${CommonStrings.signIn}</button></div>
            `;
        } else if (this.currentView === 'reset_password') {
            return `
                <h2>${CommonStrings.newPassword}</h2>
                <div style="font-weight: 500; font-size: 18px; text-align: center; margin-bottom: 24px;">
                    ${CommonStrings.createAPassword}
                </div>
                <form id="reset-password-form" novalidate>
                     <!-- Hidden username field to help browser password managers identify the user -->
                     <input type="text" name="username" autocomplete="username" style="display:none;" aria-hidden="true">
                     ${validatedField('newPassword', CommonStrings.newPassword, 'password', true, 6, '', 'new-password')}
                     <button type="submit" class="btn-primary" ${this.isLoading ? 'disabled' : ''}>
                        ${this.isLoading ? CommonStrings.loading : CommonStrings.changePassword}
                    </button>
                </form>
            `;
        } else if (this.currentView === 'forgot') {
            return `
                <h2>${CommonStrings.resetPassword}</h2>
                <p>${CommonStrings.enterEmail}</p>
                <form id="forgot-form" novalidate>
                    ${validatedField('email', CommonStrings.email, 'email', true)}
                    <button type="submit" class="btn-primary" ${this.isLoading ? 'disabled' : ''}>
                        ${this.isLoading ? CommonStrings.loading : CommonStrings.sendResetEmail}
                    </button>
                    <button type="button" class="btn-secondary" id="btn-back">${CommonStrings.back}</button>
                </form>
            `;
        }
    }

    _attachListeners() {
        const attach = (selector, handler, event = 'click') => {
            // Use authContainer to ensure we find elements inside our specific container
            const el = this.authContainer ? this.authContainer.querySelector(selector) : null;
            if (el) {
                // Remove existing listeners to be safe (though usually new elements)
                el.removeEventListener(event, handler);
                el.addEventListener(event, handler);
            } else {
                console.warn(`LoginModal: Could not find element ${selector} to attach listener`);
            }
        };

        this.authContainer.querySelector('#google-start')?.addEventListener('click', () => this._startGoogle());
        this.authContainer.querySelector('#google-restart')?.addEventListener('click', () => this._startGoogle());
        if (this.currentView === 'google_mfa') {
            attach('#google-mfa-form', e => this._advanceGoogle(e, 'mfa_verify'), 'submit');
        } else if (this.currentView === 'google_proof') {
            const email = this.authContainer.querySelector('#email');
            email.value = this._proofEmail ?? this.googleResult?.email ?? '';
            email.addEventListener('input', () => { this._proofEmail = email.value; });
            attach('#google-proof-form', e => this._advanceGoogle(e, 'prove_existing'), 'submit');
            attach('#link-forgot', () => this._setView('forgot'));
        } else if (this.currentView === 'google_profile') {
            const names = (this.googleResult?.name || '').split(' ');
            this.authContainer.querySelector('#firstName').value = this._profileDraft?.name ?? names.shift() ?? '';
            this.authContainer.querySelector('#lastName').value = this._profileDraft?.surname ?? names.join(' ');
            this.authContainer.querySelector('#google-consent').checked = this._profileDraft?.consent === true;
            this.authContainer.querySelector('#google-profile-email').textContent = this.googleResult?.email || '';
            attach('#google-profile-form', e => this._advanceGoogle(e, 'register'), 'submit');
            attach('#google-link', () => this._setView('google_proof'));
            this.authContainer.querySelector('#google-send-code')?.addEventListener('click', e => this._advanceGoogle(e, 'mailbox_send'));
            this.authContainer.querySelector('#google-verify-code')?.addEventListener('click', e => this._advanceGoogle(e, 'mailbox_verify'));
        }
        this.authContainer.querySelectorAll('[data-auth-mode]').forEach(button => {
            button.addEventListener('click', () => {
                const mode = button.dataset.authMode;
                if (mode === this.currentView) return;
                this._setView(mode);
                this.authContainer.focus();
            });
        });
        if (this.currentView === 'login') {
            attach('#login-form', this._handleLogin, 'submit');
            attach('#link-forgot', (e) => { e.preventDefault(); this._setView('forgot'); });
            
        } 
        else if (this.currentView === 'register') {
            attach('#register-form', this._handleRegister, 'submit');
        }
        else if (this.currentView === 'forgot') {
            attach('#forgot-form', this._handleReset, 'submit');
            attach('#btn-back', (e) => { e.preventDefault(); this._setView(this.googleResult?.status === 'needs_account_proof' ? 'google_proof' : 'login'); });
        }
        else if (this.currentView === 'reset_password') {
            attach('#reset-password-form', this._handleChangePassword, 'submit');
        }
    }
    
    _initPasswordToggles() {
        if (!this.authContainer) return;
        this.authContainer.querySelectorAll('.toggle-password').forEach(btn => {
            btn.removeEventListener('click', this._togglePasswordVisibility);
            btn.addEventListener('click', this._togglePasswordVisibility);
        });
    }
    
    _togglePasswordVisibility(e) {
        e.preventDefault();
        const btn = e.currentTarget;
        const wrapper = btn.closest('.input-wrapper');
        const input = wrapper ? wrapper.querySelector('input') : null;
        
        if (input) {
            const type = input.getAttribute('type') === 'password' ? 'text' : 'password';
            input.setAttribute('type', type);
            
            // Update icon
            if (type === 'text') {
                btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="feather feather-eye-off"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M1 1l22 22"></path><path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"></path></svg>';
            } else {
                btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="feather feather-eye"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>';
            }
        }
    }

    _setView(view) {
        this.currentView = view;
        this._updateContent();
    }
    
    _setLoading(loading) {
        this.isLoading = loading;
        if (!this.authContainer) return;

        const submitBtn = this.authContainer.querySelector('button[type="submit"]');
        if (submitBtn) {
            submitBtn.disabled = loading;
            submitBtn.textContent = loading ? CommonStrings.loading : this._getSubmitButtonLabel();
        }

        const inputs = this.authContainer.querySelectorAll('input');
        inputs.forEach(input => input.disabled = loading);
    }

    _getSubmitButtonLabel() {
        switch (this.currentView) {
            case 'login': return CommonStrings.signIn;
            case 'register': return CommonStrings.createAccount;
            case 'forgot': return CommonStrings.send;
            case 'reset_password': return CommonStrings.changePassword;
            default: return CommonStrings.signIn;
        }
    }

    /* Validation Logic */
    _validateForm(formId) {
        const form = this.authContainer.querySelector('#' + formId);
        if (!form) return false;
        
        let isValid = true;
        const inputs = form.querySelectorAll('input');
        
        // Reset errors
        form.querySelectorAll('.invalid').forEach(el => el.classList.remove('invalid'));
        form.querySelectorAll('.form-field-error').forEach(el => el.style.display = 'none');
        
        inputs.forEach(input => {
             // Skip optional if logic allows, assuming all here are required for now based on 'required' attr
             if (input.hasAttribute('required') && !input.value.trim()) {
                 let msg = CommonStrings.fieldRequired;
                 if (input.type === 'password') {
                     msg = CommonStrings.passwordRequired || msg;
                 } else if (input.type === 'email') {
                     // For email, we might use "Email is required" if available, or just the generic "Invalid" one if that's what we have
                     msg = CommonStrings.emailRequired || msg;
                 }
                 this._showError(input, msg); 
                 isValid = false;
                 return;
             }
             
             // Email
             if (input.type === 'email' && input.value) {
                 const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
                 if (!emailRegex.test(input.value)) {
                     this._showError(input, CommonStrings.invalidEmail);
                     isValid = false;
                 }
             }
             
             // Password Length
             if (input.type === 'password' && input.hasAttribute('minlength')) {
                 const min = parseInt(input.getAttribute('minlength'));
                 if (input.value.length < min) {
                      this._showError(input, (CommonStrings.passwordLength || "Password too short").replace('6', min));
                      isValid = false;
                 }
             }
        });
        
        return isValid;
    }

    _showError(input, message) {
        input.classList.add('invalid');
        // Find wrapper parent if exists (input-wrapper)
        const wrapper = input.closest('.input-wrapper');
        if (wrapper) wrapper.classList.add('invalid');
        
        const container = input.closest('.form-field-container');
        if (container) {
            const errorDiv = container.querySelector('.form-field-error');
            if (errorDiv) {
                errorDiv.textContent = message;
                errorDiv.style.display = 'block';
            }
        }
    }

    async _handleLogin(e) {
        e.preventDefault();
        
        if (!this._validateForm('login-form')) return;
        
        const emailInput = this.authContainer.querySelector('#email');
        const passwordInput = this.authContainer.querySelector('#password');

        if (!emailInput || !passwordInput) {
            console.error("Login inputs not found");
            return;
        }

        const email = emailInput.value;
        const password = passwordInput.value;

        if (!email || !password) return;

        // Apply logic to match flutter: prefix login email with organization id
        const finalEmail = `${AppConfig.organization}+${email}`;

        this._setLoading(true);
        try {
            await AuthService.login(finalEmail, password);
            ToastHelper.showSuccess(CommonStrings.success);
            this.modal.close();
            // Force reload to ensure all components (UserHeader, etc) pick up the new auth state
            window.location.reload(); 
        } catch (err) {
            console.error("Login Error:", err);
            let msg = err.message || CommonStrings.error;
            
            if (msg.includes("Invalid login credentials") || msg.includes("Invalid credentials")) {
                msg = CommonStrings.invalidCredentials;
            }
            
            ToastHelper.showError(msg);
        } finally {
            this._setLoading(false);
        }
    }

    _googleErrorText() {
        if (this.googleError === 'provider_cancelled') return CommonStrings.googleCancelled;
        if (this.googleError === 'attempt_expired') return CommonStrings.googleExpired;
        if (this.googleError === 'account_proof_failed') return CommonStrings.googleProofError;
        return CommonStrings.googleError;
    }

    async _startGoogle() {
        if (this.isLoading) return;
        // Full redirect must not silently discard an in-progress checkout/form.
        const otherForms = [...document.querySelectorAll('form')].filter(form => !this.authContainer.contains(form));
        if (otherForms.some(form => [...form.elements].some(el => el.value && el.type !== 'hidden')) && !window.confirm(CommonStrings.googleLeaveDraft)) return;
        this._proofEmail = null;
        this.isLoading = true; this.googleError = ''; this._updateContent();
        try { await GoogleAuthService.start(); }
        catch (error) { this.googleError = error.message; this.isLoading = false; this._updateContent(); }
    }

    showGoogleResult(result) {
        this.googleResult = result;
        this.googleError = '';
        this.isLoading = false;
        if (result.status === 'authenticated' || result.status === 'unlinked') {
            window.location.replace(result.returnPath || '/');
            return;
        }
        this._setView(result.status === 'needs_mfa' ? 'google_mfa' : result.status === 'needs_profile' ? 'google_profile' : 'google_proof');
        this.authContainer.querySelector('input,button')?.focus();
    }

    async _advanceGoogle(event, operation) {
        event.preventDefault();
        if (this.isLoading) return;
        const value = id => this.authContainer.querySelector(`#${id}`)?.value || '';
        const payload = operation === 'prove_existing' ? { email: value('email'), password: value('password') }
            : operation === 'register' ? { profile: { name: value('firstName'), surname: value('lastName') }, consent: this.authContainer.querySelector('#google-consent').checked }
            : operation === 'mfa_verify' ? { mfaCode: value('mfa-code') } : { mailboxCode: value('mailbox-code') };
        if (this.currentView === 'google_profile') this._profileDraft = { name: value('firstName'), surname: value('lastName'), consent: this.authContainer.querySelector('#google-consent').checked };
        if (operation === 'prove_existing' && !this._validateForm('google-proof-form')) return;
        if (operation === 'register' && (!this._validateForm('google-profile-form') || !payload.consent)) return;
        this.isLoading = true;
        this.authContainer.setAttribute('aria-busy', 'true');
        this.authContainer.querySelectorAll('button').forEach(button => { button.disabled = true; });
        try { this.showGoogleResult(await GoogleAuthService.advance(operation, payload)); }
        catch (error) { this.googleError = error.message; this.isLoading = false; this._updateContent(); }
    }

    async _handleRegister(e) {
        e.preventDefault();
        
        if (!this._validateForm('register-form')) return;
        
        const firstNameInput = this.authContainer.querySelector('#firstName');
        const lastNameInput = this.authContainer.querySelector('#lastName');
        const emailInput = this.authContainer.querySelector('#email');

        const firstName = firstNameInput ? firstNameInput.value : '';
        const lastName = lastNameInput ? lastNameInput.value : '';
        const email = emailInput ? emailInput.value : '';

        this._setLoading(true);
        try {
            // Match Flutter's logic: Flat structure with 'name' and 'surname'
            const data = {
                email,
                name: firstName,
                surname: lastName,
                // Add language if available
                lang: 'cs' // Defaulting to cs as per project context, or derive from LocalizationService
            };
            await AuthService.register(data);
            this._stickyToast = ToastHelper.showSuccess(`${CommonStrings.checkEmail} ${email}`, 0); // 0 = sticky/persistent
            this._setView('login');
        } catch (err) {
            console.error("Register Error:", err);
            let msg = err.message || CommonStrings.error;
            
            // Try to match specific backend errors to localized strings
            if (msg.includes("already in use") || msg.includes("already registered")) {
                msg = CommonStrings.emailInUse.replace("{email}", email);
            } else if (msg.includes("Registration failed")) {
                msg = CommonStrings.registrationFailed;
            }
            
            ToastHelper.showError(msg);
        } finally {
            this._setLoading(false);
        }
    }

    async _handleReset(e) {
        e.preventDefault();
        if (!this._validateForm('forgot-form')) return;

        const emailInput = this.authContainer.querySelector('#email');
        const email = emailInput ? emailInput.value : '';

        this._setLoading(true);
        try {
            await AuthService.resetPasswordForEmail(email);
            this._stickyToast = ToastHelper.showSuccess(`${CommonStrings.passwordResetSent} ${email}`, 0); // 0 = sticky
            this._setView('login');
        } catch (err) {
            console.error("Reset Error:", err);
            ToastHelper.showError(err.message || CommonStrings.error);
        } finally {
            this._setLoading(false);
        }
    }

    async _handleChangePassword(e) {
        e.preventDefault();
        if (!this._validateForm('reset-password-form')) return;

        const output = this.authContainer.querySelector('#newPassword');
        const password = output ? output.value : '';
        
        if (!password || !this._resetToken) return;

        this._setLoading(true);
        try {
            // Service returns { code: 200, email: "..." } or error
            const result = await AuthService.changePassword(this._resetToken, password);

            if (result.code === 200) {
                 // Success -> Auto Login
                 // Prefix logic from AppConfig
                 // Flutter: AuthService.login(AppConfig.getUserPrefix(value["email"]), _passwordController.text);
                 // Web: AppConfig.organization + result.email
                 
                 const email = result.email;
                 // Ensure result.email is valid, otherwise fall back to something or trust it matches what we sent? 
                 // Actually the rpc 'set_user_password_token' returns the user email in 'email' field on success.
                 
                 if (email) {
                    const finalEmail = `${AppConfig.organization}+${email}`;
                    await AuthService.login(finalEmail, password);
                 } else {
                    console.warn("Change password success but no email returned for auto-login.");
                 }

                 ToastHelper.showSuccess(CommonStrings.passwordChanged);
                 this.modal.close();
                 RouterService.openExternalUrl('/', { inCurrentWindow: true });
            } else if (result.code === 403 || result.code === 404) {
                 console.error("Change Password RPC Failed with code:", result.code);
                 throw new Error(CommonStrings.tokenInvalid);
            } else {
                 console.error("Change Password RPC Failed with message:", result.message);
                 throw new Error(result.message || CommonStrings.error);
            }
        } catch (err) {
            console.error("Change Password Error:", err);
            ToastHelper.showError(err.message || CommonStrings.error);
        } finally {
            this._setLoading(false);
        }
    }
}

customElements.define('login-modal', LoginModal);
