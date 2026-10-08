// Scoped to the existing auth panel; no checkout/global input changes.
export const GOOGLE_G = `<svg aria-hidden="true" width="20" height="20" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6C44.4 38.04 46.98 31.88 46.98 24.55z"/><path fill="#FBBC05" d="M10.53 28.59A14.41 14.41 0 0 1 9.75 24c0-1.59.27-3.13.76-4.59l-7.98-6.19A23.87 23.87 0 0 0 0 24c0 3.87.93 7.53 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.91-5.8l-7.73-6c-2.15 1.45-4.92 2.3-8.18 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>`;
export const GOOGLE_AUTH_STYLES = `
.auth-container { gap: 24px; padding: 36px 32px 24px; }
.auth-container:focus { outline: none; }
.auth-container button { min-height:44px; }
.auth-container input:not([type=checkbox]) { min-height:48px; }
.auth-container .toggle-password { min-width:44px; right:0; }
.auth-container h2 { margin: 0 36px 0 0; line-height: 1.3; font-size: 28px; font-weight: 650; text-align: left; letter-spacing: -.7px; }
.auth-container label { font-size: 14px; font-weight: 500; margin-bottom: 8px; }
.auth-container .form-group, .auth-container .form-field-container { margin-bottom: 0; }
.auth-container h2[tabindex="-1"]:focus { outline: none; }
.auth-container .form-field-error:empty { display: none; }
.auth-container form { display: flex; flex-direction: column; gap: 16px; }
.auth-container .form-row { gap: 12px; }
.auth-container .form-row > div { flex: 1; }
.auth-container input:not([type=checkbox]) { border-radius: 10px; font-size: 16px; }
.auth-container .btn-primary { margin-top: 8px; }
.auth-container .auth-switch-footer { margin: 0 -32px -24px; padding: 16px 24px; border-top: 1px solid var(--border-color, #ddd); display: flex; flex-wrap: wrap; align-items: center; justify-content: center; gap: 4px 8px; font-size: 14px; color: var(--text-secondary, #666); }
.auth-container .auth-switch-footer .btn-link { min-height: 32px; font-weight: 600; }
.auth-container .auth-subtitle { margin: 0; line-height: 1.5; }
.auth-container .google-button { width: 100%; min-height: 44px; border: 1px solid #747775; border-radius: 12px; background: transparent; color: var(--text-color, #1f1f1f); display: flex; justify-content: center; align-items: center; gap: 12px; font: 600 15px var(--font-family, sans-serif); cursor: pointer; padding: 12px 16px; }
body.dark .auth-container .google-button, body.dark-mode .auth-container .google-button { background: transparent; color: var(--text-color-dark, #e3e3e3); border-color: var(--border-color-dark, #696d75); }
.auth-container .btn-primary, .auth-container .btn-secondary, .auth-container .google-button {
    box-sizing: border-box;
    min-height: 48px;
    border-radius: 10px;
    padding: 12px 20px;
    font: 600 15px var(--font-family, sans-serif);
    transition: background-color .15s, box-shadow .15s;
}
body.dark-mode .auth-container input:not([type=checkbox]) { background: #25272b; border-color: #696d75; }
.auth-container .google-button { font-weight: 500; }
.auth-container .btn-primary:hover { background-color: var(--primary-color, #007bff); filter: brightness(1.08); }
.auth-container .btn-link { font: 500 14px var(--font-family, sans-serif); }
.auth-container .google-button:hover { box-shadow: 0 1px 3px #0003; }
.auth-container .google-button:disabled { opacity: .65; cursor: wait; }
.auth-container .auth-divider { display: flex; align-items: center; gap: 12px; margin: 0; color: var(--text-secondary); font-size: 14px; }
.auth-container .auth-divider::before, .auth-container .auth-divider::after { content: ''; height: 1px; flex: 1; background: var(--border-color); }
.auth-container button:focus-visible, .auth-container input:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 3px; }
.auth-container button.modal-close-btn { background: transparent; border: 0; min-width: 44px; min-height: 44px; top:12px; right:12px; line-height: 1; font: 24px sans-serif; }
.auth-container .auth-feedback { padding: 12px; border: 1px solid var(--border-color); border-radius: 6px; line-height: 1.5; color: var(--text-color); font-size: 14px; }
.auth-container .auth-consent { display:flex; align-items:flex-start; gap: 8px; margin: 16px 0; line-height: 1.4; font-size: 13px; }
.auth-container .auth-consent input { width: 18px; height: 18px; flex-shrink: 0; }
.auth-container .google-profile-actions { display: flex; flex-direction: column; gap: 12px; }
.auth-container .auth-links { flex-wrap: wrap; align-items: center; gap: 4px 20px; }
.auth-container .form-row > * { min-width: 0; }
@media(max-width:390px) { .auth-container { padding: 32px 24px 24px; gap: 24px; } .auth-container h2 { font-size: 26px; } .auth-container .auth-switch-footer { margin: 0 -24px -24px; } .auth-container .form-row { flex-direction: column; gap: 16px; } }
@media(prefers-reduced-motion:reduce) { .auth-container * { transition:none !important; } }
`;
