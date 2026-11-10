// Advanced measurement with consent state and bounded conversion contacts.
export const measurementProtocol = 3;
// Pure contract. Every receiver rebuilds the payload independently.
const ecommerceEvents = new Set(['view_item', 'add_to_cart', 'remove_from_cart', 'begin_checkout', 'add_payment_info', 'purchase']);
export const currencies = value => typeof value === 'string' && /^[A-Z]{3}$/.test(value);
const productId = value => typeof value === 'string' && /^product_[1-9]\d{0,15}$/.test(value);
const eventIdentity = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const contactEmail = value => typeof value === 'string' && value.length <= 254 && /^[^\s@\u0000-\u001f\u007f]+@[^\s@\u0000-\u001f\u007f]+\.[^\s@\u0000-\u001f\u007f]+$/.test(value);
const contactPhone = value => typeof value === 'string' && /^\+[1-9]\d{7,14}$/.test(value);
const pageTypes = ['product', 'checkout', 'confirmation', 'sale_opening'];

export const measurementNamespace = 'festapp-measurement';
export const measurementId = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value);

// Saved purposes. A boolean is the earlier API: true grants analytics only.
export function measurementConsent(input) {
    if (input === true) return {analytics: true, marketing: false};
    return {analytics: input?.analytics === true, marketing: input?.marketing === true};
}

// Optional host cookie snapshot, scoped to the current purposes at every boundary.
export function measurementHostIdentity(input, choice) {
    const consent = measurementConsent(choice), result = {};
    if (!input || typeof input !== 'object' || Array.isArray(input)) return result;
    for (const [name, value] of Object.entries(input)) {
        const analytics = /^_ga(?:_[A-Z0-9]+)?$/.test(name);
        const marketing = ['_gcl_aw', '_gcl_gb', '_gcl_au', '_fbp', '_fbc'].includes(name);
        if ((analytics && consent.analytics || marketing && consent.marketing) &&
            typeof value === 'string' && value.length <= 512 && /^[A-Za-z0-9._$-]+$/.test(value)) {
            result[name] = value;
            if (Object.keys(result).length === 10) break;
        }
    }
    return result;
}

// Pages project hostnames are separate sites on the Public Suffix List. A
// shared workers.dev account or sibling custom domains are not this profile.
export function measurementOrigin(value, local = false) {
    try {
        const url = new URL(value);
        if (url.origin !== value || url.username || url.password) return null;
        if (url.protocol === 'https:' && /^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\.pages\.dev$/.test(url.hostname)) return value;
        if (local && url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname)) return value;
    } catch { /* Invalid deployment configuration fails closed. */ }
    return null;
}

// The single campaign/click allowlist for the URL gate, host handshake and runtime.
export const campaignKeys = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'utm_id', 'gclid', 'gbraid', 'wbraid', 'gad_source', 'gad_campaignid', 'srsltid', 'fbclid', 'sznclid', 'ttclid', 'msclkid'];
// Direct visits may pass linker and preview signals to the runtime URL only.
export const measurementSignalKeys = ['_gl', 'gtm_debug'];
export function measurementSignals(input) {
    const result = {};
    for (const key of measurementSignalKeys) {
        const value = input?.[key];
        if (typeof value === 'string' && value.length >= 1 && value.length <= (key === '_gl' ? 2048 : 256) &&
            !/[@\u0000-\u001f\u007f-\u009f]/.test(value) &&
            (key !== '_gl' || /^[A-Za-z0-9*._-]+$/.test(value))) result[key] = value;
    }
    return result;
}
const unsafeText = /[@\u0000-\u001f\u007f-\u009f]/;

export function campaignContext(input) {
    const result = {};
    for (const key of campaignKeys) {
        if (typeof input?.[key] === 'string' && input[key].length >= 1 && input[key].length <= 256 && !unsafeText.test(input[key])) result[key] = input[key];
    }
    return result;
}

export function attributionContext(input) {
    try {
        const page = new URL(input.page_location);
        if (!['https:', 'http:'].includes(page.protocol) || page.username || page.password || page.search || page.hash ||
            !/^\/form\/[a-zA-Z0-9_-]+\/?$/.test(page.pathname)) return null;
        const result = {page_location: page.href, form_embedded: input.form_embedded === true};
        if (input.page_referrer) {
            const referrer = new URL(input.page_referrer);
            if (['https:', 'http:'].includes(referrer.protocol) && !referrer.username && !referrer.password)
                result.page_referrer = referrer.origin + '/';
        }
        return {...result,...campaignContext(input)};
    } catch { return null; }
}

// Only validated public context and allowlisted campaign values reach tag URLs.
export function measurementPageLocation(context) {
    const verified = attributionContext(context);
    if (!verified) return null;
    const url = new URL(verified.page_location);
    for (const [key, value] of Object.entries(campaignContext(verified))) url.searchParams.set(key, value);
    return url.href;
}

const textValue = (value, limit = 256) => typeof value === 'string' && !/[\u0000-\u001f]/.test(value) ? value.trim().slice(0, limit) : '';
// Optional public catalog labels. A rejected label is omitted, never the item.
const itemLabel = value => typeof value === 'string' && !unsafeText.test(value) ? value.trim().slice(0, 100) : '';
const money = value => Number.isFinite(value) && value >= 0 && value <= 999999999 ? Math.round((value + Number.EPSILON) * 100) / 100 : null;

// Only these two bounded fields pass. Anything else, or a malformed value, is left out.
function contactUserData(input) {
    const result = {};
    if (contactEmail(input?.email)) result.email = input.email;
    if (contactPhone(input?.phone_number)) result.phone_number = input.phone_number;
    return Object.keys(result).length ? result : null;
}

// Rebuild at every transport boundary. Never spread form, order or message data.
export function analyticsPayload(input) {
    if (!input || typeof input !== 'object') return null;
    const withUserData = payload => {
        const user_data = contactUserData(input.user_data);
        return user_data ? {...payload, user_data} : payload;
    };
    if (!input.event) {
        if (!pageTypes.includes(input.page_type)) return null;
        const result = {page_type: input.page_type, user_type: 'b2c'};
        if (typeof input.language === 'string' && /^[a-z]{2}$/.test(input.language)) result.language = input.language;
        return result;
    }
    if (['page_view', 'form_start', 'form_submit_error'].includes(input.event)) return {event: input.event};
    if (input.event === 'generate_lead') {
        if (!['free_registration', 'waitlist', 'sale_opening_notification'].includes(input.lead_source) || !currencies(input.currency) || input.value !== 0 || !eventIdentity(input.event_id)) return null;
        return withUserData({event: 'generate_lead', currency: input.currency, value: 0, lead_source: input.lead_source, event_id: input.event_id});
    }
    const source = input.ecommerce;
    if (!ecommerceEvents.has(input.event) || !source || !currencies(source.currency) ||
        !Array.isArray(source.items) || !source.items.length || source.items.length > 200) return null;
    const items = [];
    for (const item of source.items) {
        const price = money(item?.price);
        const name = textValue(item?.item_name);
        if (!item || !productId(item.item_id) || !name || price === null || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 9999) return null;
        const entry = {item_id: item.item_id, item_name: name, price, quantity: item.quantity};
        for (const key of ['item_category', 'item_brand']) {
            const label = itemLabel(item[key]);
            if (label) entry[key] = label;
        }
        items.push(entry);
    }
    // Integer cents keep values such as 0.10 × 3 stable across both boundaries.
    const cents = items.reduce((sum, item) => sum + Math.round(item.price * 100) * item.quantity, 0);
    if (!Number.isSafeInteger(cents)) return null;
    const value = cents / 100;
    if (Math.round(value * 100) !== cents) return null;
    const ecommerce = {currency: source.currency, items, value};
    if (input.event === 'add_payment_info' || input.event === 'purchase') {
        if (!['bank_transfer', 'card', 'free'].includes(source.payment_type)) return null;
        ecommerce.payment_type = source.payment_type;
    }
    if (input.event === 'purchase') {
        if (!eventIdentity(source.transaction_id)) return null;
        ecommerce.transaction_id = source.transaction_id;
    }
    const result = {event: input.event, ecommerce};
    return input.event === 'purchase' ? withUserData(result) : result;
}

// The sole projection from the stable wire contract to the destination dataLayer.
// Transport peers keep page_view on the wire, including across rolling upgrades.
export function measurementDataLayerPayload(input, {embedded = false, pageContext = null} = {}) {
    const payload = analyticsPayload(input);
    if (!payload) return null;
    // A shared host layer cannot infer an event's context from its last push:
    // another embed may have published in between. Rebuild only public fields.
    const page = payload.event
        ? analyticsPayload({page_type: pageContext?.page_type, language: pageContext?.language})
        : null;
    const eventContext = payload.event
        ? {page_type: page?.page_type ?? null, user_type: 'b2c', language: page?.language ?? null}
        : {};
    return {...eventContext, ...payload,
        ...(payload.event === 'page_view' && embedded === true ? {event: 'form_page_view'} : {}),
        form_embedded: embedded === true};
}

// Identity of the SQL snapshot that actually supplies the runtime code.
export function measurementManifest(policy, formLink) {
    if (!policy || policy.measurement_protocol !== measurementProtocol || !Number.isSafeInteger(policy.organization) || !Number.isSafeInteger(policy.unit) || policy.organization<1 || policy.unit<1 ||
        !Number.isSafeInteger(policy.runtime_revision) || policy.runtime_revision<1 ||
        !Number.isSafeInteger(policy.policy_revision) || policy.policy_revision<1 ||
        typeof policy.processing_revision !== 'string' || !policy.processing_revision || policy.processing_revision.length>128 ||
        policy.profile !== 'gtm-v1' || !measurementId(formLink) ||
        JSON.stringify(policy.required_purposes) !== JSON.stringify(['analytics', 'marketing'])) return null;
    return {measurement_protocol:measurementProtocol, organization:policy.organization, unit:policy.unit, form_link:formLink,
        measurement_consent_bridge:policy.measurement_consent_bridge === true,
        processing_revision:policy.processing_revision, runtime_revision:policy.runtime_revision,
        policy_revision:policy.policy_revision, profile:policy.profile, required_purposes:['analytics','marketing']};
}
export const sameMeasurementManifest = (a,b) => !!a && !!b &&
    ['measurement_protocol','organization','unit','form_link','processing_revision','runtime_revision','policy_revision','profile','required_purposes']
        .every(key => JSON.stringify(a[key]) === JSON.stringify(b[key])) &&
    (a.measurement_consent_bridge === true) === (b.measurement_consent_bridge === true);
