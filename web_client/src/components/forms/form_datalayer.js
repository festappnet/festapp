import { analyticsPayload, currencies } from './form_measurement_contract.js';
import { AppConfig } from '../../app_config.js';
import { isValidEmail } from '../../logic/email_address.js';
import { normalizeE164Phone } from '../../utils/phone_formatter.js';
import { browserStorage } from '../../services/browser_storage.js';

import {publicFormLocation, documentEntryAllowed} from '../../utils/public_form_location.js';

export function hasBrowserSession(win) {
    try {
        if (browserStorage.getItem(AppConfig.Keys.auth)) return true;
        for (const storage of [win.localStorage, win.sessionStorage]) {
            for (let i = 0; i < storage.length; i++) {
                const key = storage.key(i);
                if ((key === AppConfig.Keys.auth || key === 'refresh' || /^sb-.*-auth-token/.test(key)) && storage.getItem(key)) return true;
            }
        }
        return false;
    } catch { return true; }
}

// Public catalog labels only: the product type and the occasion it belongs to.
const catalogItem = (product, currency, item_category, item_brand) => ({item_id: `product_${product.id}`, item_name: product.title,
    price: Number(product.price), quantity: 1, currency, item_category, item_brand});

export class FormDataLayer {
    constructor({win = window, model, bridge, entryAllowed, session = hasBrowserSession, refreshPolicy}) {
        this.win = win; this.model = model; this.bridge = bridge; this.session = session;
        this.entryAllowed = (entryAllowed ?? publicFormLocation(win.location, {entry: true})) && documentEntryAllowed(win);
        this.previous = [];
        this.pageType = 'product';
        this.viewedPages = new Set();
        this.viewedCurrencies = new Set();
        this.conversions = new Set();
        this.policyExpiresAt = Date.now() + Math.min(60, Math.max(0, Number(model.data?.analytics?.valid_for_seconds) || 0)) * 1000;
        this.refreshPolicy = refreshPolicy;
        this.policyGeneration = 0;
        // Hiding keeps the frame, so the container does not run twice for one visit.
        // Returning rechecks policy and context, which removes the frame when they failed.
        this.onVisibility = () => { if (!this.win.document.hidden) this.renewPolicy(); };
        win.document.addEventListener?.('visibilitychange', this.onVisibility);
        this.onPageShow = event => { if (event.persisted) this.renewPolicy(); };
        win.addEventListener?.('pageshow', this.onPageShow);
        this.catalog = new Map(); this.fields = new Map();
        const visit = fields => {
            for (const field of fields || []) {
                if (field.isHidden) continue;
                if (field.type === 'product_type') {
                    this.fields.set(String(field.id), field);
                    for (const product of field.options || []) {
                        if (!/^[1-9]\d{0,15}$/.test(String(product.id))) continue;
                        const currency = product.currency || product.currency_code;
                        if (!currencies(currency)) continue;
                        this.catalog.set(String(product.id), catalogItem(product, currency, field.productTypeData?.title, model.occasionTitle));
                    }
                }
                visit(field.subFields);
            }
        };
        visit(model.visibleFields || model.relatedFields);
        if (refreshPolicy && model.data?.analytics?.eligible === true && this.publicContext()) {
            this.policyTimer = win.setInterval(() => this.renewPolicy(), 20000);
            if (this.session(win)) this.renewPolicy();
        }
    }
    cancelPending() { this.observation = (this.observation || 0) + 1; }
    dispose() { this.cancelPending(); this.disposed = true; this.policyGeneration++; this.win.clearInterval(this.policyTimer); this.bridge?.revokeMeasurement?.(); this.win.document.removeEventListener?.('visibilitychange', this.onVisibility); this.win.removeEventListener?.('pageshow', this.onPageShow); }
    async renewPolicy() {
        if (!this.refreshPolicy || this.disposed || this.renewing || this.staff) return;
        if (!this.publicContext()) { this.bridge?.revokeMeasurement?.(); return; }
        const generation = this.policyGeneration;
        this.renewing = true;
        try {
            const policy = await this.refreshPolicy();
            if (this.disposed || generation !== this.policyGeneration) return;
            if (!policy || policy.enabled !== true || policy.organization_allowed !== true || policy.eligible !== true || policy.runtime_supported !== true)
                throw Error('measurement unavailable');
            const blocked = !this.enabled();
            this.model.data.analytics = policy;
            this.policyExpiresAt = Date.now() + Math.min(60, Math.max(0, Number(policy.valid_for_seconds) || 0)) * 1000;
            if (policy.visitor_role === 'staff') { this.stopForStaff(); return; }
            this.bridge?.updatePolicy?.(this.policyExpiresAt);
            if (blocked) this.view(); // A verified visitor's frame may report ready before this.
        } catch {
            if (!this.disposed && generation === this.policyGeneration) {
                this.policyExpiresAt = 0;
                this.model.data.analytics = {...this.model.data.analytics, eligible:false};
                this.bridge?.revokeMeasurement?.();
            }
        } finally { this.renewing = false; }
    }
    publicContext() {
        try { return !this.disposed && this.entryAllowed && !this.model.demoSimulation && publicFormLocation(this.win.location); }
        catch { return false; }
    }
    // A signed-in visitor counts only after the server named the role for this form.
    // Anything else, including a session the server did not see, stays unmeasured.
    visitorAllowed() {
        const role = this.model.data?.analytics?.visitor_role;
        return !this.staff && role !== 'staff' && (!this.session(this.win) || role === 'visitor');
    }
    contextAllowed() {
        try { return this.publicContext() && this.visitorAllowed(); }
        catch { return false; }
    }
    // Resolves once it is known whether this visitor may be measured.
    async visitorReady() {
        if (this.publicContext() && this.session(this.win)) await this.renewPolicy();
        return this.contextAllowed();
    }
    stopForStaff() {
        this.staff = true;
        this.win.clearInterval(this.policyTimer);
        this.bridge?.revokeMeasurement?.();
    }
    // Sign-in during a visit: nothing is sent until the server names the new role.
    authChanged(userId = null) {
        if (this.authUser === undefined) { this.authUser = userId; return; }
        if (this.authUser === userId) return;
        this.authUser = userId;
        this.model.data.analytics = {...this.model.data.analytics, visitor_role:undefined};
        this.bridge?.revokeMeasurement?.();
        this.policyGeneration++;
        this.renewing = false;
        this.renewPolicy();
    }
    enabled() {
        try {
            const policy = this.model.data?.analytics;
            if (this.disposed || policy?.enabled !== true || policy.organization_allowed !== true ||
                policy.runtime_supported !== true || policy.eligible !== true ||
                !this.contextAllowed()) { this.bridge?.revokeMeasurement?.(); return false; }
            // Expiry only pauses sends here. The transport owns removing its frame.
            return Date.now() < this.policyExpiresAt && this.bridge?.measurementAllowed?.() === true;
        } catch { return false; }
    }
    // The host transport hands contact to the embedding page. Any site can embed a
    // public form and opt in, so that page must be one the organizer approved.
    contactAllowed() {
        const host = this.bridge?.dataLayerHost?.();
        const approved = this.model.data?.analytics?.approved_hosts;
        return !host || (Array.isArray(approved) && approved.includes(host));
    }
    // Normalized as Google requires: e-mail trimmed and lowercased, phone in E.164.
    // A value that cannot be normalized safely is left out rather than guessed.
    // Runs inside order submission, so no failure here may reach the caller.
    contact(payload) {
        try {
            if (!this.enabled() || !this.contactAllowed()) return null;
            const answer = type => {
                const field = (this.model.visibleFields || this.model.relatedFields)?.find(item => item.type === type);
                const id = String(field?.id);
                return payload?.fields?.find(entry => Object.hasOwn(entry, id))?.[id];
            };
            const email = String(answer('email') ?? '').trim().toLowerCase();
            const prefixes = this.model.data?.phone_prefixes;
            const phone = normalizeE164Phone(answer('phone'), {defaultPrefix: Array.isArray(prefixes) && prefixes.length === 1 ? prefixes[0] : null});
            return {email: isValidEmail(email) ? email : null, phone_number: phone};
        } catch { return null; }
    }
    emit(input) {
        if (!this.enabled()) return false;
        const payload = analyticsPayload(input);
        if (!payload) return false;
        try { return this.bridge.track(payload) === true; }
        catch { return false; }
    }

    page(page_type) {
        this.pageType = page_type;
        const language = this.win.document.documentElement.lang?.slice(0, 2);
        this.emit({page_type, language});
        if (!this.viewedPages.has(page_type) && this.emit({event: 'page_view'})) this.viewedPages.add(page_type);
    }
    // First real visitor input. Field names and values never leave.
    started() { if (!this.formStarted && this.emit({event: 'form_start'})) this.formStarted = true; }
    groups(event, items, extra = {}) {
        for (const currency of new Set(items.map(item => item.currency))) {
            this.emit({event, ecommerce: {currency, items: items.filter(item => item.currency === currency), ...extra}});
        }
    }
    view() {
        this.page(this.pageType);
        const items = [...this.catalog.values()];
        for (const currency of new Set(items.map(item => item.currency))) {
            if (!this.viewedCurrencies.has(currency) && this.emit({event:'view_item', ecommerce:{currency, items:items.filter(item => item.currency === currency)}}))
                this.viewedCurrencies.add(currency);
        }
        return this.viewedPages.size > 0;
    }
    cart(payload = {}, session) {
        const selected = new Map();
        const add = value => {
            for (const id of Array.isArray(value) ? value : String(value ?? '').split(' | ')) {
                const product = this.catalog.get(String(id));
                if (product) selected.set(product.item_id, {...product, quantity: (selected.get(product.item_id)?.quantity || 0) + 1});
            }
        };
        for (const field of payload.fields || []) {
            for (const id of this.fields.keys()) if (Object.hasOwn(field, id)) add(field[id]);
        }
        for (const [index, ticket] of (payload.ticket || []).entries()) {
            const cached = session?.spotModels?.get(String(ticket.spot));
            const product = cached?.productModel || cached?.product || session?.state?.tickets?.[index]?._blueprintProduct;
            if (product && /^[1-9]\d{0,15}$/.test(String(product.id))) {
                const currency = product.currency_code || product.currencyCode || product.currency || session?.state?.currency;
                if (currencies(currency)) {
                    this.catalog.set(String(product.id), catalogItem(product, currency,
                        product.type_title ?? this.catalog.get(String(product.id))?.item_category, this.model.occasionTitle));
                    if (ticket.spot) add(product.id);
                }
            }
            // Only a catalog product is accepted. Spot IDs, notes and all answers are ignored.
            for (const field of ticket.fields || []) if (Object.hasOwn(field, 'product_type')) add(field.product_type);
        }
        return [...selected.values()];
    }
    update(payload, session) {
        const next = this.cart(payload, session);
        for (const [event, from, to] of [['add_to_cart', next, this.previous], ['remove_from_cart', this.previous, next]]) {
            const delta = from.map(item => ({...item, quantity: item.quantity - (to.find(old => old.item_id === item.item_id && old.currency === item.currency)?.quantity || 0)})).filter(item => item.quantity > 0);
            this.groups(event, delta);
        }
        this.previous = next;
    }
    observe(session) {
        const version = this.observation = (this.observation || 0) + 1;
        Promise.resolve().then(() => session.awaitPendingReservations?.({recover: false})).then(() => {
            if (version !== this.observation) return;
            if (this.enabled()) this.update(session.payload, session);
            else this.previous = this.cart(session.payload, session); // Baseline only until the transport is ready.
        }).catch(() => {}); // Failed reservations never become successful cart changes.
    }
    review(payload, session) {
        const items = this.cart(payload, session);
        this.page('checkout');
        this.groups('begin_checkout', items);
    }
    payment(payload, method, session) {
        const items = this.cart(payload, session);
        this.groups('add_payment_info', items, {payment_type: items.every(item => item.price === 0) ? 'free' : method === 'stripe' ? 'card' : 'bank_transfer'});
    }
    confirmed(data, contact = null) {
        this.pageType = 'confirmation';
        const conversion = analyticsPayload(data?.ticketOrder?.analytics);
        if (!conversion || !['purchase', 'generate_lead'].includes(conversion.event)) return;
        const identity = conversion.ecommerce?.transaction_id || conversion.event_id;
        if (!this.enabled() || this.conversions.has(identity)) return;
        this.page('confirmation');
        if (this.emit(contact && this.contactAllowed() ? {...conversion, user_data: contact} : conversion)) this.conversions.add(identity);
    }
}
