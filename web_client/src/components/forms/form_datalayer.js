import { isValidEmail } from '../../logic/email_address.js';
import { normalizeE164Phone } from '../../utils/phone_formatter.js';
import { FORM_MEASUREMENT_SCRIPT_LIMIT } from './form_measurement_limits.js';
import { AppConfig } from '../../app_config.js';
import { browserStorage } from '../../services/browser_storage.js';

const ecommerceEvents = new Set(['view_item', 'add_to_cart', 'remove_from_cart', 'begin_checkout', 'add_payment_info', 'purchase']);
const currencies = value => typeof value === 'string' && /^[A-Z]{3}$/.test(value);
const productId = value => typeof value === 'string' && /^product_[1-9]\d{0,15}$/.test(value);
const orderSymbol = value => typeof value === 'string' && /^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$/.test(value);
const pageTypes = ['product', 'checkout', 'confirmation'];

const textValue = (value, limit = 256) => typeof value === 'string' && !/[\u0000-\u001f]/.test(value) ? value.trim().slice(0, limit) : '';
const money = value => Number.isFinite(value) && value >= 0 && value <= 999999999 ? Math.round((value + Number.EPSILON) * 100) / 100 : null;

export function normalizeUserData(input, {phonePrefix = null} = {}) {
    if (!input || typeof input !== 'object') return null;
    const result = {};
    const email = typeof input.email === 'string' ? input.email.replace(/^[\s\u200B-\u200D\u2060\u180E]+|[\s\u200B-\u200D\u2060\u180E]+$/gu, '').toLowerCase() : '';
    if (isValidEmail(email)) result.email = email;
    const phone = normalizeE164Phone(input.phone_number, {defaultPrefix: phonePrefix});
    if (phone) result.phone_number = phone;
    const address = {};
    for (const key of ['first_name', 'last_name']) {
        const name = textValue(input.address?.[key], 128).normalize('NFC').toLowerCase()
            .replace(/^(?:(?:prof|doc|ing|arch|mgr|bc|mudr|judr|rndr|phdr|pharmdr|mvdr|thdr|paeddr|dr|mr|mrs|ms)\.?\s+)+/u, '')
            .replace(/(?:[,\s]+(?:ph\.?d\.?|csc\.?|dis\.?))+$/u, '').trim().replace(/\s+/g, ' ');
        if (name) address[key] = name;
    }
    const postal = textValue(input.address?.postal_code, 24);
    if (postal && /^[\p{L}\p{N} -]+$/u.test(postal)) address.postal_code = postal;
    const country = textValue(input.address?.country, 256).toUpperCase();
    if (/^[A-Z]{2}$/.test(country)) address.country = country;
    if (Object.keys(address).length) result.address = address;
    return Object.keys(result).length ? result : null;
}

// Rebuild at both transport boundaries. Never spread form, order or message data.
export function analyticsPayload(input, {allowUserData = false} = {}) {
    if (!input || typeof input !== 'object') return null;
    const withUserData = payload => {
        const userData = allowUserData ? normalizeUserData(input.user_data) : null;
        if (userData) payload.user_data = userData;
        return payload;
    };
    if (!input.event) {
        if (!pageTypes.includes(input.page_type)) return null;
        const result = {page_type: input.page_type, user_type: 'b2c'};
        if (typeof input.language === 'string' && /^[a-z]{2}$/.test(input.language)) result.language = input.language;
        return result;
    }
    if (input.event === 'page_view' || input.event === 'form_submit_error') return {event: input.event};
    if (input.event === 'generate_lead') {
        if (!['free_registration', 'waitlist'].includes(input.lead_source) || !currencies(input.currency) || input.value !== 0) return null;
        return withUserData({event: 'generate_lead', currency: input.currency, value: 0, lead_source: input.lead_source});
    }
    const source = input.ecommerce;
    if (!ecommerceEvents.has(input.event) || !source || !currencies(source.currency) ||
        !Array.isArray(source.items) || !source.items.length || source.items.length > 200) return null;
    const items = [];
    for (const item of source.items) {
        const price = money(item?.price);
        const name = textValue(item?.item_name);
        if (!item || !productId(item.item_id) || !name || price === null || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 9999) return null;
        items.push({item_id: item.item_id, item_name: name, price, quantity: item.quantity});
    }
    // Integer cents keep values such as 0.10 × 3 stable across both boundaries.
    const ecommerce = {currency: source.currency, items, value: items.reduce((sum, item) => sum + Math.round(item.price * 100) * item.quantity, 0) / 100};
    if (input.event === 'add_payment_info' || input.event === 'purchase') {
        if (!['bank_transfer', 'card', 'free'].includes(source.payment_type)) return null;
        ecommerce.payment_type = source.payment_type;
    }
    if (input.event === 'purchase') {
        if (!orderSymbol(source.transaction_id)) return null;
        ecommerce.transaction_id = source.transaction_id;
    }
    const result = {event: input.event, ecommerce};
    return input.event === 'purchase' ? withUserData(result) : result;
}

export function publicFormLocation(location, {entry = false} = {}) {
    if (!location || !/^\/form\/[a-zA-Z0-9_-]+\/?$/.test(location.pathname)) return false;
    const query = new URLSearchParams(location.search);
    // Unknown parameters fail closed, including every capability/payment alias.
    if ([...query.keys()].some(key => !['lang', 'embed', 'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'gclid', 'fbclid'].includes(key))) return false;
    if (query.has('embed') && query.get('embed') !== '1') return false;
    return !location.hash || (!entry && ['#order-preview', '#order-result', '#seat-selection'].includes(location.hash));
}

export function publicFormAttributionSearch(location) {
    if (!location || !/^\/form\/[a-zA-Z0-9_-]+\/?$/.test(location.pathname)) return '';
    const result = new URLSearchParams();
    for (const [key, value] of new URLSearchParams(location.search)) {
        if (['lang', 'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'gclid', 'fbclid'].includes(key)) result.append(key, value);
    }
    const search = result.toString();
    return search ? `?${search}` : '';
}

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

// Future consent integration belongs here. This is the sole loading decision.
// Consent itself is deliberately outside this contract.
export function shouldLoadFormIntegrations(win, entryAllowed = publicFormLocation(win.location, {entry: true}), {purpose = 'scripts', enhancedConversions = false, hostUserData = false} = {}) {
    if (!entryAllowed || !documentEntryAllowed(win) || !publicFormLocation(win.location) || hasBrowserSession(win)) return false;
    const embedded = win.self !== win.top || new URLSearchParams(win.location.search).has('embed');
    if (purpose === 'user_data') return enhancedConversions === true && (!embedded || hostUserData === true);
    return purpose === 'scripts' && !embedded;
}

export class FormDataLayer {
    constructor({win = window, model, bridge, entryAllowed, session = hasBrowserSession}) {
        this.win = win; this.model = model; this.bridge = bridge; this.session = session;
        this.entryAllowed = (entryAllowed ?? publicFormLocation(win.location, {entry: true})) && documentEntryAllowed(win);
        this.previous = [];
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
                        this.catalog.set(String(product.id), {item_id: `product_${product.id}`, item_name: product.title, price: Number(product.price), quantity: 1, currency});
                    }
                }
                visit(field.subFields);
            }
        };
        visit(model.visibleFields || model.relatedFields);
    }
    cancelPending() { this.observation = (this.observation || 0) + 1; }
    dispose() { this.cancelPending(); this.disposed = true; }
    enabled() { return !this.disposed && this.entryAllowed && !this.model.demoSimulation && !this.model.offerBundle && publicFormLocation(this.win.location) && !this.session(this.win); }
    emit(input) {
        if (!this.enabled()) return false;
        const payload = analyticsPayload(input, {allowUserData: this.userDataAllowed()});
        if (!payload) return false;
        try {
            // Embedded documents never own tags or scripts. Only the opted-in host consumes pushes.
            if (new URLSearchParams(this.win.location.search).get('embed') === '1' || this.win.self !== this.win.top) {
                this.bridge?.track(payload);
                return true;
            }
            this.win.dataLayer ||= [];
            if (payload.ecommerce || payload.event === 'generate_lead') this.win.dataLayer.push({ecommerce: null, user_data: null});
            this.win.dataLayer.push(payload);
            if (['purchase', 'generate_lead'].includes(payload.event)) this.win.dataLayer.push({user_data: null});
            return true;
        } catch { return false; } // An analytics consumer must never break checkout.
    }

    page(page_type) {
        const language = this.win.document.documentElement.lang?.slice(0, 2);
        this.emit({page_type, language});
        this.emit({event: 'page_view'});
    }
    groups(event, items, extra = {}) {
        for (const currency of new Set(items.map(item => item.currency))) {
            this.emit({event, ecommerce: {currency, items: items.filter(item => item.currency === currency), ...extra}});
        }
    }
    view() {
        this.page('product');
        const items = [...this.catalog.values()];
        this.groups('view_item', items);
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
                    this.catalog.set(String(product.id), {item_id: `product_${product.id}`, item_name: product.title, price: Number(product.price), quantity: 1, currency});
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
            if (version === this.observation) this.update(session.payload, session);
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
    userDataAllowed() {
        return shouldLoadFormIntegrations(this.win, this.entryAllowed, {purpose: 'user_data',
            enhancedConversions: this.model.data?.analytics?.enhanced_conversions === true,
            hostUserData: this.bridge?.dataLayer === true && this.bridge?.dataLayerUserData === true});
    }
    contact(payload, form) {
        if (!this.userDataAllowed()) return null;
        const values = {};
        let phonePrefix = null;
        for (const field of this.model.visibleFields || []) {
            if (field.isHidden || field.isTicketField) continue;
            const entry = payload?.fields?.find(value => Object.hasOwn(value, String(field.id)));
            if (entry) values[field.type] = entry[String(field.id)];
            if (field.type === 'phone') {
                const input = form?.querySelector(`[name="${field.id}"]`);
                const prefixes = this.model.data?.phone_prefixes;
                phonePrefix = input?.dataset.phonePrefix || (Array.isArray(prefixes) && prefixes.length === 1 ? prefixes[0] : null);
            }
        }
        // A free-form address and nationality are not evidence of postal code
        // or country of residence. Only explicit structured values are eligible.
        const address = values.address && typeof values.address === 'object' ? values.address : {};
        return normalizeUserData({email: values.email, phone_number: values.phone,
            address: {first_name: values.name, last_name: values.surname,
                postal_code: values.postal_code || address.postal_code, country: values.country || address.country}}, {phonePrefix});
    }
    confirmed(data, waitlist = false, userData = null) {
        this.page('confirmation');
        const order = data?.ticketOrder?.order;
        const payment = order?.payment_info;
        if (waitlist || payment?.amount === 0) {
            const currency = payment?.currency_code || this.previous[0]?.currency || 'CZK';
            this.emit({event: 'generate_lead', currency, value: 0, lead_source: waitlist ? 'waitlist' : 'free_registration', user_data: userData});
            return;
        }
        const purchase = analyticsPayload(data?.ticketOrder?.analytics);
        if (purchase?.event !== 'purchase' || !this.enabled()) return;
        // Server receipts omit analytics on replay. Browser storage is a second
        // fence for duplicate callbacks and a retained response after reload.
        const key = `festapp-purchase:${purchase.ecommerce.transaction_id}`;
        try {
            if (this.win.localStorage.getItem(key)) return;
            this.win.localStorage.setItem(key, '1');
        } catch { return; } // No durable deduplication means no purchase.
        this.emit({...purchase, user_data: userData});
    }
}

// Each document gets one owner. The guard lives until unload, since removing a
// script node or destroying a FormPage cannot revoke code already executed.
const integrationDocuments = new WeakMap();
const originalDocumentWindow = globalThis.window;
const originalDocumentURL = originalDocumentWindow?.location?.href;
const originalSaleOpening = Boolean(originalDocumentWindow?.__festappSaleOpeningLink);
function documentEntryAllowed(win) {
    if (win !== originalDocumentWindow || !originalDocumentURL) return true;
    if (originalSaleOpening) return false;
    const original = new URL(originalDocumentURL);
    if (publicFormLocation(original, {entry: true})) return true;
    // A clean catalogue may enter a form through the router. Private documents
    // and query/fragment data stripped during routing must never become eligible.
    return (['/', '/events'].includes(original.pathname) || /^\/unit\/[1-9]\d*\/?$/.test(original.pathname)) &&
        publicFormLocation({pathname: '/form/entry', search: original.search, hash: original.hash}, {entry: true});
}

export function installFormIntegrationGuard(win, auth, {navigate = (url, replace) => replace ? win.location.replace(url) : win.location.assign(url), reload = () => win.location.reload()} = {}) {
    if (integrationDocuments.has(win)) return integrationDocuments.get(win);
    const documentPath = win.location.pathname;
    const replaceHistory = win.history.replaceState.bind(win.history);
    const state = {leaving: false, cancelScripts: false};
    // An attempted navigation can be cancelled or be only a fragment change.
    // Only pagehide proves this document is being left; it must not disarm the guard early.
    win.addEventListener('pagehide', () => { state.leaving = true; }, true);
    const leave = (url, replace = false) => {
        if (state.leaving) return;
        state.cancelScripts = true;
        if (!url) { reload(); return; }
        const target = new URL(url, win.location.href);
        const sameDocument = target.origin === win.location.origin && target.pathname === win.location.pathname && target.search === win.location.search;
        navigate(target.href, replace);
        if (sameDocument) reload(); // assigning only a hash does not unload scripts
    };
    state.leaveWithReturn = (value, path, destination, navigateExternal) => {
        state.cancelScripts = true;
        replaceHistory(value, '', path);
        navigateExternal(destination);
    };
    const safe = url => url.origin === win.location.origin && url.pathname === documentPath && publicFormLocation(url);
    for (const method of ['pushState', 'replaceState']) {
        const original = win.history[method].bind(win.history);
        win.history[method] = (value, title, target) => {
            if (target != null) {
                const url = new URL(target, win.location.href);
                if (!safe(url)) { leave(url.href, method === 'replaceState'); return; }
            }
            return original(value, title, target);
        };
    }
    const check = event => {
        if (event?.type === 'pageshow') state.leaving = false;
        if (event?.type === 'visibilitychange' && win.document.visibilityState === 'hidden') return;
        if (!safe(new URL(win.location.href)) || hasBrowserSession(win)) {
            event?.stopImmediatePropagation?.();
            leave();
        }
    };
    for (const event of ['popstate', 'hashchange', 'storage', 'pageshow', 'focus']) win.addEventListener(event, check, true);
    win.document.addEventListener('visibilitychange', check, true);
    // The SDK notifies after installing a session. Reload immediately, including
    // sign-ins propagated from another tab; this is a guard, not origin isolation.
    auth?.onAuthStateChange((_event, session) => { if (session) leave(); });
    integrationDocuments.set(win, state);
    return state;
}

export function navigateWithFormReturnContext(win, value, returnPath, destination, navigate) {
    const guard = integrationDocuments.get(win);
    if (guard) guard.leaveWithReturn(value, returnPath, destination, navigate);
    else {
        win.history.replaceState(value, '', returnPath);
        navigate(destination);
    }
}

export function loadFormIntegrations({win = window, settings, auth, entryAllowed, guardOptions} = {}) {
    if (typeof auth?.onAuthStateChange !== 'function' || !shouldLoadFormIntegrations(win, entryAllowed) ||
        integrationDocuments.has(win)) return false;
    const container = typeof settings?.gtm_container === 'string' && /^GTM-[A-Z0-9]{4,32}$/.test(settings.gtm_container) ? settings.gtm_container : null;
    const code = typeof settings?.scripts === 'string' && Array.from(settings.scripts).length <= FORM_MEASUREMENT_SCRIPT_LIMIT ? settings.scripts : '';
    if (!container && !code) return false;
    const state = installFormIntegrationGuard(win, auth, guardOptions);
    const append = script => {
        if (state.leaving || state.cancelScripts || !shouldLoadFormIntegrations(win, entryAllowed)) return false;
        win.document.head.append(script);
        return true;
    };
    if (container) {
        win.dataLayer ||= [];
        try { win.dataLayer.push({'gtm.start': Date.now(), event: 'gtm.js'}); }
        catch { return false; }
        const script = win.document.createElement('script');
        script.async = true;
        script.src = `https://www.googletagmanager.com/gtm.js?id=${container}`;
        script.referrerPolicy = 'no-referrer';
        append(script);
    }
    if (code) {
        // A template is inert and is never inserted in the live document. Only
        // freshly constructed script elements, with approved attributes, execute.
        const template = win.document.createElement('template');
        template.innerHTML = code;
        const sources = [...template.content.querySelectorAll('script')];
        const runNext = index => {
            if (index >= sources.length) return;
            const source = sources[index];
            const script = win.document.createElement('script');
            const type = source.getAttribute('type');
            if (type && !['text/javascript', 'application/javascript', 'module'].includes(type)) { runNext(index + 1); return; }
            if (type) script.type = type;
            if (source.hasAttribute('src')) {
                let url;
                try { url = new URL(source.getAttribute('src')); } catch { runNext(index + 1); return; }
                if (url.protocol !== 'https:' || url.username || url.password) { runNext(index + 1); return; }
                script.src = url.href;
                script.async = source.hasAttribute('async');
                script.defer = source.hasAttribute('defer');
                for (const attribute of ['integrity', 'crossorigin']) if (source.hasAttribute(attribute)) script.setAttribute(attribute, source.getAttribute(attribute));
                script.referrerPolicy = 'no-referrer';
            } else script.textContent = source.textContent;
            const waits = script.hasAttribute('src') || script.type === 'module';
            if (waits) {
                const next = () => runNext(index + 1);
                script.addEventListener('load', next, {once: true});
                script.addEventListener('error', next, {once: true});
            }
            if (append(script) && !waits) runNext(index + 1);
        };
        runNext(0);
    }
    return true;
}
