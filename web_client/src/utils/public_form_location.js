import {campaignKeys, measurementSignalKeys} from '../components/forms/form_measurement_contract.js';
import {readCheckoutOrigin} from '../services/checkout_origin.js';
import {parseOrderLocation, parseWaitlistLocation} from '../components/forms/customer_order_location.js';

export function publicCheckoutLocation(location) {
    if (publicFormLocation(location, {checkout: true})) return true;
    if (location?.pathname !== '/order') return false;
    const query = new URLSearchParams(location.search);
    if (query.has('admin') || query.has('preview')) return false;
    if (['token', 'order_id', 'offer_id', 'waitlist'].some(key => query.getAll(key).length > 1)) return false;
    try { return Boolean(parseOrderLocation(location)?.token || parseWaitlistLocation(location)?.token); }
    catch { return false; }
}

export function publicFormLocation(location, {entry = false, checkout = false} = {}) {
    if (!location || !/^\/form\/[a-zA-Z0-9_-]+\/?$/.test(location.pathname)) return false;
    const query = new URLSearchParams(location.search);
    if (checkout && query.has('checkout_origin')) {
        try { readCheckoutOrigin(location); }
        catch { return false; }
        query.delete('checkout_origin');
    }
    // Unknown parameters fail closed, including every capability/payment alias.
    if ([...query.keys()].some(key => !['lang', 'embed', ...campaignKeys, ...measurementSignalKeys].includes(key))) return false;
    if (query.has('embed') && query.get('embed') !== '1') return false;
    return !location.hash || (!entry && ['#order-preview', '#order-result', '#seat-selection'].includes(location.hash));
}

export function publicFormAttributionSearch(location) {
    if (!location || !/^\/form\/[a-zA-Z0-9_-]+\/?$/.test(location.pathname)) return '';
    const result = new URLSearchParams();
    for (const [key, value] of new URLSearchParams(location.search)) {
        if (['lang', ...campaignKeys].includes(key)) result.append(key, value);
    }
    const search = result.toString();
    return search ? `?${search}` : '';
}


// Retain the original document safety context without changing router or Auth.
const originalDocumentWindow = globalThis.window;
const originalDocumentURL = originalDocumentWindow?.location?.href;
const originalSaleOpening = Boolean(originalDocumentWindow?.__festappSaleOpeningLink);
export function documentEntryAllowed(win) {
    if (win !== originalDocumentWindow || !originalDocumentURL) return true;
    if (originalSaleOpening) return false;
    const original = new URL(originalDocumentURL);
    if (publicFormLocation(original, {entry: true})) return true;
    // A clean catalogue may enter a form through the router. Private documents
    // and query/fragment data stripped during routing must never become eligible.
    return (['/', '/events'].includes(original.pathname) || /^\/unit\/[1-9]\d*\/?$/.test(original.pathname)) &&
        publicFormLocation({pathname: '/form/entry', search: original.search, hash: original.hash}, {entry: true});
}
