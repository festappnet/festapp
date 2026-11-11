import {measurementConsent} from './form_measurement_contract.js';

// Keep the pinned Klaro 0.7.21 choice/draft model at this adapter boundary.
// Confirm a verified remote choice only in that model, without saveConsents or
// storage changes. Null retires the visit choice without deleting shared cookies.
export function applyKlaroVisitChoice(manager, choice, draft = null) {
    const purposes = measurementConsent(choice);
    manager.confirmed = false;
    manager.savedConsents = {...purposes};
    manager.updateConsent('analytics', purposes.analytics && (!draft || draft.analytics === true));
    manager.updateConsent('marketing', purposes.marketing && (!draft || draft.marketing === true));
    manager.confirmed = choice !== null;
    manager.applyConsents();
}

// The same saved-choice adapter is used by standalone Klaro and embedding hosts.
// It only reports the saved choice; a changed draft is never reported as a grant.
export function bindKlaroConsent(manager, setConsent) {
    let disposed = false;
    const saved = service => manager.confirmed === true && manager.savedConsents?.[service] === true &&
        manager.getConsent(service) === true;
    const sync = () => {
        const granted = {analytics: false, marketing: false};
        try {
            granted.analytics = saved('analytics');
            // Optional: a host manager without this service grants analytics only.
            granted.marketing = saved('marketing');
        } catch { granted.analytics = granted.marketing = false; /* Missing/broken CMP remains denied. */ }
        if (!disposed) setConsent(granted);
    };
    const watcher = {update: sync};
    const disconnect = () => {
        if (disposed) return;
        disposed = true;
        try { manager.unwatch(watcher); } finally { setConsent(false); }
    };
    try { manager.watch(watcher); sync(); }
    catch (error) {
        try { disconnect(); } catch { /* The failed source must not retain its watcher. */ }
        throw error;
    }
    return disconnect;
}
