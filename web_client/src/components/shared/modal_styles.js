export const SHARED_MODAL_STYLES = `

.auth-container {
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    font-family: var(--font-family, sans-serif);
    position: relative; /* For close button absolute pos */
}

.modal-close-btn {
    position: absolute;
    top: 16px;
    right: 16px;
    color: var(--text-color, #333);
    opacity: 0.5;
    cursor: pointer;
    font-size: 24px;
    z-index: 10;
}
.modal-close-btn:hover {
    opacity: 1;
}
body.dark-mode .modal-close-btn {
    color: var(--text-color-dark, white);
}

.auth-container h2 {
    margin-bottom: 24px;
    text-align: center;
    color: var(--text-color, #1a1a1a);
}

.auth-container p {
    margin-bottom: 16px;
    color: var(--text-secondary, #666);
    text-align: center;
}

.form-group {
    margin-bottom: 16px;
}

.form-row {
    display: flex;
    gap: 16px;
}

.form-row .form-group {
    flex: 1;
}

label {
    display: block;
    margin-bottom: 8px;
    font-weight: 500;
    color: var(--text-color, #333);
}

input {
    width: 100%;
    padding: 10px 12px;
    border: 1px solid var(--border-color, #ddd);
    border-radius: 6px;
    font-size: 16px;
    transition: border-color 0.2s;
    background-color: var(--bg-input, #fff);
    color: var(--text-color, #333);
    box-sizing: border-box;
}

input::placeholder {
    color: var(--text-secondary, #666);
    opacity: 0.75;
}

input:focus {
    border-color: var(--primary-color, #007bff);
    outline: none;
    box-shadow: 0 0 0 2px rgba(0,123,255,0.1);
}

/* Autofill Fix */
input:-webkit-autofill,
input:-webkit-autofill:hover, 
input:-webkit-autofill:focus, 
input:-webkit-autofill:active{
    -webkit-box-shadow: 0 0 0 30px var(--bg-input, #fff) inset !important;
    -webkit-text-fill-color: var(--text-color, #333) !important;
    transition: background-color 5000s ease-in-out 0s; /* Prevent background flash */
}

/* Dark Mode Autofill */
body.dark-mode input:-webkit-autofill,
body.dark-mode input:-webkit-autofill:hover, 
body.dark-mode input:-webkit-autofill:focus, 
body.dark-mode input:-webkit-autofill:active{
    -webkit-box-shadow: 0 0 0 30px var(--bg-input-dark, #333) inset !important;
    -webkit-text-fill-color: var(--text-color-dark, #eee) !important;
}

.btn-primary {
    width: 100%;
    padding: 12px;
    background-color: var(--primary-color, #007bff);
    color: var(--btn-text-color, white);
    border: none;
    border-radius: 6px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    margin-top: 8px;
    transition: background-color 0.2s;
}

.btn-primary:hover {
    background-color: var(--primary-hover, #0056b3);
}

.btn-primary:disabled {
    background-color: var(--disabled-color, #ccc);
    cursor: not-allowed;
}

.btn-secondary {
    width: 100%;
    padding: 12px;
    background-color: transparent;
    color: var(--text-color, #333);
    border: 1px solid var(--border-color, #ddd);
    border-radius: 6px;
    font-size: 16px;
    font-weight: 500;
    cursor: pointer;
    margin-top: 12px;
}

.btn-secondary:hover {
    background-color: var(--bg-hover, #f5f5f5);
}

.auth-links {
    margin-top: 16px;
    display: flex;
    justify-content: center;
    gap: 8px;
    font-size: 14px;
    color: var(--text-secondary, #666);
}

.btn-link {
    background: none;
    border: none;
    padding: 0;
    color: var(--primary-color, #007bff);
    text-decoration: none;
    cursor: pointer;
    font-size: inherit;
    font-family: inherit;
}

.btn-link:hover {
    text-decoration: underline;
}

/* Password Toggle */
.password-group .input-wrapper {
    position: relative;
    display: flex;
    align-items: center;
}

.password-group input {
    padding-right: 40px; /* Space for icon */
}

.toggle-password {
    position: absolute;
    right: 8px;
    background: none;
    border: none;
    cursor: pointer;
    color: var(--text-secondary, #666);
    padding: 4px;
    display: flex;
    align-items: center;
    justify-content: center;
}

.toggle-password:hover {
    color: var(--text-color, #333);
}

/* Dark Mode Overrides */
/* Assuming a class 'dark-mode' on body or generic logic prefers-color-scheme if variables aren't controlled by JS */
/* Dark Mode Overrides */
/* Use class-based selector to respect js toggle */
body.dark-mode .auth-container h2, 
body.dark-mode label, 
body.dark-mode input, 
body.dark-mode .btn-secondary,
body.dark-mode .toggle-password:hover {
    color: var(--text-color-dark, #eee);
}

body.dark-mode .auth-container p,
body.dark-mode .auth-links,
body.dark-mode .toggle-password {
    color: var(--text-secondary-dark, #aaa);
}

body.dark-mode input {
    background-color: var(--bg-input-dark, #333);
    border-color: var(--border-color-dark, #444);
}

body.dark-mode .btn-secondary {
    border-color: var(--border-color-dark, #444);
    color: var(--text-color-dark, #eee);
}

body.dark-mode .btn-secondary:hover {
    background-color: var(--bg-hover-dark, #444);
}

.auth-links span {
    color: #ccc;
}

/* Validation Styles */
.input-wrapper.invalid input,
input.invalid {
    border-color: var(--red-color, #dc3545) !important;
    border-bottom-width: 2px !important;
}

.form-field-error {
    color: var(--red-color, #dc3545);
    font-size: 13px;
    margin-top: 4px;
    display: none;
    font-weight: 500;
    text-align: left;
}

.form-field-container {
    margin-bottom: 16px; 
}
/* Reduce default margin of form-group inside container if needed */
.form-field-container .form-group {
    margin-bottom: 0;
}

/* User Settings / Segmented Controls */
.settings-widget {
    display: flex;
    flex-direction: column;
    gap: 16px;
    width: 100%;
}

.settings-section {
    display: flex;
    flex-direction: column;
    width: 100%;
}

.settings-label {
    font-size: 14px;
    color: inherit;
    margin-bottom: 8px;
    font-weight: 500;
}

.segmented-control {
    display: flex;
    width: 100%;
    background-color: var(--unselected-widget-fill, rgba(0,0,0,0.05));
    border-radius: 8px;
    overflow: hidden;
    border: 1px solid var(--input-border, rgba(0,0,0,0.1));
}

.segmented-btn {
    border: none;
    padding: 8px 16px;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: background-color 0.2s, color 0.2s;
    min-width: 70px;
    color: inherit;
    background-color: transparent;
    border-radius: 0;
    flex: 1;
}

.segmented-btn:not(:first-child) {
    border-left: 1px solid var(--input-border, rgba(0,0,0,0.1));
}

.segmented-btn.active {
    background-color: var(--primary-color, #4465A6);
    color: #ffffff;
}

.segmented-btn:not(.active):hover {
    background-color: rgba(0,0,0,0.05);
}

.version-info {
    font-size: 11px;
    color: inherit;
    opacity: 0.7;
    text-align: center;
    margin-top: 8px;
}
`;
