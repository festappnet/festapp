import { RouterService } from '../../services/router_service.js';
import { CommonStrings } from '../shared/common_strings.js';
import './user_header.css';
import { RightsService } from '../../services/rights_service.js';
import { SupabaseService } from '../../services/supabase_service.js';
import { AppConfig } from '../../app_config.js';

import { SHARED_MODAL_STYLES } from '../shared/modal_styles.js';

export class UserHeader extends HTMLElement {
    constructor() {
        super();
        this.user = null;
        this.context = null;
        this._handleContextChange = this._handleContextChange.bind(this);
    }

    connectedCallback() {
        // Initial render (empty or skeleton?)
        this.innerHTML = ''; 
        
        // Listen to context changes
        RightsService.addListener(this._handleContextChange);

        // Scroll Behavior
        this.lastScrollY = window.scrollY;
        // Bind the RAF handler once
        this._onScroll = this._onScroll.bind(this);
        this.ticking = false;
        
        window.addEventListener('scroll', this._onScroll, { passive: true });
        
        // Main owns backend activation and the initial rights fetch. Starting a
        // request from custom-element upgrade would race Supabase initialization
        // and could pin this process to the legacy writer during cutover.
    }

    disconnectedCallback() {
        RightsService.removeListener(this._handleContextChange);
        window.removeEventListener('scroll', this._onScroll);
    }

    _handleContextChange(context) {
        this.context = context;
        this.user = RightsService.currentUser;
        this.render();
    }

    _onScroll() {
        if (!this.ticking) {
            window.requestAnimationFrame(() => {
                this._updateScrollState();
                this.ticking = false;
            });
            this.ticking = true;
        }
    }

    _updateScrollState() {
        const currentScrollY = window.scrollY;
        
        // Threshold
        if (currentScrollY < 10) {
            if (this.classList.contains('header-hidden')) {
                this.classList.remove('header-hidden');
            }
            this.lastScrollY = currentScrollY;
            return;
        }

        // Scroll Down -> Hide
        if (currentScrollY > this.lastScrollY) {
             if (!this.classList.contains('header-hidden')) {
                 this.classList.add('header-hidden');
                 // Also close popover if open when scrolling down (hiding)
                 const wrapper = this.querySelector('#user-popover-wrapper');
                 if (wrapper) wrapper.remove();
             }
        } 
        // Scroll Up -> Show
        else {
             if (this.classList.contains('header-hidden')) {
                 this.classList.remove('header-hidden');
             }
        }
        
        this.lastScrollY = currentScrollY;
    }



    render() {
        this.innerHTML = '';

        const container = document.createElement('div');
        container.className = 'user-header-container';

        // Logo
        const logo = document.createElement('img');
        logo.src = 'assets/icons/fstapplogo.svg'; 
        logo.alt = 'Logo';
        logo.className = 'header-logo';
        // Force height via inline style to beat any CSS loading issues or specificity wars
        logo.style.height = '56px';
        logo.style.cursor = 'pointer';
        logo.onclick = () => {
             // Force redirect to root
             RouterService.openExternalUrl("/", { inCurrentWindow: true });
        };
        container.appendChild(logo);

        // SEO: Hidden H1
        const h1 = document.createElement('h1');
        h1.textContent = AppConfig.appName;
        h1.style.position = 'absolute';
        h1.style.width = '1px';
        h1.style.height = '1px';
        h1.style.padding = '0';
        h1.style.margin = '-1px';
        h1.style.overflow = 'hidden';
        h1.style.clip = 'rect(0, 0, 0, 0)';
        h1.style.whiteSpace = 'nowrap';
        h1.style.border = '0';
        container.appendChild(h1);

        // ... existing actions ...


        const actions = document.createElement('div');
        actions.className = 'header-actions';
        
        // If context isn't loaded yet, don't show anything here to avoid blinking "Sign In"
        // RightsService.context is null initially.
        if (!this.context && !this.user) {
             // Maybe show a small spinner or just nothing?
             // User requested "don't show sign in button until correct request is done".
             // So rendering nothing in actions is correct.
        } else if (this.user && this.user.id) {
             // ... Authenticated Logic ...
             const userInfo = RightsService.getUserDisplayInfo(this.user);

             // 1. Admin Button (if applicable)
             const canSeeAdmin = RightsService.canSeeAdmin();
             const canSeeReservations = RightsService.canSeeReservations();
             
             if (canSeeAdmin || canSeeReservations) {
                 const adminBtn = document.createElement('button');
                 adminBtn.className = 'btn-admin';
                 adminBtn.innerHTML = `<i class="material-icons">admin_panel_settings</i><span class="admin-text">${CommonStrings.admin}</span>`;
                 adminBtn.onclick = () => RouterService.navigateToAdmin(
                     RightsService.currentLink || '',
                 );
                 actions.appendChild(adminBtn);
             }

             // 2. User Info (Avatar)
             const userContainer = document.createElement('div');
             userContainer.className = 'user-info-container';
             
             const avatar = document.createElement('div');
             avatar.className = 'avatar-circle';
             
             avatar.textContent = userInfo.initial;
             
             userContainer.appendChild(avatar);
             
             // Popover interaction
             userContainer.onclick = (e) => {
                 e.stopPropagation();
                 this.togglePopover(userContainer);
             };

             actions.appendChild(userContainer);
             
        } else {
            // Guest -> Sign In Button
            // Only show if we confirm we are NOT logged in (context exists but user is null)
            const signInBtn = document.createElement('button');
            signInBtn.className = 'btn-sign-in';
            // Use innerHTML to include icon and text span for responsive hiding
            signInBtn.innerHTML = `<i class="material-icons">person</i><span class="sign-in-text">${CommonStrings.signIn}</span>`;
            signInBtn.onclick = (e) => {
                e.preventDefault();
                import('./login_modal.js').then(() => {
                    const modal = document.createElement('login-modal');
                    document.body.appendChild(modal);
                });
            };
            actions.appendChild(signInBtn);

            // Settings Icon (for guests)
            const settingsBtn = document.createElement('i');
            settingsBtn.className = 'material-icons settings-icon-btn';
            settingsBtn.textContent = 'settings';
            settingsBtn.onclick = (e) => {
                e.stopPropagation();
                this.togglePopover(settingsBtn);
            };
            actions.appendChild(settingsBtn);
        }

        container.appendChild(actions);
        this.appendChild(container); // Append once
    }
    
    togglePopover(target) {
        let wrapper = document.getElementById('user-popover-wrapper');
        
        // If it exists and is open, close it (toggle behavior)
        if (wrapper) {
            wrapper.remove();
            return;
        }

        wrapper = document.createElement('div');
        wrapper.id = 'user-popover-wrapper';
        
        // --- Backdrop ---
        const backdrop = document.createElement('div');
        backdrop.className = 'popover-backdrop';
        // Close when clicking backdrop
        backdrop.onclick = (e) => {
            e.stopPropagation(); // Prevent bubbling to document
            wrapper.remove();
        };
        wrapper.appendChild(backdrop);

        const popover = document.createElement('div');
        popover.id = 'user-popover';
        popover.className = 'user-popover';

        // --- Close Button ---
        const closeBtn = document.createElement('i');
        closeBtn.className = 'material-icons popover-close-btn';
        closeBtn.textContent = 'close';
        closeBtn.onclick = () => wrapper.remove();
        popover.appendChild(closeBtn);

        // --- User Header Section (Avatar + Info) ---
        if (this.user && this.user.id) {
            const userInfo = RightsService.getUserDisplayInfo(this.user);

            const headerSection = document.createElement('div');
            headerSection.className = 'popover-header-section';

            // Large Avatar
            const avatar = document.createElement('div');
            avatar.className = 'popover-avatar-large';
            avatar.textContent = userInfo.initial;
            headerSection.appendChild(avatar);

            // Name
            if (userInfo.name) {
                const nameDiv = document.createElement('div');
                nameDiv.className = 'popover-user-name';
                nameDiv.textContent = userInfo.name;
                headerSection.appendChild(nameDiv);
            }

            // Email
            const emailDiv = document.createElement('div');
            emailDiv.className = 'popover-user-email';
            emailDiv.textContent = userInfo.email;
            headerSection.appendChild(emailDiv);

            popover.appendChild(headerSection);
            
            // Divider
            const hr = document.createElement('div');
            hr.className = 'popover-divider';
            popover.appendChild(hr);
        }

        // --- Settings Section ---
        const settingsContainer = document.createElement('div');
        settingsContainer.className = 'popover-settings-container';
        popover.appendChild(settingsContainer);
        
        import('../forms/widgets/settings_widget.js').then(({ SettingsWidget }) => {
            new SettingsWidget(settingsContainer);
        });

        // --- Logout Section ---
        if (this.user && this.user.id) {
            // Divider
            const hr = document.createElement('div');
            hr.className = 'popover-divider';
            popover.appendChild(hr);
            
            const logoutRow = document.createElement('div');
            logoutRow.className = 'popover-logout-row';
            logoutRow.onclick = async () => {
                 const { AuthService } = await import('../../services/auth_service.js'); 
                 await AuthService.logout();
                 wrapper.remove();
             };

            const logoutIcon = document.createElement('i');
            logoutIcon.className = 'material-icons logout-icon';
            logoutIcon.textContent = 'logout';
            
            const logoutText = document.createElement('span');
            logoutText.textContent = CommonStrings.signOut;
            
            logoutRow.appendChild(logoutIcon);
            logoutRow.appendChild(logoutText);
            
            popover.appendChild(logoutRow);
        }
        
        // Position
        const rect = target.getBoundingClientRect();
        
        if (window.innerWidth < 600) {
            popover.style.position = 'fixed';
            popover.style.top = '72px';
            popover.style.left = '50%';
            popover.style.transform = 'translateX(-50%)'; 
            popover.style.width = '90%';
            popover.style.maxWidth = '360px';
        } else {
             // Desktop: Anchor to the target
             const headerRect = this.getBoundingClientRect();
             const targetRect = target.getBoundingClientRect();
             const rightOffset = headerRect.right - targetRect.right;
             
             popover.style.position = 'absolute';
             popover.style.top = 'calc(100% + 2px)'; 
             popover.style.right = Math.max(16, rightOffset) + 'px'; 
        }

        wrapper.appendChild(popover);
        // ESC Key Handler
        const escHandler = (e) => {
            if (e.key === 'Escape') {
                wrapper.remove();
                // Listener removed automatically since wrapper is gone? No.
                document.removeEventListener('keydown', escHandler);
            }
        };
        document.addEventListener('keydown', escHandler);

        // Update close button to also remove listener
        const originalRemove = wrapper.remove.bind(wrapper);
        wrapper.remove = () => {
             document.removeEventListener('keydown', escHandler);
             originalRemove();
        };

        // Inject Shared Styles
        const style = document.createElement('style');
        style.textContent = SHARED_MODAL_STYLES;
        wrapper.appendChild(style);

        this.appendChild(wrapper);

        // Global click listener to close if clicked outside (redundant with backdrop but good fallback)
        const closeHandler = (e) => {
             // If wrapper is gone, remove listener
             if (!document.getElementById('user-popover-wrapper')) {
                 document.removeEventListener('click', closeHandler);
                 return;
             }
        };
        // setTimeout(() => document.addEventListener('click', closeHandler), 10);
    }
}

customElements.define('user-header', UserHeader);
