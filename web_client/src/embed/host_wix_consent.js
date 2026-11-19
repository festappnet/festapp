import {purchaseObservation, auditDecision} from './purchase_observation.js';
import {consentValidity} from './host_consent_validity.js';
// Wix @wix/site consentPolicyManager's synchronous saved-policy boundary.
// Default policies never import; creation dates gate ordinary measurement only.
export function createWixConsentSource(win, input) {
    let config;
    try {
        config = typeof input === 'string' ? JSON.parse(input) : {...input};
        if (config.provider !== 'wix' || ![config.organization,config.unit].every(v => Number.isSafeInteger(v) && v > 0) ||
            !/^[a-f0-9]{32}$/.test(config.consentRevision) || config.origin !== win.location.origin || !consentValidity(config)) config = null;
    } catch { config = null; }
    const listeners = new Set();
    const observePurchase = purchaseObservation(win);
    let pending = false, timer, last;
    const read = scope => {
        try {
            if (!config || pending || (scope && (scope.organization !== config.organization || scope.unit !== config.unit || scope.consentRevision !== config.consentRevision))) return null;
            const saved = win.consentPolicyManager?.getCurrentConsentPolicy();
            const p = saved?.policy;
            const date = saved?.createdDate;
            const timestamp = typeof date === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?(?:Z|[+-]\d\d:\d\d)$/.test(date)
                ? Date.parse(date) : Object.prototype.toString.call(date) === '[object Date]' ? date.getTime() : NaN;
            const now = win.Date.now();
            if (saved?.defaultPolicy !== false || p?.essential !== true ||
                !['functional','analytics','advertising','dataToThirdParty'].every(k => typeof p[k] === 'boolean')) return null;
            const ordinaryValid = consentValidity(config)(timestamp, now);
            const unsupportedConsent = typeof win.__tcfapi !== 'undefined';
            const marketing = !unsupportedConsent && p.advertising && p.dataToThirdParty;
            const purchaseConsent = unsupportedConsent ? null : observePurchase({
                source:'wix',...auditDecision(timestamp),
                ad_storage:marketing,ad_user_data:marketing,ad_personalization:marketing,
            });
            return {purchaseConsent,...(!ordinaryValid ? {ordinaryValid:false} : {}),consentRevision:config.consentRevision,analytics:ordinaryValid && p.analytics,marketing:ordinaryValid && marketing};
        } catch { return null; }
    };
    const tick = () => {
        const next = JSON.stringify(read());
        if (next === last) return;
        last = next;
        for (const listener of [...listeners]) { try { listener(); } catch { /* Independent consumers. */ } }
    };
    const changed = () => {
        if (pending) return;
        pending = true;
        win.queueMicrotask(() => { pending = false; tick(); });
    };
    return {read, subscribe(listener) {
        listeners.add(listener);
        if (listeners.size === 1 && config) {
            last = JSON.stringify(read());
            win.document.addEventListener('consentPolicyChanged', changed);
            win.document.addEventListener('visibilitychange', tick);
            win.addEventListener('focus',tick);
            timer = win.setInterval(tick,1000); // Other tabs, expiry and host API availability.
        }
        return () => {
            listeners.delete(listener);
            if (!listeners.size) { win.clearInterval(timer); win.document.removeEventListener('consentPolicyChanged',changed);win.document.removeEventListener('visibilitychange',tick);win.removeEventListener('focus',tick); }
        };
    }};
}
