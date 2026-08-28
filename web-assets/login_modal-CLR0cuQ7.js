import{AuthService as c}from"./auth_service-Bycevz_n.js";import{R as g,e as f,C as s,A as u,d as p}from"./index-BxGoqAKg.js";import{ToastHelper as h}from"./toast-C66ajYTo.js";class w extends HTMLElement{constructor(){super(),this.attachShadow({mode:"open"})}connectedCallback(){this.render()}render(){const e=`
            :host {
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                z-index: 10000;
                display: flex;
                align-items: center;
                justify-content: center;
                opacity: 0;
                visibility: hidden;
                transition: opacity 0.3s ease, visibility 0.3s;
            }
            :host(.open) {
                opacity: 1;
                visibility: visible;
            }
            .backdrop {
                position: absolute;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.5);
                backdrop-filter: blur(4px);
            }
            .modal-content {
                position: relative;
                background: var(--bg-color, #fff); /* Fallback or theme var */
                width: 90%;
                max-width: 400px; /* Default max width */
                border-radius: 12px;
                box-shadow: 0 4px 20px rgba(0,0,0,0.2);
                z-index: 1;
                max-height: 90vh;
                overflow-y: auto;
                display: flex;
                flex-direction: column;
                transform: scale(0.9);
                transition: transform 0.3s cubic-bezier(0.18, 0.89, 0.32, 1.28);
            }
            :host(.open) .modal-content {
                transform: scale(1);
            }
            /* Dark mode support if parent has dark theme */
            /* Dark mode support: rely on body class, not media query directly */
            :host-context(body.dark) .modal-content,
            :host-context(body.dark-mode) .modal-content {
                background: #1e1e1e;
                color: white;
            }
        `;this.shadowRoot.innerHTML=`
            <style>${e}</style>
            <div class="backdrop"></div>
            <div class="modal-content">
                <slot></slot>
            </div>
        `,this.shadowRoot.querySelector(".backdrop").addEventListener("click",()=>{this.close()})}open(){document.body.appendChild(this),this.offsetHeight,this.classList.add("open"),this.setAttribute("open",""),document.body.style.overflow="hidden"}close(){this.classList.remove("open"),this.removeAttribute("open"),document.body.style.overflow="",setTimeout(()=>{this.parentNode&&this.parentNode.removeChild(this)},300)}}customElements.define("app-modal",w);const b=f;class y extends HTMLElement{constructor(){super(),this.currentView="login",this.isLoading=!1,this._render=this._render.bind(this),this._handleReset=this._handleReset.bind(this),this._handleChangePassword=this._handleChangePassword.bind(this),this._togglePasswordVisibility=this._togglePasswordVisibility.bind(this),this._handleLogin=this._handleLogin.bind(this),this._handleRegister=this._handleRegister.bind(this)}_isRegistrationEnabled(){const e=g.context?.organization;return e&&typeof e.IS_REGISTRATION_ENABLED=="boolean"?e.IS_REGISTRATION_ENABLED:!0}set resetToken(e){this._resetToken=e,e&&this._setView("reset_password")}connectedCallback(){this._handleKeyDown=this._handleKeyDown.bind(this),window.addEventListener("keydown",this._handleKeyDown),this._render()}disconnectedCallback(){window.removeEventListener("keydown",this._handleKeyDown)}_handleKeyDown(e){e.key==="Escape"&&this.modal&&this.modal.close()}_render(){this.innerHTML=`<style>${b}</style>`,this.modal=document.createElement("app-modal"),this.authContainer=document.createElement("div"),this.authContainer.className="auth-container",this.modal.appendChild(this.authContainer),this.appendChild(this.modal),this.modal.open(),this._updateContent();const e=this.modal.close.bind(this.modal);this.modal.close=()=>{this._resetToken||this.currentView==="reset_password"||(this._stickyToast&&(this._stickyToast.hide(),this._stickyToast=null),e(),setTimeout(()=>{this.parentNode&&this.parentNode.removeChild(this)},300))}}_updateContent(){if(this.authContainer)try{if(this.authContainer.innerHTML=this._getContent(),!(this._resetToken||this.currentView==="reset_password")){const t=document.createElement("i");t.className="material-icons modal-close-btn",t.textContent="close",t.onclick=()=>this.modal.close(),this.authContainer.appendChild(t)}this._attachListeners(),this._initPasswordToggles()}catch(e){console.error("LoginModal render error:",e),this.authContainer.innerHTML='<p class="error">Error rendering form. Please try again.</p>'}}_getContent(){const e=(t,o,r="text",i=!0,n=0,l="",a="on")=>{const d=r==="password";return`
            <div class="form-field-container" data-field="${t}">
                <div class="form-group ${d?"password-group":""}">
                    <label for="${t}">${o}</label>
                    <div class="input-wrapper">
                        <input 
                            type="${r}" 
                            id="${t}" 
                            name="${t}" 
                            ${i?"required":""} 
                            ${n>0?`minlength="${n}"`:""}
                            ${l?`placeholder="${l}"`:""}
                            autocomplete="${a}"
                        >
                        ${d?`
                        <button type="button" class="btn-icon toggle-password" data-target="${t}" aria-label="Toggle password visibility">
                            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="feather feather-eye"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                        </button>
                        `:""}
                    </div>
                </div>
                <div class="form-field-error" id="${t}-error"></div>
            </div>
            `};if(this.currentView==="login")return`
                <h2>${s.signIn}</h2>
                <form id="login-form" novalidate>
                    ${e("email",s.email,"email",!0,0,"","username")}
                    ${e("password",s.password,"password",!0,0,"","current-password")}
                    <button type="submit" class="btn-primary" ${this.isLoading?"disabled":""}>
                        ${this.isLoading?s.loading:s.signIn}
                    </button>
                    <div class="auth-links">
                        <button type="button" class="btn-link" id="link-forgot">${s.forgotPassword}</button>
                        ${this._isRegistrationEnabled()?`
                        <span>|</span>
                        <button type="button" class="btn-link" id="link-register">${s.signUp}</button>
                        `:""}
                    </div>
                </form>
            `;if(this.currentView==="register")return`
                <h2>${s.signUp}</h2>
                <form id="register-form" novalidate>
                    ${e("email",s.email,"email",!0,0,"","email")}
                    <div class="form-row">
                        <div style="flex:1">
                            ${e("firstName",s.firstName,"text",!0,0,"","given-name")}
                        </div>
                         <div style="flex:1">
                            ${e("lastName",s.lastName,"text",!0,0,"","family-name")}
                        </div>
                    </div>
                    <button type="submit" class="btn-primary" ${this.isLoading?"disabled":""}>
                        ${this.isLoading?s.loading:s.signUp}
                    </button>
                    <button type="button" class="btn-secondary" id="btn-back">${s.back}</button>
                </form>
            `;if(this.currentView==="reset_password")return`
                <h2>${s.newPassword}</h2>
                <div style="font-weight: 500; font-size: 18px; text-align: center; margin-bottom: 24px;">
                    ${s.createAPassword}
                </div>
                <form id="reset-password-form" novalidate>
                     <!-- Hidden username field to help browser password managers identify the user -->
                     <input type="text" name="username" autocomplete="username" style="display:none;" aria-hidden="true">
                     ${e("newPassword",s.newPassword,"password",!0,6,"","new-password")}
                     <button type="submit" class="btn-primary" ${this.isLoading?"disabled":""}>
                        ${this.isLoading?s.loading:s.changePassword}
                    </button>
                </form>
            `;if(this.currentView==="forgot")return`
                <h2>${s.resetPassword}</h2>
                <p>${s.enterEmail}</p>
                <form id="forgot-form" novalidate>
                    ${e("email",s.email,"email",!0)}
                    <button type="submit" class="btn-primary" ${this.isLoading?"disabled":""}>
                        ${this.isLoading?s.loading:s.sendResetEmail}
                    </button>
                    <button type="button" class="btn-secondary" id="btn-back">${s.back}</button>
                </form>
            `}_attachListeners(){const e=(t,o,r="click")=>{const i=this.authContainer?this.authContainer.querySelector(t):null;i?(i.removeEventListener(r,o),i.addEventListener(r,o)):console.warn(`LoginModal: Could not find element ${t} to attach listener`)};this.currentView==="login"?(e("#login-form",this._handleLogin,"submit"),e("#link-forgot",t=>{t.preventDefault(),this._setView("forgot")}),this._isRegistrationEnabled()&&e("#link-register",t=>{t.preventDefault(),this._setView("register")})):this.currentView==="register"?(e("#register-form",this._handleRegister,"submit"),e("#btn-back",t=>{t.preventDefault(),this._setView("login")})):this.currentView==="forgot"?(e("#forgot-form",this._handleReset,"submit"),e("#btn-back",t=>{t.preventDefault(),this._setView("login")})):this.currentView==="reset_password"&&e("#reset-password-form",this._handleChangePassword,"submit")}_initPasswordToggles(){this.authContainer&&this.authContainer.querySelectorAll(".toggle-password").forEach(e=>{e.removeEventListener("click",this._togglePasswordVisibility),e.addEventListener("click",this._togglePasswordVisibility)})}_togglePasswordVisibility(e){e.preventDefault();const t=e.currentTarget,o=t.closest(".input-wrapper"),r=o?o.querySelector("input"):null;if(r){const i=r.getAttribute("type")==="password"?"text":"password";r.setAttribute("type",i),i==="text"?t.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="feather feather-eye-off"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M1 1l22 22"></path><path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"></path></svg>':t.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="feather feather-eye"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>'}}_setView(e){this.currentView=e,this._updateContent()}_setLoading(e){if(this.isLoading=e,!this.authContainer)return;const t=this.authContainer.querySelector('button[type="submit"]');t&&(t.disabled=e,t.textContent=e?s.loading:this._getSubmitButtonLabel()),this.authContainer.querySelectorAll("input").forEach(r=>r.disabled=e)}_getSubmitButtonLabel(){switch(this.currentView){case"login":return s.signIn;case"register":return s.signUp;case"forgot":return s.send;case"reset_password":return s.changePassword;default:return s.signIn}}_validateForm(e){const t=this.authContainer.querySelector("#"+e);if(!t)return!1;let o=!0;const r=t.querySelectorAll("input");return t.querySelectorAll(".invalid").forEach(i=>i.classList.remove("invalid")),t.querySelectorAll(".form-field-error").forEach(i=>i.style.display="none"),r.forEach(i=>{if(i.hasAttribute("required")&&!i.value.trim()){let n=s.fieldRequired;i.type==="password"?n=s.passwordRequired||n:i.type==="email"&&(n=s.emailRequired||n),this._showError(i,n),o=!1;return}if(i.type==="email"&&i.value&&(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(i.value)||(this._showError(i,s.invalidEmail),o=!1)),i.type==="password"&&i.hasAttribute("minlength")){const n=parseInt(i.getAttribute("minlength"));i.value.length<n&&(this._showError(i,(s.passwordLength||"Password too short").replace("6",n)),o=!1)}}),o}_showError(e,t){e.classList.add("invalid");const o=e.closest(".input-wrapper");o&&o.classList.add("invalid");const r=e.closest(".form-field-container");if(r){const i=r.querySelector(".form-field-error");i&&(i.textContent=t,i.style.display="block")}}async _handleLogin(e){if(e.preventDefault(),!this._validateForm("login-form"))return;const t=this.authContainer.querySelector("#email"),o=this.authContainer.querySelector("#password");if(!t||!o){console.error("Login inputs not found");return}const r=t.value,i=o.value;if(!r||!i)return;const n=`${u.organization}+${r}`;this._setLoading(!0);try{await c.login(n,i),h.showSuccess(s.success),this.modal.close(),window.location.reload()}catch(l){console.error("Login Error:",l);let a=l.message||s.error;(a.includes("Invalid login credentials")||a.includes("Invalid credentials"))&&(a=s.invalidCredentials),h.showError(a)}finally{this._setLoading(!1)}}async _handleRegister(e){if(e.preventDefault(),!this._validateForm("register-form"))return;const t=this.authContainer.querySelector("#firstName"),o=this.authContainer.querySelector("#lastName"),r=this.authContainer.querySelector("#email"),i=t?t.value:"",n=o?o.value:"",l=r?r.value:"";this._setLoading(!0);try{const a={email:l,name:i,surname:n,lang:"cs"};await c.register(a),this._stickyToast=h.showSuccess(`${s.checkEmail} ${l}`,0),this._setView("login")}catch(a){console.error("Register Error:",a);let d=a.message||s.error;d.includes("already in use")||d.includes("already registered")?d=s.emailInUse.replace("{email}",l):d.includes("Registration failed")&&(d=s.registrationFailed),h.showError(d)}finally{this._setLoading(!1)}}async _handleReset(e){if(e.preventDefault(),!this._validateForm("forgot-form"))return;const t=this.authContainer.querySelector("#email"),o=t?t.value:"";this._setLoading(!0);try{await c.resetPasswordForEmail(o),this._stickyToast=h.showSuccess(`${s.passwordResetSent} ${o}`,0),this._setView("login")}catch(r){console.error("Reset Error:",r),h.showError(r.message||s.error)}finally{this._setLoading(!1)}}async _handleChangePassword(e){if(e.preventDefault(),!this._validateForm("reset-password-form"))return;const t=this.authContainer.querySelector("#newPassword"),o=t?t.value:"";if(!(!o||!this._resetToken)){this._setLoading(!0);try{const r=await c.changePassword(this._resetToken,o);if(r.code===200){const i=r.email;if(i){const n=`${u.organization}+${i}`;await c.login(n,o)}else console.warn("Change password success but no email returned for auto-login.");h.showSuccess(s.passwordChanged),this.modal.close(),p.openExternalUrl("/",{inCurrentWindow:!0})}else throw r.code===403||r.code===404?(console.error("Change Password RPC Failed with code:",r.code),new Error(s.tokenInvalid)):(console.error("Change Password RPC Failed with message:",r.message),new Error(r.message||s.error))}catch(r){console.error("Change Password Error:",r),h.showError(r.message||s.error)}finally{this._setLoading(!1)}}}}customElements.define("login-modal",y);export{y as LoginModal};
