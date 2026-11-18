import {validConsentBinding} from './measurement_consent_source.js';
const purposes = ['ad_storage','ad_user_data','ad_personalization'];
export function purchaseConsentSnapshot(choice, notice, now = Date.now()) {
    const snapshot = choice?.purchaseConsent;
    const timestamp = Date.parse(snapshot?.timestamp);
    if (!notice?.revision || !snapshot || (snapshot.source === 'klaro' && choice?.marketing !== true) ||
        !['klaro','cookiebot','cookieconsent','wix'].includes(snapshot.source) ||
        !/^[a-f0-9]{32}$/.test(snapshot.consentRevision || '') ||
        (snapshot.source !== 'klaro' && !validConsentBinding(snapshot.binding)) ||
        !purposes.every(key => snapshot[key] === true) ||
        !Number.isFinite(timestamp) || timestamp > now || now - timestamp >= 365*86400000 ||
        snapshot.websiteOrigin !== notice.origin ||
        (choice.expiresAt !== undefined && (!Number.isFinite(choice.expiresAt) || choice.expiresAt <= now))) return null;
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
            const current=purchaseConsentSnapshot(choice,order.notice,this.clock());
            if (!current || current.consentRevision !== order.snapshot.consentRevision ||
                JSON.stringify(current.binding) !== JSON.stringify(order.snapshot.binding) || current.source !== order.snapshot.source) order.revoked=true;
        }
        this.flush();
    }
    capture(snapshot, notice) {
        if (!snapshot || !notice?.revision) return null;
        const order={snapshot:structuredClone(snapshot),notice:{...notice}};
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
