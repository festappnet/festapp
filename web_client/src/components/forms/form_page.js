import { EmbedBridge, revealEmbedStep } from '../../services/embed_bridge.js';
import { isEmbed } from '../../services/embed_context.js';
import { OrganizationIdentityFooter } from './organization_identity_footer.js';
import { parseOrderFragment, loadOrderOverview, overviewText } from './order_overview.js';
import { WaitlistCommands, parseWaitlistFragment, waitlistRegistrationPayload } from './waitlist_commands.js';
import { prepareOfferSession, renderWaitlistControls, prefillOfferFields, ticketLabel } from './waitlist_form.js';
import { WaitlistStrings as WaitlistStrings } from './waitlist_strings.js';
import { FormModel } from './form_models.js';

import './form_component.css';
import './order_preview.css';
import { Component } from '../base/component.js';
import { CommonStrings } from '../shared/common_strings.js';
import { FormStrings } from './form_strings.js';
import { FormHelper } from './form_helper.js';
import { FormFieldBuilder } from './fields/form_field_builder.js';
import { TicketFieldBuilder } from './fields/ticket_field_builder.js';
import { DbForms } from './db_forms.js';

import { DbOrders } from '../eshop/db_orders.js';
import { RouterService } from '../../services/router_service.js';
import { RightsService } from '../../services/rights_service.js';
import { ColorUtils } from '../../utils/color_utils.js';
import { SeoService } from '../../services/seo_service.js';
// ... (content generated later)
import { ThemeService } from '../../services/theme_service.js';
import { FeatureService } from '../features/feature_service.js';
import { FormAvailabilityService } from './form_availability_service.js';
// Widgets moved to Service
import { CountdownWidget } from './widgets/countdown_widget.js';
// import { NotAvailableWidget } from './widgets/not_available_widget.js';
import { FormRenderer } from './form_renderer.js';
import { FormDataReader } from './form_data_reader.js';
import { FormSession } from './form_session.js';
import { PriceWidget } from './widgets/price_widget.js';
import { CurrencySelectorWidget } from './widgets/currency_selector_widget.js';
import { FormValidator } from './form_validator.js';
import { FormNetwork } from './form_network.js';
import { OrderResult } from './order_result.js';
import { paymentMethodText } from './payment_method_strings.js';
import { BlueprintDataPreparer } from '../blueprint/blueprint_data_preparer.js';
import { CardPaymentController } from './card_payment_controller.js';

export class FormPage extends Component {
    // Keep internal session static for now if needed across hot-reloads, or instance?
    // Instance is cleaner, but need to be careful with Router callbacks.
    // Let's go fully instance.
    constructor(hostId) {
        super(hostId);
        this.pageHost = this.host;
        this.currentPriceWidget = null;
        this.currentSession = null;
        this.currentLink = null;
        this.onBack = null;
        this._previewModulePromise = null;
    }

    clear() {
        this.embedBridge?.destroy();
        this.embedBridge = null;
        window.removeEventListener('festapp-embed-step', this.embedStep);
        this.embedStep = null;
        this.loadGeneration = (this.loadGeneration || 0) + 1;
        this.cleanup();
        this.pageHost?.replaceChildren();
    }

    cleanup({ preserveEditButton = false } = {}) {
        CountdownWidget.stop();
        this.identityFooter?.clear();
        if (this.currentPriceWidget) {
            this.currentPriceWidget.destroy();
            this.currentPriceWidget = null;
        }
        this.currentSession = null;
        this._previewModulePromise = null;
        // Also remove legacy widget just in case
        const widget = document.getElementById('floating-price-widget');
        if (widget) widget.remove();
        
        // Remove FAB if exists
        if (this._fabBtn && !preserveEditButton) {
            this._fabBtn.remove();
            this._fabBtn = null;
        }
        
        // Explicitly destroy Ticket Fields to remove listeners
        if (this.host) {
             const ticketFields = this.host.querySelectorAll('.ticket-field');
             ticketFields.forEach(field => {
                 if (typeof field.destroy === 'function') {
                     field.destroy();
                 }
             });
        }

        // Base cleanup
        super.clear();
    }
    // Timer removed (handled by widgets)
    // static currentLink = null; // Now instance property
    // static onBack = null; // Callback for back navigation // Now instance property

    async init(link, options = {}) {
        // Reset Ticket Counter to ensure deterministic IDs (0, 1, 2...)
        // This prevents IDs from growing indefinitely and helps debugging.
        TicketFieldBuilder.reset();

        // Prevent re-init if same link (e.g. hash change/back from preview)
        // Hardened Check: If container has content, we assume it's valid.
        // NOTE: this.host is managed by base Component
        if (!options.forceReload && this.currentLink === link && this.host && this.host.innerHTML.trim() !== '') {
            return;
        }
        // Check for existing instance to prevent duplicates or state leaks
        if (options.onBack) this.onBack = options.onBack;

        const loadGeneration = this.loadGeneration = (this.loadGeneration || 0) + 1;
        this.cleanup(); // Clean previous content
        window.scrollTo(0, 0);

        this.currentLink = link;
        if (isEmbed() && !this.embedBridge) {
            this.embedBridge = new EmbedBridge(); this.embedBridge.start();
            this.embedStep = event => this.embedBridge.scrollTo(event.detail.element, { block: event.detail.block });
            window.addEventListener('festapp-embed-step', this.embedStep);
        }

        // Configuration
        this.onBack = this.onBack || (() => window.history.back()); // Default fallback

        // Standard cleanup logic
        // Widgets handle their own timers now (CountdownWidget)
        // FormPage.cleanup(); // Clean up any previous widget instances - Moved above



        // Ensure Host
        if (!this.host) {
             console.error("FormPage: No host element!");
             return;
        }
        
        // Keep visible content while an embedded browser waits for the RPC.
        this.pageHost.replaceChildren();
        this.host = document.createElement('div');
        const footer = document.createElement('div'); footer.className = 'organization-identity-slot';
        this.pageHost.append(this.host, footer);
        this.identityFooter = new OrganizationIdentityFooter(footer);
        this.renderLoading();
        document.getElementById("public-seo-summary")?.remove();
        // Containment for fixed children (Embedding Support)
        this.pageHost.style.transform = 'translate(0)';
        this.pageHost.style.display = 'block';
        this.host.style.display = 'block';

        // Hide the main application container to prevent layout shifts
        const app = document.getElementById('app');
        if (app) app.style.display = 'none';

        try {
            // 3. Fetch Data
            this.waitlistScope = parseWaitlistFragment(window.location.hash);
            this.waitlistCommands ||= new WaitlistCommands();
            const viewScope = parseOrderFragment(window.location.hash);
            if (viewScope) {
                this.overviewScope = viewScope;
                this.host.replaceChildren();
                const identityFooter = this.identityFooter;
                const overview = await loadOrderOverview(this.host, this.waitlistCommands, viewScope,
                    this.continuationScope ? () => this.continueOverviewOffer() : null, false, value => { if (loadGeneration === this.loadGeneration) identityFooter.render(value); });
                if (loadGeneration !== this.loadGeneration) return;
                this.currentLink = overview?.root?.formLink || link;
                return;
            }
            this.overviewScope = null;
            let formModel;
            if (this.waitlistScope) {
                let referrer = document.querySelector('meta[name="referrer"]');
                if (!referrer) { referrer = document.createElement('meta'); referrer.name = 'referrer'; document.head.appendChild(referrer); }
                referrer.content = 'no-referrer';
                const bundle = await this.waitlistCommands.read(this.waitlistScope);
                if (loadGeneration !== this.loadGeneration) return;
                this.waitlistBundle = bundle;
                this.identityFooter.render(bundle.form?.organizationIdentity || bundle.organizationIdentity);
                RouterService.canonicalizePublicLink('form', link, bundle.form?.link || bundle.formLink);
                link = bundle.form?.link || bundle.formLink || link;
                this.currentLink = link;
                if (!this.waitlistScope.offerId || !bundle.pendingCount) {
                    this.renderWaitlistManagement(bundle);
                    this.attachOverview();
                    return;
                }
                formModel = new FormModel(bundle.form);
                formModel.offerBundle = bundle;
            } else formModel = await DbForms.getFormByLink(link);
            if (loadGeneration !== this.loadGeneration) return;
            
            if (!formModel) {
                this.renderError(FormStrings.formNotFound);
                return;
            }

            this.identityFooter.render(formModel.organizationIdentity);
            RouterService.canonicalizePublicLink('form', link, formModel.link);
            link = formModel.link || link;
            this.currentLink = link;
            // 4. Apply Theme
            this.applyTheme(formModel);
            
            // 5. Update SEO
            if (!this.waitlistScope) SeoService.updateMetaTags(formModel, window.location.href);


            // --- Availability Check Logic ---
            // Refactored to Service
            const statusResult = FormAvailabilityService.getStatus(formModel);
            
            // Check URL params/Rules for preview
            const urlParams = new URLSearchParams(window.location.search);
            const isPreviewParam = !isEmbed() && urlParams.get('preview') === 'true';
            if (isPreviewParam) await RightsService.updateAppData({ formLink: link });
            const canPreview = RightsService.canSeeReservations();
            const showPreview = canPreview && isPreviewParam;

            const handled = FormAvailabilityService.renderStatus(this.host, formModel, statusResult, {
                showPreview,
                onReload: () => this.init(link, { forceReload: true })
            });

            if (handled) return;

            // 5. Render Form
            this.renderForm(formModel, showPreview);
            
            // 6. Update Rights & Show Edit Button
            // Pass the form link as 'formLink' to match Flutter's behavior
            if (!isEmbed()) RightsService.updateAppData({ formLink: link }).then(() => {
                if (RightsService.canSeeReservations()) {
                    this.renderEditButton(link);
                }
            });

        } catch (e) {
            if (loadGeneration !== this.loadGeneration) return;
            // Capability failures must never log request or transport details.
            this.identityFooter?.clear();
            this.currentLink = null; // A retry must not hit the same-link guard.
            this.renderError(e.message === 'INVALID_CAPABILITY' ? WaitlistStrings.invalid : FormStrings.loadFailed, () => this.init(link));
        }
    }

    async attachOverview() {
        const scope = this.waitlistScope;
        const section = document.createElement('section'); this.host.prepend(section);
        const load = async () => {
            section.replaceChildren();
            try {
                const url = await this.waitlistCommands.overviewAccess(scope);
                const viewScope = parseOrderFragment(new URL(url).hash);
                if (!section.isConnected) return;
                this.overviewScope = viewScope;
                await loadOrderOverview(section, this.waitlistCommands, viewScope, null, true);
            } catch {
                const error = document.createElement('p'); error.textContent = overviewText('failed'); error.setAttribute('role', 'alert');
                const retry = document.createElement('button'); retry.type = 'button'; retry.textContent = overviewText('refresh'); retry.onclick = load;
                section.replaceChildren(error, retry);
            }
        };
        await load();
    }

    async continueOverviewOffer() {
        const scope = this.continuationScope;
        if (!scope) return;
        try {
            const bundle = await this.waitlistCommands.read(scope);
            if (!bundle.form || !bundle.pendingCount) return;
            this.waitlistScope = scope;
            const model = new FormModel(bundle.form); model.offerBundle = bundle;
            this.renderForm(model, false);
        } catch { /* The overview remains available if the offer ended. */ }
    }

    async refreshOffer(model) {
        try {
            const bundle = await this.waitlistCommands.read(this.waitlistScope);
            if (!bundle.form || !bundle.pendingCount) { this.renderWaitlistManagement(bundle); return; }
            const updated = new FormModel(bundle.form); updated.offerBundle = bundle;
            updated.offerDraft = { fields: [...this.currentSession.state.fields], tickets: this.currentSession.state.tickets };
            updated.selectedTicketIds = model.selectedTicketIds.filter(id => bundle.tickets.some(p => p.id === id && !['admitted', 'withdrawn', 'cancelled'].includes(p.lifecycle))).slice(0, bundle.pendingCount);
            this.renderForm(updated, false);
        } catch { /* Keep the editable draft on a network failure. */ }
    }

    async refreshCapacityChoice(model, reason = 'FORM_CAPACITY_EXCEEDED') {
        const current = this.currentSession;
        const link = this.currentLink;
        const priceChanged = reason === 'STRIPE_PRICE_CHANGED';
        const recipientChanged = reason === 'STRIPE_RECIPIENT_CHANGED';
        const reviewRequired = priceChanged || recipientChanged;
        if (reviewRequired) this._paymentReviewPending = true;
        const message = document.createElement('div'); message.setAttribute('role', 'alert');
        const text = document.createElement('p');
        text.textContent = recipientChanged ? paymentMethodText('reason_recipient_changed') : priceChanged ? paymentMethodText('priceChanged') : WaitlistStrings.text(reason);
        const button = document.createElement('button'); button.type = 'button';
        button.textContent = priceChanged ? paymentMethodText('reviewCurrentPrices') : WaitlistStrings.refresh;
        if (reviewRequired) button.dataset.refreshPayment = 'true';
        button.onclick = async () => {
            button.disabled = true;
            try {
                const latest = await DbForms.getFormByLink(link);
                if (!latest || this.currentSession !== current || this.currentLink !== link) return;
                if (latest.registrationMode === 'waitlist' && !window.confirm(WaitlistStrings.explanation)) return;
                // Keep the reservation capability while reading fresh seat prices.
                latest.secret = model.secret;
                let spots = [];
                if (current.state.tickets.some(ticket => ticket.spot) && latest.blueprint && latest.registrationMode !== 'waitlist') {
                    const blueprint = await DbForms.getBlueprint(latest.secret, latest.key, latest.blueprint.id || latest.blueprint);
                    spots = BlueprintDataPreparer.prepare(blueprint).objects || [];
                }
                if (this.currentSession !== current || this.currentLink !== link) return;
                if (FormAvailabilityService.renderStatus(this.host, latest, FormAvailabilityService.getStatus(latest))) return;
                this._pendingPaymentType = this._pendingPaymentMethod = this._pendingPaymentQuote = null;
                this._paymentReviewPending = false;
                this.renderForm(latest, false, { previous: current, spots, review: reviewRequired });
            } catch {
                text.textContent = paymentMethodText('refreshFailed');
            } finally { button.disabled = false; }
        };
        message.append(text, button); this.host.prepend(message);
    }

    async submitWaitlistRegistration(model) {
        const button = this.host.querySelector('.btn-submit');
        if (button.disabled) return;
        button.disabled = true;
        try {
            const data = await this.waitlistCommands.command('register', waitlistRegistrationPayload(this.currentSession));
            this.cleanup({ preserveEditButton: true });
            this.host.replaceChildren();
            const result = document.createElement('p');
            result.setAttribute('role', 'status');
            result.textContent = `${WaitlistStrings.registered} ${data.order?.order_symbol || ''}. ${WaitlistStrings.explanation} ${WaitlistStrings.queued}`;
            if (data.orderOverviewUrl) {
                const scope = parseOrderFragment(new URL(data.orderOverviewUrl).hash);
                const fragment = new URL(data.orderOverviewUrl).hash;
                window.history.replaceState({}, '', `${window.location.pathname}${window.location.search}${fragment}`);
                this.overviewScope = scope;
                this.currentLink = null;
                await this.init(decodeURIComponent(new URL(data.orderOverviewUrl).pathname.split('/').pop()));
                this.host.prepend(result);
            } else this.host.appendChild(result);
        } catch (e) {
            button.disabled = false;
            const error = document.createElement('p'); error.setAttribute('role', 'alert');
            error.textContent = WaitlistStrings.text(e.message);
            this.host.appendChild(error);
        }
    }

    renderWaitlistManagement(bundle) {
        this.host.replaceChildren();
        const title = document.createElement('h2');
        title.textContent = bundle.offerStatus ? WaitlistStrings.text(bundle.offerStatus) : (this.waitlistScope.offerId ? WaitlistStrings.expired : WaitlistStrings.title);
        this.host.appendChild(title);
        const selected = new Set();
        for (const person of bundle.tickets) {
            const label = document.createElement('label'); label.style.cssText = 'display:block;padding:12px';
            const checkbox = document.createElement('input'); checkbox.type = 'checkbox';
            checkbox.disabled = ['admitted', 'cancelled', 'withdrawn'].includes(person.lifecycle);
            checkbox.onchange = () => checkbox.checked ? selected.add(person.id) : selected.delete(person.id);
            label.append(checkbox, document.createTextNode(` ${ticketLabel(person)} ${WaitlistStrings.text(person.lifecycle)}`));
            this.host.appendChild(label);
        }
        if (!this.waitlistScope.offerId) {
            const button = document.createElement('button'); button.textContent = WaitlistStrings.withdraw;
            button.onclick = () => this.resolveWaitlist('withdraw', [...selected]);
            this.host.appendChild(button);
        }
    }

    async resolveWaitlist(operation, ticketIds) {
        if (!ticketIds.length || !window.confirm(WaitlistStrings.confirm)) return;
        try {
            await this.waitlistCommands.command(operation, { ...this.waitlistScope, ticketIds });
            const link = this.currentLink; this.currentLink = null; await this.init(link);
        } catch (e) {
            const error = document.createElement('p'); error.setAttribute('role', 'alert');
            error.textContent = WaitlistStrings.text(e.message); this.host.appendChild(error);
        }
    }

    renderEditButton(link) {
        // Prevent duplicates
        if (this._fabBtn) return;

        const btn = document.createElement('button');
        // ... (rest of creation logic)
        btn.className = 'fab-edit';
        // Material Edit Icon
        btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24" fill="currentColor"><path d="M200-200h57l391-391-57-57-391 391v57Zm-80 80v-170l528-527q12-11 26.5-17t30.5-6q16 0 31 6t26 17l55 56q12 11 17.5 26t5.5 30q0 16-5.5 30.5T817-647L290-120H120Zm635-498-57-57 57 57Zm-58 58L462-200H368v-94l329-329 57 57Z"/></svg>';
        
        // CSS
        btn.style.position = 'fixed';
        btn.style.bottom = '24px';
        btn.style.right = '24px';
        btn.style.width = '56px';
        btn.style.height = '56px';
        btn.style.borderRadius = '50%';
        btn.style.backgroundColor = 'var(--fab-color, var(--primary-color, #000))';
        btn.style.color = 'var(--fab-text-color, #fff)';
        btn.style.border = 'none';
        btn.style.boxShadow = '0 3px 6px rgba(0,0,0,0.16), 0 3px 6px rgba(0,0,0,0.23)';
        btn.style.cursor = 'pointer';
        btn.style.display = 'flex';
        btn.style.alignItems = 'center';
        btn.style.justifyContent = 'center';
        btn.style.zIndex = '3001'; // Keep editor access above the order result.

        btn.onclick = async () => {
             // Prioritize context.occasion.link (backend canonical link)
             // Fallback to local link (form link)
             const context = RightsService.context;
             let occasionLink = context?.occasion?.link;
             
             if (!occasionLink) {
                 occasionLink = link;
             }
             
             const path = `/${occasionLink}/reservations`;
             await RouterService.navigateToFlutterRoute(path);
        };

        document.body.appendChild(btn);
        this._fabBtn = btn;
    }

    renderLoading() {
        this.host.innerHTML = '<div class="loading-spinner" role="status"></div>';
        this.host.firstElementChild.textContent = CommonStrings.loading;
    }

    renderError(message, onRetry) {
        this.identityFooter?.clear();
        this.host.innerHTML = '<div class="error-message" role="alert"></div>';
        const error = this.host.firstElementChild;
        error.textContent = message;
        if (onRetry) {
            const retry = document.createElement('button');
            retry.type = 'button';
            retry.textContent = CommonStrings.retry;
            retry.addEventListener('click', onRetry);
            error.appendChild(retry);
        }
    }

    // Delegated to ThemeService
    applyTheme(formModel) {
        ThemeService.applyThemeFromModel(formModel);
    }

    renderForm(formModel, showPreview, restoredDraft = null) {
        this.currentPriceWidget?.destroy();
        this.currentPriceWidget = null;
        // Initialize Session
        const session = new FormSession(formModel);
        this.currentSession = session;
        prepareOfferSession(session, formModel);
        if (restoredDraft) session.restoreDraft(restoredDraft.previous, restoredDraft.spots);
        
        // Subscribe to Validation Changes
        session.addEventListener('validation-changed', (e) => {
            FormValidator.renderErrors(this.host, e.detail);
        });

        // Initialize Widget (it subscribes itself)
        if (formModel.registrationMode !== 'waitlist') this.currentPriceWidget = new PriceWidget(session, this.host);
        FormRenderer.render(this.host, session, formModel, showPreview, {
            onSubmit: (form, model) => this.validateAndSubmit(form, model),
            onInput: (e, form, model) => {
                if (e.type === 'input') FormValidator.handleInputValidation(e, form, session);
                
                // Optimized State Update
                // If target has no name (e.g. Ticket Add/Remove button dispatch), refresh full structure
                if (!e.target.name) {
                    // Structural change (e.g. Ticket Removed) logic is now handled by internal state methods
                    // session.removeTicket() etc. No need to re-scrape.
                } else {
                    session.handleInput(e, form);
                }
            }
        });
        
        if (formModel.registrationMode !== 'waitlist') new CurrencySelectorWidget(session, this.host);
        renderWaitlistControls(this, formModel);
        if (this.waitlistScope) this.attachOverview();
        
        

        
        // Handle Currency Filtering
        session.addEventListener('state-changed', (e) => {
            const { currency, previousCurrency } = e.detail;
            const form = this.host.querySelector('form'); // Live lookup
            if (!form) return;

            // User Request: "deselect all products if you switch the currency"
            // We should aggressive deselect ALL products if the currency actually changed.
            // But state-changed fires on PRICE updates too. 
            // We need to know if CURRENCY changed. 
            // The event detail only gives current currency. 
            // We need to compare with a tracked previous state, or check if the event provides it.
            // Since we don't have 'previousCurrency' in the event detail yet...
            // Wait, we generate the event in FormSession.
            
            // To be safe and compliant with "switch currency" implied action:
            // This listener hooks into `state-changed`. If we just uncheck everything every time state changes,
            // we kill partial selections during standard input. BAD.
            
            // WE MUST CHECK IF CURRENCY CHANGED.
            // But `FormSession` emits `state-changed` with { currency, ... }.
            // We can store last seen currency in a local variable in this scope.
            
        });
        
        let lastSeenCurrency = session.state.currency;

        session.addEventListener('state-changed', (e) => {
             const { currency } = e.detail;
             const form = this.host.querySelector('form');
             if (!form) return;
             
             const currencyChanged = lastSeenCurrency !== currency;
             lastSeenCurrency = currency;
             
             // 1. Sync Standard Fields from Session (Replaces manual unchecking)
             // Iterate all standard inputs and match against session state
             const allInputs = form.querySelectorAll('input, select, textarea');
             allInputs.forEach(input => {
                 if (input.dataset.ticketId) return; // Skip ticket fields (handled by TicketFieldBuilder)
                 if (input.type === 'submit' || input.type === 'button' || input.type === 'hidden') return;
                 if (!input.name) return;
                 
                 let lookupKey = input.name;
                 let isExpiry = false;

                 if (input.name && input.name.endsWith('_expiry')) {
                     lookupKey = input.name.replace('_expiry', '');
                     isExpiry = true;
                 }
                 
                 const val = session.state.fields.get(lookupKey);
                 
                 // Apply Logic (Standard)
                 if (input.type === 'radio') {
                     const shouldCheck = val !== undefined && String(input.value) === String(val);
                     if (input.checked !== shouldCheck) input.checked = shouldCheck;
                 } else if (input.type === 'checkbox') {
                      let isChecked = false;
                      if (val !== undefined) {
                          if (val === true || val === 'true') isChecked = true;
                          else isChecked = String(val).split(' | ').includes(input.value);
                      }
                      if (input.checked !== isChecked) input.checked = isChecked;
                 } else {
                     let expected = val !== undefined ? val : '';
                     
                     // Handle Composite Objects (e.g. ID Document)
                     if (typeof expected === 'object' && expected !== null) {
                         // Check for ID Document structure
                         if (expected.id_document_number !== undefined) {
                             if (isExpiry) {
                                  expected = expected.id_document_expiry_date || '';
                             } else {
                                  expected = expected.id_document_number || '';
                             }
                         }
                     }

                     if (String(input.value) !== String(expected)) {
                         input.value = expected;
                     }
                 }
                 
                 // Update "Clear Selection" Button Visibility
                 // This effectively handles "Reactive UI" for standard fields
                 const container = input.closest('.form-field-container');
                 if (container) {
                     const clearBtn = container.querySelector('.btn-clear-selection');
                     if (clearBtn) {
                         const anyChecked = container.querySelector('input:checked');
                         clearBtn.style.display = anyChecked ? 'inline-block' : 'none';
                     }
                 }
             });

             // 2. Visibility Logic (CSS)
             const allCurrencyElements = form.querySelectorAll('[data-currency]');
             
             allCurrencyElements.forEach(el => {
                const itemCurrency = el.getAttribute('data-currency');
                
                // Only toggle container-like elements, not inputs themselves (inputs are data-driven)
                if (el.classList.contains('form-check') || el.classList.contains('dropdown-item') || el.classList.contains('option-card')) {
                     if (itemCurrency && itemCurrency !== currency) {
                         el.style.display = 'none';
                     } else {
                         el.style.display = ''; 
                     }
                }
             });

             // 3. Trigger Session Cleanup
             // If currency changed, we command session to drop invalid values.
             // This modifies state -> triggers 'state-changed' again -> runs Sync above -> Unchecks inputs.
             if (currencyChanged) {
                 session.resetIncompatibleCurrencyFields(currency);
             }
        });
        
        // Trigger initial update for the price widget
        setTimeout(() => {
            if (this.currentSession !== session) return;
            const form = this.host.querySelector('form');
            if (form) {
                // Initial syncing
                // Parse the initial form state (e.g. default values) into the session
                if (restoredDraft) {
                    prefillOfferFields(form, session);
                    session._syncPayloadFromState();
                    session._recalculate();
                } else session.initialize(form);
                if (formModel.offerBundle) prefillOfferFields(form, session);
                
                // Initial syncing
                // If the session initialized with a currency (e.g. from logic), ensure filter runs.
                // Disptach current state to trigger filter
                session.setIsReady(true);
                if (restoredDraft?.review && formModel.registrationMode !== 'waitlist') this.validateAndSubmit(form, formModel);
            }
        }, 100);

        // Optimization: Prefetch OrderPreview
        this.prefetchPreview();
    }

    prefetchPreview() {
        if (this._previewModulePromise) return;

        const fetcher = () => {
             if (this._previewModulePromise) return;
             this._previewModulePromise = import('./order_preview.js');
        };

        if (window.requestIdleCallback) {
            window.requestIdleCallback(fetcher);
        } else {
            setTimeout(fetcher, 2000); // 2s delay
        }
    }


    // --- Validation & Submit Logic ---
    
    // Delegated to FormValidator
    handleInputValidation(e, form) {
         FormValidator.handleInputValidation(e, form, this.currentSession);
    }

    validateAndSubmit(form, formModel) {
        if (this._paymentReviewPending) {
            this.host.querySelector('[data-refresh-payment]')?.click();
            return;
        }
        if (this.currentSession.state.tickets.length > this.currentSession.maxTickets) {
            const error = document.createElement('p'); error.setAttribute('role', 'alert'); error.textContent = WaitlistStrings.text('FORM_CAPACITY_EXCEEDED'); form.prepend(error); revealEmbedStep(error); return;
        }
        if (formModel.offerBundle && !formModel.selectedTicketIds?.length) {
            const message = document.createElement('p'); message.setAttribute('role', 'alert'); message.textContent = WaitlistStrings.selectPeople; form.prepend(message); revealEmbedStep(message); return;
        }
        const isValid = FormValidator.validateAndShowErrors(form, formModel, this.currentSession);
        
        if (isValid) {
            if (formModel.registrationMode === 'waitlist') {
                if (window.confirm(WaitlistStrings.explanation)) this.submitWaitlistRegistration(formModel);
            } else this.handlePreview(form, formModel);
        }
    }

    calculateTotal(form, formModel) {
        if (this.currentSession) {
            return this.currentSession.state;
        }
        const payload = FormDataReader.getPayload(form, formModel);
        return FormHelper.calculatePrice(payload, formModel);
    }

    // --- DEBUG HELPER ---
    handlePreview(form, formModel) {
        // Native Validation Check
        // Explicitly check native validity before proceeding, 
        // as some browsers might not block onSubmit if preventDefault was called early?
        // Actually, normally 'submit' event only fires if valid. 
        // But we are calling this from our explicit handler.
        if (!form.reportValidity()) {
            return;
        }

        // Use prefetched module if available, or fetch now
        if (!this._previewModulePromise) {
            this._previewModulePromise = import('./order_preview.js');
        }

        this._previewModulePromise.then(({ OrderPreview }) => {
             try {
                 const priceData = this.calculateTotal(form, formModel);
                 const precalculatedPayload = this.currentSession ? this.currentSession.payload : null;
                 
                 OrderPreview.show(form, formModel, priceData, (overlay, paymentType, paymentMethod, paymentQuote) => {
                     // On Confirm
                     this._pendingPaymentType = paymentType || null;
                     this._pendingPaymentMethod = paymentMethod;
                     this._pendingPaymentQuote = paymentQuote;
                     this.submitOrder(form, formModel, overlay || document.body);
                 }, () => {
                     // Restore the single identity slot after the preview removes its content.
                     if (this.identityFooter) this.pageHost.append(this.identityFooter.host);
                 }, precalculatedPayload);
                 const previewContent = document.querySelector('#order-preview-overlay .order-preview-content');
                 if (previewContent && this.identityFooter) previewContent.append(this.identityFooter.host);
                 
             } catch (e) {
                 console.error('[FormPage] OrderPreview.show crashed:', e);
             }
        }).catch(err => {
             console.error('[FormPage] Failed to load OrderPreview module', err);
        });
    }
    
    closePreview() {
        const overlay = document.getElementById('order-preview-overlay');
        if (overlay) {
            overlay.classList.remove('visible');
            setTimeout(() => {
                overlay.remove(); 
            }, 300); 
        }
    }

    submitOrder(form, formModel, unusedContent) {
        // 1. Close Preview
        const previewOverlay = document.getElementById('order-preview-overlay');
        let previewHistoryClosed = Promise.resolve();
        if (previewOverlay) {
             previewOverlay.remove();
             previewHistoryClosed = new Promise(resolve => {
                 let fallbackTimer = null;
                 const handlePreviewClosed = () => {
                     window.removeEventListener('popstate', handlePreviewClosed);
                     if (fallbackTimer) clearTimeout(fallbackTimer);
                     resolve();
                 };

                 window.addEventListener('popstate', handlePreviewClosed, { once: true });
                 RouterService.goBackProgrammatically();

                 // A direct invocation can have no preview history entry. Do not
                 // leave submission completion blocked in that defensive case.
                 fallbackTimer = setTimeout(handlePreviewClosed, 1000);
             });
        } else {
             this.closePreview();
        }

        // 2. Show Loader
        const loader = this.showFullScreenLoader();
        
        // 3. Prepare Data
        const payload = this.currentSession ? this.currentSession.payload : FormDataReader.getPayload(form, formModel);

        // Inject payment_type if deposit option was selected
        if (this._pendingPaymentType) {
            payload.payment_type = this._pendingPaymentType;
            this._pendingPaymentType = null;
        }

        // 4. Submit via Network
        if(this._pendingPaymentMethod){
            if(this._pendingPaymentMethod==='stripe'){
                payload.payment_method='stripe';
                payload.payment_type='full';
                payload.expected_payment_amount_minor=this._pendingPaymentQuote.amountMinor;
                payload.expected_payment_currency=this._pendingPaymentQuote.currency;
                payload.stripe_connection_id=this._pendingPaymentQuote.connectionId;
                payload.payment_surface=this._pendingPaymentQuote.surface;
            }
            this._pendingPaymentMethod=null;this._pendingPaymentQuote=null;
        }
        const request = formModel.offerBundle
            ? this.waitlistCommands.accept(this.waitlistScope, formModel.selectedTicketIds, {
                ...payload, ticket: payload.ticket.map(t => ({ ...t, fields: t.fields.map(f => {
                    const def = this.currentSession._getTicketSubDef(f._subFieldId);
                    return def && def.type !== 'product_type' ? { ...f, [def.id]: f[def.type] } : f;
                }) })),
            }).then(data => ({ success: true, data }))
            : FormNetwork.submitOrder(payload);
        request.then(async result => {
             // history.back() is asynchronous. Rendering the result before the
             // preview popstate arrives lets that stale event close the result.
             await previewHistoryClosed;

             loader.remove();
             document.body.style.overflow = ''; 
             
             if (result.success) {
                 if (formModel.offerBundle) {
                     const link = this.currentLink;
                     if (this.overviewScope) {
                         this.continuationScope = this.waitlistScope;
                         const fragment = `order?${new URLSearchParams({ order_id: String(this.overviewScope.orderId), token: this.overviewScope.token })}`;
                         window.history.replaceState({}, '', `${window.location.pathname}${window.location.search}#${fragment}`);
                     }
                     this.currentLink = null;
                     await this.init(link);
                     this.showFullScreenResult(true, { ...result.data, overviewAvailable: Boolean(this.overviewScope), ticketOrder: { order: result.data.order } }, formModel);
                     return;
                 }
                 // Clean up old widgets first
                 this.cleanup({ preserveEditButton: true });

                 // Reset Form
                 if (this.host) {
                     this.host.innerHTML = '';
                     this.renderForm(formModel, false);
                 }
                 window.scrollTo(0, 0); 
             }
             
             if (!result.success && ['FORM_CAPACITY_EXCEEDED', 'STRIPE_PRICE_CHANGED', 'STRIPE_RECIPIENT_CHANGED'].includes(result.data?.errorCode)) await this.refreshCapacityChoice(formModel, result.data.errorCode);
             this.showFullScreenResult(result.success, result.data, formModel);
             
        }).catch(async e => {
             await previewHistoryClosed;

             // Preserve the stable error UI without logging capability-bearing transport errors.
             loader.remove();
             document.body.style.overflow = ''; 
             if (formModel.offerBundle) await this.refreshOffer(formModel);
             this.showFullScreenResult(false, e.data || { code: 999, errorCode: e.message }, formModel);
        });
    }

    showFullScreenLoader() {
        const loader = document.createElement('div');
        loader.className = 'fullscreen-loader-overlay';
        loader.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background-color: rgba(0, 0, 0, 0.85); /* Dark background */
            backdrop-filter: blur(5px);
            z-index: 3000;
            display: flex;
            justify-content: center;
            align-items: center;
            flex-direction: column;
            font-family: var(--font-family-base, sans-serif);
        `;
        
        // Spinner
        loader.innerHTML = `
            <div class="spinner"></div>
            <div style="margin-top: 24px; font-weight: 600; font-size: 1.1rem; color: #ffffff;">
                ${CommonStrings.processing || 'Processing...'}
            </div>
        `;
        
        document.body.appendChild(loader);
        if (!isEmbed()) document.body.style.overflow = 'hidden'; // Ensure scroll locked
        
        // Ensure Spinner CSS
        if (!document.getElementById('spinner-style')) {
            const style = document.createElement('style');
            style.id = 'spinner-style';
            style.textContent = `
                .spinner {
                    border: 4px solid rgba(255,255,255,0.1); /* Light track for dark bg */
                    border-top: 4px solid var(--primary-color, #3498db);
                    border-radius: 50%;
                    width: 50px;
                    height: 50px;
                    animation: spin 1s linear infinite;
                }
                @keyframes spin {
                    0% { transform: rotate(0deg); }
                    100% { transform: rotate(360deg); }
                }
            `;
            document.head.appendChild(style);
        }
        
        revealEmbedStep(loader);
        return loader;
    }

    showFullScreenResult(success, resultData, formModel) {
        // Push State
        RouterService.pushOverlayState('order-result');

        // Create Full Screen Container
        const container = document.createElement('div');
        container.className = 'fullscreen-result-overlay';
        container.style.position = 'fixed';
        container.style.top = '0';
        container.style.left = '0';
        container.style.width = '100%';
        container.style.height = '100%';
        container.style.backgroundColor = 'var(--background-color, #fff)';
        container.style.zIndex = '3000';
        container.style.overflowY = 'auto'; // Scrollable result
        container.style.padding = '20px';
        container.style.boxSizing = 'border-box'; /* Ensure padding doesn't affect width calculations */
        container.style.display = 'flex';
        container.style.flexDirection = 'column';
        container.style.justifyContent = 'safe center'; /* Center short results without clipping tall results */
        container.style.alignItems = 'center'; /* Center Horizontally */
        
        document.body.appendChild(container);
        if (!isEmbed()) document.body.style.overflow = 'hidden'; // Ensure scroll locked

        const previousFocus = document.activeElement;
        const escapeResult = event => {
            if (isEmbed() && event.key === 'Escape') RouterService.goBackProgrammatically();
        };
        container.addEventListener('keydown', escapeResult);

        let cardPaymentController = null;
        // Cleanup Function
        const cleanup = () => {
            cardPaymentController?.dispose();
            if (this.identityFooter) this.pageHost.append(this.identityFooter.host);
            container.remove();
            previousFocus?.focus({ preventScroll: true });
            revealEmbedStep(previousFocus);
            document.body.style.overflow = ''; // Restore scroll
            
            if (success && !formModel.offerBundle) {
                    // Clean up old widget instance first
                    this.cleanup({ preserveEditButton: true });
                    this.identityFooter?.render(formModel.organizationIdentity);
                    
                    // Reset Form State BEHIND the overlay
                    if (this.host) {
                        this.host.innerHTML = '';
                        this.renderForm(formModel, false);
                    }
                    
                    // Scroll to top immediately
                    window.scrollTo(0, 0);
            } else {
                    // Failure: Ensure widget is visible (defensive)
            }
        };

        // Handle Back History
        const popHandler = () => {
            window.removeEventListener('popstate', popHandler);
            cleanup();
        };
        window.addEventListener('popstate', popHandler, { once: true });

        const renderResult = () => {
            const focusedAction = document.activeElement?.dataset?.paymentAction;
            OrderResult.render(container, success, resultData, formModel, () => {
                RouterService.goBackProgrammatically();
            }, cardPaymentController ? {
                onPay: () => cardPaymentController.continue(),
                onRefresh: () => cardPaymentController.refresh(),
            } : {});
            if (this.identityFooter) {
                this.identityFooter.render(formModel.organizationIdentity);
                container.append(this.identityFooter.host);
            }
            if (focusedAction) container.querySelector(`[data-payment-action="${focusedAction}"]`)?.focus({preventScroll:true});
        };
        if (!isEmbed()) cardPaymentController = CardPaymentController.fromResult(resultData, {onPayment: payment => {
            resultData.payment = payment;
            if(container.isConnected)renderResult();
        }});
        renderResult();
        revealEmbedStep(container);
        if (cardPaymentController && resultData.checkout_url) {
            try { cardPaymentController.openPrepared(resultData.checkout_url); } catch { /* The same order remains resumable. */ }
        }
    }
}
