import {validConsentBinding} from './measurement_consent_source.js';
const matchingTimestamp = Date.now();
const purposes = ['ad_storage','ad_user_data','ad_personalization'];
export function validMetaBrowserId(value) {
    return typeof value === 'string' && value.length <= 1024 && !/[\u0000-\u001f\u007f]/.test(value) && /^fb\.[0-9]{1,3}\.[0-9]{13}\.[A-Za-z0-9_-]{1,500}$/.test(value);
}
export function validMetaBrowserMatching(matching) {
    return Object.fromEntries(['fbp','fbc'].filter(key => validMetaBrowserId(matching?.[key])).map(key => [key,matching[key]]));
}

function samePurchaseScope(a, b) {
    return !!a && !!b && a.source === b.source && a.consentRevision === b.consentRevision &&
        a.websiteOrigin === b.websiteOrigin && a.binding?.id === b.binding?.id &&
        a.binding?.version === b.binding?.version;
}
export function samePurchaseDecision(a, b) {
    return samePurchaseScope(a, b) && purposes.every(key => a[key] === b[key]);
}

export function metaBrowserMatching(snapshot, win) {
    // Read identifiers only after all purposes and the source origin agree.
    if (!hasCurrentPurchaseConsent({purchaseConsent:snapshot,expiresAt:snapshot?.transportExpiresAt}) || snapshot.websiteOrigin !== win.location.origin) return {};
    const cookies = new Map();
    // The standalone form origin is shared by every organizer; only the
    // organizer's own website cookies (embed) can carry its Meta identifiers.
    if (snapshot.source !== 'klaro') try {
        for (const part of win.document.cookie.split(';')) {
            const [key,...value] = part.trim().split('=');
            if (!['_fbp','_fbc'].includes(key)) continue;
            try { cookies.set(key,decodeURIComponent(value.join('='))); } catch { /* Skip malformed cookies. */ }
        }
    } catch { /* A blocked cookie API does not hide a consented URL click. */ }
    const fbp = cookies.get('_fbp');
    let fbc = cookies.get('_fbc');
    const click = new URL(win.location.href).searchParams.get('fbclid');
    // A newer ad click in the URL wins over an older _fbc that Pixel has not refreshed yet.
    if (/^[A-Za-z0-9_-]{1,500}$/.test(click || '') && (!validMetaBrowserId(fbc) || fbc.split('.')[3] !== click))
        fbc = `fb.1.${Math.floor(win.performance?.timeOrigin || matchingTimestamp)}.${click}`;
    return {...(validMetaBrowserId(fbp) ? {fbp} : {}), ...(validMetaBrowserId(fbc) ? {fbc} : {})};
}
function hasCurrentDecision(choice, now) {
    const snapshot = choice?.purchaseConsent;
    return !!snapshot &&
        ['klaro','cookiebot','cookieconsent','wix','complianz'].includes(snapshot.source) &&
        /^[a-f0-9]{32}$/.test(snapshot.consentRevision || '') &&
        (snapshot.source === 'klaro' || validConsentBinding(snapshot.binding)) &&
        (choice.expiresAt === undefined || (Number.isFinite(choice.expiresAt) && choice.expiresAt > now));
}
export function hasCurrentPurchaseConsent(choice, now = Date.now()) {
    return hasCurrentDecision(choice,now) && purposes.every(key => choice.purchaseConsent[key] === true);
}
export function publicPurchaseDecision(snapshot) {
    if (!snapshot || typeof snapshot!=='object') return null;
    const {source,capturedAt,consentRevision,websiteOrigin,binding,ad_storage,ad_user_data,ad_personalization} = snapshot;
    const decidedAt = snapshot.decidedAt ?? snapshot.timestamp;
    return {source,capturedAt,...(decidedAt ? {decidedAt} : {}),consentRevision,websiteOrigin,ad_storage,ad_user_data,ad_personalization,
        ...(binding ? {binding:{id:binding.id,version:binding.version}} : {})};
}
export function currentPurchaseDenial(choice, now = Date.now()) {
    if (!hasCurrentDecision(choice,now) || !purposes.every(key => typeof choice.purchaseConsent[key] === 'boolean') || !purposes.some(key => choice.purchaseConsent[key] === false)) return null;
    return publicPurchaseDecision(choice.purchaseConsent);
}
export function purchaseConsentSnapshot(choice, notice, now = Date.now()) {
    if (!notice?.revision || !hasCurrentPurchaseConsent(choice,now)) return null;
    const snapshot = choice.purchaseConsent;
    if (snapshot.websiteOrigin !== notice.origin) return null;
    return {source:snapshot.source, capturedAt:new Date(now).toISOString(), ...((snapshot.decidedAt ?? snapshot.timestamp) ? {decidedAt:snapshot.decidedAt ?? snapshot.timestamp} : {}), consentRevision:snapshot.consentRevision,
        websiteOrigin:notice.origin, ad_storage:true, ad_user_data:true, ad_personalization:true,
        ...(snapshot.binding ? {binding:{id:snapshot.binding.id,version:snapshot.binding.version}} : {}),
        revision:notice.revision, ...(choice.expiresAt !== undefined ? {transportExpiresAt:choice.expiresAt} : {})};
}

function comparableDecisionAt(snapshot, observedAt) {
    const value = snapshot.decidedAt ?? snapshot.timestamp;
    if (typeof value !== 'string' ||
        !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value)) return null;
    const decision = Date.parse(value);
    if (!Number.isFinite(decision) || decision > observedAt ||
        new Date(decision).toISOString().slice(0, 19) !== value.slice(0, 19)) return null;
    return decision;
}

function olderDecision(denial, grant, now) {
    const deniedAt = comparableDecisionAt(denial, now);
    const acceptedAt = comparableDecisionAt(grant, Math.min(now, Date.parse(grant.capturedAt) || now));
    return deniedAt !== null && acceptedAt !== null && deniedAt < acceptedAt;
}

// The capability never enters the consent bridge or an analytics payload.
// Revocations are sticky and retried while this visit is alive. Disposal/tab
// closure simply stops observation; it does not withdraw durable consent.
export class PurchaseConsentOrders {
    constructor({revoke, clock = () => Date.now()}) { Object.assign(this,{revoke,clock}); this.orders=new Map(); }
    observe(choice) {
        this.choice=choice;
        const now = this.clock();
        const denial = currentPurchaseDenial(choice, now);
        if (denial) {
            for (const order of this.orders.values()) {
                if (samePurchaseScope(denial, order.snapshot) && !olderDecision(denial, order.snapshot, now)) {
                    order.revoked = true;
                    order.denial = denial;
                }
            }
        }
        this.flush();
    }
    capture(snapshot, notice) {
        if (!snapshot || !notice?.revision) return null;
        const order={snapshot:structuredClone(snapshot)};
        this.orders.set(order,order);
        this.observe(this.choice);
        return order;
    }
    canDispatch(order) {
        if (!this.orders.has(order)) return false;
        const expiresAt = order.snapshot.transportExpiresAt;
        if (!order.revoked && (expiresAt === undefined || expiresAt > this.clock())) {
            order.dispatched = true;
            return true;
        }
        // An earlier attempt could already have saved consent before its
        // response was lost. Keep observing until its capability is recovered.
        if (!order.dispatched) this.orders.delete(order);
        return false;
    }
    authorize(order, scope) {
        if (!this.orders.has(order) || !scope?.token || !Number.isSafeInteger(scope.orderId)) return;
        order.scope={...scope};
        this.observe(this.choice);
    }
    track(scope, snapshot, notice) {
        if (!scope?.token || !Number.isSafeInteger(scope.orderId)) return;
        this.authorize(this.capture(snapshot,notice),scope);
    }
    flush() {
        for (const [id,order] of this.orders) if(order.revoked && order.scope && !order.sending) {
            order.sending=true;
            Promise.resolve().then(()=>this.revoke(order.scope,order.denial)).then(ok=>{if(ok)this.orders.delete(id);})
                .catch(()=>{}).finally(()=>{order.sending=false;});
        }
    }
}
