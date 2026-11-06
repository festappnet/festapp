import { analyticsPayload, currencies } from './form_measurement_contract.js';
import { AppConfig } from '../../app_config.js';
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
        this.conversionEpochs = new Map();
        this.policyExpiresAt = Date.now() + Math.min(60, Math.max(0, Number(model.data?.analytics?.valid_for_seconds) || 0)) * 1000;
        this.refreshPolicy = refreshPolicy;
        this.policyGeneration = 0;
        this.onVisibility = () => {
            this.policyGeneration++;
            this.policyExpiresAt = 0;
            if (this.refreshPolicy) this.model.data.analytics = {...this.model.data.analytics, eligible:false};
            this.bridge?.revokeMeasurement?.();
            if (!this.win.document.hidden) this.renewPolicy();
        };
        win.document.addEventListener?.('visibilitychange', this.onVisibility);
        this.onPageShow = event => { if (event.persisted) this.onVisibility(); };
        win.addEventListener?.('pagehide', this.onVisibility);
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
        if (refreshPolicy && model.data?.analytics?.eligible === true && this.contextAllowed())
            this.policyTimer = win.setInterval(() => this.renewPolicy(), 20000);
    }
    cancelPending() { this.observation = (this.observation || 0) + 1; }
    dispose() { this.cancelPending(); this.disposed = true; this.policyGeneration++; this.win.clearInterval(this.policyTimer); this.bridge?.revokeMeasurement?.(); this.win.document.removeEventListener?.('visibilitychange', this.onVisibility); this.win.removeEventListener?.('pagehide', this.onVisibility); this.win.removeEventListener?.('pageshow', this.onPageShow); }
    async renewPolicy() {
        if (!this.refreshPolicy || this.disposed || this.renewing || this.win.document.hidden) return;
        if (!this.contextAllowed()) { this.bridge?.revokeMeasurement?.(); return; }
        const generation = this.policyGeneration;
        this.renewing = true;
        try {
            const policy = await this.refreshPolicy();
            if (this.disposed || generation !== this.policyGeneration) return;
            if (!policy || policy.enabled !== true || policy.organization_allowed !== true || policy.eligible !== true || policy.runtime_supported !== true)
                throw Error('measurement unavailable');
            this.model.data.analytics = policy;
            this.policyExpiresAt = Date.now() + Math.min(60, Math.max(0, Number(policy.valid_for_seconds) || 0)) * 1000;
            this.bridge?.updatePolicy?.(this.policyExpiresAt);
        } catch {
            if (!this.disposed && generation === this.policyGeneration) {
                this.policyExpiresAt = 0;
                this.model.data.analytics = {...this.model.data.analytics, eligible:false};
                this.bridge?.revokeMeasurement?.();
            }
        } finally { this.renewing = false; }
    }
    contextAllowed() {
        try { return !this.disposed && this.entryAllowed && !this.model.demoSimulation &&
            publicFormLocation(this.win.location) && !this.session(this.win); }
        catch { return false; }
    }
    measurementEpoch() {
        try {
            const policy = this.model.data?.analytics;
            if (this.disposed || policy?.enabled !== true || policy.organization_allowed !== true ||
                policy.runtime_supported !== true || policy.eligible !== true || Date.now() >= this.policyExpiresAt ||
                !this.contextAllowed()) { this.bridge?.revokeMeasurement?.(); return null; }
            return this.bridge?.measurementEpoch?.() ?? null;
        } catch { return null; }
    }
    enabled() { return this.measurementEpoch() !== null; }
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
    // First real visitor input after consent. Field names and values never leave.
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
        const epoch = this.measurementEpoch();
        Promise.resolve().then(() => session.awaitPendingReservations?.({recover: false})).then(() => {
            if (version !== this.observation) return;
            if (epoch !== null && epoch === this.measurementEpoch()) this.update(session.payload, session);
            else this.previous = this.cart(session.payload, session); // Baseline only; no replay across consent grants.
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
    confirmed(data) {
        this.pageType = 'confirmation';
        const conversion = analyticsPayload(data?.ticketOrder?.analytics);
        if (!conversion || !['purchase', 'generate_lead'].includes(conversion.event)) return;
        const identity = conversion.ecommerce?.transaction_id || conversion.event_id;
        const epoch = this.measurementEpoch();
        if (!this.conversionEpochs.has(identity)) this.conversionEpochs.set(identity, epoch);
        if (epoch === null || this.conversionEpochs.get(identity) !== epoch || this.conversions.has(identity)) return;
        this.page('confirmation');
        if (this.emit(conversion)) this.conversions.add(identity);
    }
}
