// Scoped to the existing auth panel; no checkout/global input changes.
export const GOOGLE_G = `<svg aria-hidden="true" width="20" height="20" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6C44.4 38.04 46.98 31.88 46.98 24.55z"/><path fill="#FBBC05" d="M10.53 28.59A14.41 14.41 0 0 1 9.75 24c0-1.59.27-3.13.76-4.59l-7.98-6.19A23.87 23.87 0 0 0 0 24c0 3.87.93 7.53 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.91-5.8l-7.73-6c-2.15 1.45-4.92 2.3-8.18 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>`;
export const GOOGLE_AUTH_STYLES = `
.auth-container { gap: 16px; padding: 24px; }
.auth-container button { min-height:44px; }
.auth-container input:not([type=checkbox]) { min-height:44px; }
.auth-container .toggle-password { min-width:44px; right:0; }
.auth-container h2 { margin: 8px 24px 0; line-height: 1.3; }
.auth-container .auth-subtitle { margin: 0; line-height: 1.5; }
.auth-container .google-button { width: 100%; min-height: 44px; border: 1px solid #747775; border-radius: 6px; background: #fff; color: #1f1f1f; display: flex; justify-content: center; align-items: center; gap: 12px; font: 500 14px var(--font-family, sans-serif); cursor: pointer; padding: 12px 16px; }
body.dark .auth-container .google-button, body.dark-mode .auth-container .google-button { background: #131314; color: #e3e3e3; border-color: #8e918f; }
.auth-container .google-button:hover { box-shadow: 0 1px 3px #0003; }
.auth-container .google-button:disabled { opacity: .65; cursor: wait; }
.auth-container .auth-divider { display: flex; align-items: center; gap: 12px; margin: 0; color: var(--text-secondary); font-size: 14px; }
.auth-container .auth-divider::before, .auth-container .auth-divider::after { content: ''; height: 1px; flex: 1; background: var(--border-color); }
.auth-container button:focus-visible, .auth-container input:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 3px; }
.auth-container button.modal-close-btn { background: transparent; border: 0; min-width: 44px; min-height: 44px; top:8px; right:8px; line-height: 1; font: 24px sans-serif; }
.auth-container .auth-feedback { padding: 12px; border: 1px solid var(--border-color); border-radius: 6px; line-height: 1.5; color: var(--text-color); font-size: 14px; }
.auth-container .auth-consent { display:flex; align-items:flex-start; gap: 8px; margin: 16px 0; line-height: 1.4; font-size: 13px; }
.auth-container .auth-consent input { width: 18px; height: 18px; flex-shrink: 0; }
.auth-container .google-profile-actions { display: flex; flex-direction: column; gap: 12px; }
.auth-container .form-row > * { min-width: 0; }
@media(max-width:390px) { .auth-container { padding: 20px; } .auth-container .form-row { flex-direction: column; gap: 0; } }
@media(prefers-reduced-motion:reduce) { .auth-container * { transition:none !important; } }
`;
