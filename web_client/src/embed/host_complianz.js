// Category-level Complianz opt-in records only. This is an organizer-configured
// coverage mapping, not an attestation by Google Consent Mode or by Festapp.
const events = ['cmplz_status_change', 'cmplz_banner_status', 'cmplz_fire_categories',
    'cmplz_cookie_warning_loaded', 'cmplz_revoke', 'cmplz_before_categories_consent'];
const disabled = value => value === undefined || value === false || value === 0 || value === '0';
const policyId = value => (typeof value === 'string' || Number.isSafeInteger(value)) &&
    /^[1-9][0-9]{0,15}$/.test(String(value)) ? String(value) : null;

export function createComplianzSource(win, input) {
    let config;
    try {
        config = typeof input === 'string' ? JSON.parse(input) : {...input};
        if (config?.provider !== 'complianz' || ![config.organization, config.unit].every(v => Number.isSafeInteger(v) && v > 0) ||
            typeof config.consentRevision !== 'string' || !/^[a-f0-9]{32}$/.test(config.consentRevision) || !policyId(config.policyId)) config = null;
        else config = Object.freeze({...config, policyId:policyId(config.policyId)});
    } catch { config = null; }
    const listeners = new Set();
    let timer, last, pending = false;
    const read = scope => {
        try {
            if (!config || pending || (scope && (scope.organization !== config.organization || scope.unit !== config.unit ||
                scope.consentRevision !== config.consentRevision))) return null;
            const cmp = win.complianz;
            if (cmp?.consenttype !== 'optin' || !disabled(cmp.forceEnableStats) || !disabled(cmp.consent_per_service) ||
                typeof win.cmplz_get_cookie !== 'function' || typeof win.cmplz_get_banner_status !== 'function' ||
                typeof win.cmplz_has_consent !== 'function' || win.cmplz_get_banner_status() !== 'dismissed' ||
                policyId(cmp.current_policy_id) !== config.policyId || policyId(win.cmplz_get_cookie('policy_id')) !== config.policyId) return null;
            // The public helper owns multisite prefixes. A dismissed banner alone
            // can be just its close button; require persisted category decisions.
            const stats = win.cmplz_get_cookie('statistics'), ads = win.cmplz_get_cookie('marketing');
            if (![stats, ads].every(value => ['allow', 'deny'].includes(value))) return null;
            // Per-service overrides cannot be projected into a blanket ad grant.
            const services = win.cmplz_get_cookie('consented_services');
            if (services && services !== '[]' && services !== '{}') return null;
            const analytics = win.cmplz_has_consent('statistics'), marketing = win.cmplz_has_consent('marketing');
            if (typeof analytics !== 'boolean' || typeof marketing !== 'boolean') return null;
            return {consentRevision:config.consentRevision, analytics:stats === 'allow' && analytics,
                marketing:ads === 'allow' && marketing && disabled(cmp.tcf_active) && typeof win.__tcfapi === 'undefined'};
        } catch { return null; }
    };
    const tick = () => {
        if (!listeners.size) return;
        const next = JSON.stringify(read());
        if (next === last) return;
        last = next;
        for (const listener of [...listeners]) { try { listener(); } catch { /* Independent consumers. */ } }
    };
    const changed = () => {
        if (pending) return;
        pending = true;
        // CMP writes categories sequentially, and decline dismisses before its
        // category writes. Never publish an intermediate snapshot from a hook.
        win.queueMicrotask(() => { pending = false; tick(); });
    };
    return {
        read,
        subscribe(listener) {
            listeners.add(listener);
            if (listeners.size === 1 && config) {
                last = JSON.stringify(read());
                for (const event of events) win.document.addEventListener(event, changed);
                timer = win.setInterval(tick, 1000); // Expiry and other-tab changes.
            }
            return () => {
                listeners.delete(listener);
                if (!listeners.size) {
                    win.clearInterval(timer); timer = undefined; last = undefined;
                    for (const event of events) win.document.removeEventListener(event, changed);
                }
            };
        },
    };
}
