import { ACCOUNT_CONNECTIONS_PATH } from './account_connections_links.js';
import { isEmbed } from '../../services/embed_context.js';
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
        if (isEmbed()) { this.hidden = true; return; }
        // Moving the same header between the app and an overview reconnects it.
        // Keep its rendered navigation; rights updates own subsequent rendering.
        
        // Listen to context changes
        RightsService.addListener(this._handleContextChange);
        // A header can mount after startup has already published account data.
        // Read that completed snapshot without fetching or replacing unchanged
        // navigation when an existing header is merely moved in the DOM.
        if (RightsService.context && this.context !== RightsService.context) {
            this._handleContextChange(RightsService.context);
        }


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
        this.querySelector('#user-popover-wrapper')?.remove();
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
        this.querySelector('#user-popover-wrapper')?.remove();
        this.innerHTML = '';

        const container = document.createElement('div');
        container.className = 'user-header-container';

        // Logo
        const ticketBrand = new URL(AppConfig.webLink).hostname === 'vstupenky.online';
        const logo = document.createElement(ticketBrand ? 'span' : 'img');
        if (ticketBrand) {
            logo.className = 'header-wordmark';
            logo.textContent = 'vstupenky.online';
        } else {
            logo.src = '/brand-logo.svg';
            logo.alt = AppConfig.appName;
            logo.className = 'header-logo';
            logo.style.height = '56px';
        }
        logo.style.cursor = 'pointer';
        const homeLink = document.createElement('a');
        homeLink.href = '/';
        homeLink.className = 'header-home-link';
        homeLink.appendChild(logo);
        container.appendChild(homeLink);

        // SEO: Hidden H1
        const introduction = document.getElementById('site-introduction');
        const h1 = document.createElement(document.body.dataset.page === 'organizers' || (window.location.pathname === '/' && introduction && !introduction.hidden) ? 'span' : 'h1');
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
        if (this.hasAttribute('data-marketing') && new URL(AppConfig.webLink).hostname === 'vstupenky.online') {
            const help = document.createElement('a');
            help.className = 'header-help'; help.href = '/napoveda/'; help.textContent = 'Nápověda';
            actions.appendChild(help);
        }
        
        // If context isn't loaded yet, don't show anything here to avoid blinking "Sign In"
        // RightsService.context is null initially.
        if (!this.context && !this.user) {
             // Maybe show a small spinner or just nothing?
             // User requested "don't show sign in button until correct request is done".
             // So rendering nothing in actions is correct.
        } else if (this.user && this.user.id) {
             // ... Authenticated Logic ...
             const userInfo = RightsService.getUserDisplayInfo(this.user);

             // My events is account navigation on the ticketing site. Opening
             // it does not grant access to any unit or occasion; the destination
             // resolves the signed-in workspace and checks its own capabilities.
             const canOpenMyEvents = ticketBrand ||
                 RightsService.canSeeAdmin() || RightsService.canSeeReservations();
             if (canOpenMyEvents) {
                 const adminBtn = document.createElement('button');
                 adminBtn.className = 'btn-admin';
                 adminBtn.setAttribute('aria-label', CommonStrings.myEvents);
                 adminBtn.title = CommonStrings.myEvents;
                 adminBtn.innerHTML = `<i class="material-icons" aria-hidden="true">grid_view</i><span class="admin-text">${CommonStrings.myEvents}</span>`;
                 adminBtn.onclick = () => RouterService.navigateToAdmin();
                 actions.appendChild(adminBtn);
             }

             // 2. User Info (Avatar)
             const userContainer = document.createElement('button');
             userContainer.type = 'button';
             userContainer.className = 'user-info-container';
             userContainer.setAttribute('aria-label', CommonStrings.settings);
             userContainer.setAttribute('aria-haspopup', 'dialog');
             userContainer.setAttribute('aria-expanded', 'false');
             userContainer.setAttribute('aria-controls', 'user-popover');
             
             const avatar = document.createElement('span');
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
            if (new URL(AppConfig.webLink).hostname === 'vstupenky.online' &&
                RightsService.context?.organization?.IS_REGISTRATION_ENABLED === true) {
                const addEventBtn = document.createElement('button');
                addEventBtn.type = 'button';
                addEventBtn.className = 'btn-add-event';
                addEventBtn.setAttribute('aria-label', CommonStrings.addEvent);
                const fullLabel = document.createElement('span');
                fullLabel.className = 'add-event-full';
                fullLabel.textContent = CommonStrings.addEvent;
                const shortLabel = document.createElement('span');
                shortLabel.className = 'add-event-short';
                shortLabel.textContent = CommonStrings.addEventShort;
                shortLabel.setAttribute('aria-hidden', 'true');
                addEventBtn.append(fullLabel, shortLabel);
                addEventBtn.onclick = async () => {
                    if (this.hasAttribute('data-marketing')) {
                        window.location.assign('/login');
                        return;
                    }
                    await import('./login_modal.js');
                    const modal = document.createElement('login-modal');
                    modal.currentView = 'register';
                    document.body.appendChild(modal);
                };
                actions.appendChild(addEventBtn);
            }

            // Guest -> Sign In Button
            // Only show if we confirm we are NOT logged in (context exists but user is null)
            const signInBtn = document.createElement('button');
            signInBtn.className = 'btn-sign-in';
            signInBtn.setAttribute('aria-label', CommonStrings.signIn);
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
            const settingsBtn = document.createElement('button');
            settingsBtn.type = 'button';
            settingsBtn.setAttribute('aria-label', CommonStrings.settings);
            settingsBtn.setAttribute('aria-haspopup', 'dialog');
            settingsBtn.setAttribute('aria-expanded', 'false');
            settingsBtn.setAttribute('aria-controls', 'user-popover');
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
        popover.setAttribute('role', 'dialog');
        popover.setAttribute('aria-label', CommonStrings.settings);
        target.setAttribute('aria-expanded', 'true');

        // --- Close Button ---
        const closeBtn = document.createElement('button');
        closeBtn.type = 'button';
        closeBtn.setAttribute('aria-label', CommonStrings.close);
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
            const avatar = document.createElement('span');
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

            const accountActions = document.createElement('div');
            popover.appendChild(accountActions);
            const connections = document.createElement('a');
            connections.href = ACCOUNT_CONNECTIONS_PATH;
            connections.target = '_blank';
            connections.rel = 'noopener noreferrer';
            connections.className = 'popover-logout-row popover-account-action popover-account-connections';
            const connectionsIcon = document.createElement('i');
            connectionsIcon.className = 'material-icons';
            connectionsIcon.setAttribute('aria-hidden', 'true');
            connectionsIcon.textContent = 'extension';
            const connectionsLabel = document.createElement('span');
            connectionsLabel.textContent = CommonStrings.accountConnections;
            connections.append(connectionsIcon, connectionsLabel);
            accountActions.appendChild(connections);
            const userId = this.user.id;
            const organizationId = Number(AppConfig.organization);
            if (Number.isSafeInteger(organizationId) && organizationId > 0) {
                // Organization administration is distinct from occasion/unit rights.
                // Recheck on every open and ignore results from an old identity/menu.
                Promise.resolve().then(() => SupabaseService.getClient().rpc(
                    'check_is_admin_of_organization', { organization_id: organizationId },
                )).then(({ data, error }) => {
                    if (error || data !== true || !wrapper.isConnected ||
                        this.user?.id !== userId || RightsService.currentUser?.id !== userId ||
                        Number(AppConfig.organization) !== organizationId) return;
                    const action = document.createElement('button');
                    action.type = 'button';
                    action.className = 'popover-logout-row popover-account-action popover-organization-settings';
                    const icon = document.createElement('i');
                    icon.className = 'material-icons';
                    icon.setAttribute('aria-hidden', 'true');
                    icon.textContent = 'business';
                    const label = document.createElement('span');
                    label.textContent = CommonStrings.organizationSettings;
                    action.append(icon, label);
                    action.onclick = async () => {
                        wrapper.remove();
                        await RouterService.navigateToFlutterRoute(`/organizationEdit/${organizationId}`);
                    };
                    accountActions.prepend(action);
                }).catch(() => {});
            }
            const logoutRow = document.createElement('button');
            logoutRow.type = 'button';
            logoutRow.className = 'popover-logout-row popover-account-action';
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
             target.setAttribute('aria-expanded', 'false');
             if (target.isConnected) target.focus();
        };

        // Inject Shared Styles
        const style = document.createElement('style');
        style.textContent = SHARED_MODAL_STYLES;
        wrapper.appendChild(style);

        this.appendChild(wrapper);
        closeBtn.focus();

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
