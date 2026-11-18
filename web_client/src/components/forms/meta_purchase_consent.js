import {validConsentBinding} from './measurement_consent_source.js';
const purposes = ['ad_storage','ad_user_data','ad_personalization'];
function hasCurrentDecision(choice, now) {
    const snapshot = choice?.purchaseConsent;
    const timestamp = Date.parse(snapshot?.timestamp);
    return !!snapshot &&
        ['klaro','cookiebot','cookieconsent','wix'].includes(snapshot.source) &&
        /^[a-f0-9]{32}$/.test(snapshot.consentRevision || '') &&
        (snapshot.source === 'klaro' || validConsentBinding(snapshot.binding)) &&
        Number.isFinite(timestamp) && timestamp <= now && now - timestamp < 365*86400000 &&
        (choice.expiresAt === undefined || (Number.isFinite(choice.expiresAt) && choice.expiresAt > now));
}
export function hasCurrentPurchaseConsent(choice, now = Date.now()) {
    return hasCurrentDecision(choice,now) && purposes.every(key => choice.purchaseConsent[key] === true);
}
export function currentPurchaseDenial(choice, now = Date.now()) {
    if (!hasCurrentDecision(choice,now) || !purposes.some(key => choice.purchaseConsent[key] === false)) return null;
    const {source,timestamp,consentRevision,websiteOrigin,binding,ad_storage,ad_user_data,ad_personalization} = choice.purchaseConsent;
    return {source,timestamp,consentRevision,websiteOrigin,ad_storage,ad_user_data,ad_personalization,
        ...(binding ? {binding:{id:binding.id,version:binding.version}} : {})};
}
export function purchaseConsentSnapshot(choice, notice, now = Date.now()) {
    if (!notice?.revision || !hasCurrentPurchaseConsent(choice,now)) return null;
    const snapshot = choice.purchaseConsent;
    if (snapshot.websiteOrigin !== notice.origin) return null;
    return {source:snapshot.source, timestamp:snapshot.timestamp, consentRevision:snapshot.consentRevision,
        websiteOrigin:notice.origin, ad_storage:true, ad_user_data:true, ad_personalization:true,
        ...(snapshot.binding ? {binding:{id:snapshot.binding.id,version:snapshot.binding.version}} : {}),
        revision:notice.revision, ...(choice.expiresAt !== undefined ? {transportExpiresAt:choice.expiresAt} : {})};
}

// The capability never enters the consent bridge or an analytics payload.
// Revocations are sticky and retried while this visit is alive. Disposal/tab
// closure simply stops observation; it does not withdraw durable consent.
export class PurchaseConsentOrders {
    constructor({revoke, clock = () => Date.now()}) { Object.assign(this,{revoke,clock}); this.orders=new Map(); }
    observe(choice) {
        this.choice=choice;
        for (const order of this.orders.values()) {
            const denial=currentPurchaseDenial(choice,this.clock());
            if (denial && denial.websiteOrigin === order.snapshot.websiteOrigin &&
                denial.consentRevision === order.snapshot.consentRevision &&
                denial.source === order.snapshot.source &&
                denial.binding?.id === order.snapshot.binding?.id &&
                denial.binding?.version === order.snapshot.binding?.version &&
                Date.parse(denial.timestamp) > Date.parse(order.snapshot.timestamp)) order.revoked=true;
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
            Promise.resolve().then(()=>this.revoke(order.scope)).then(ok=>{if(ok)this.orders.delete(id);})
                .catch(()=>{}).finally(()=>{order.sending=false;});
        }
    }
}
