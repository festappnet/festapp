// CookieConsent v3 category-level opt-in records. The organizer archives the
// notice/revision mapping; CMP state is not a cryptographic coverage attestation.
const events = ['cc:onConsent', 'cc:onChange', 'cc:onFirstConsent'];
const revision = value => Number.isSafeInteger(value) && value > 0;
const categoryName = value => typeof value === 'string' && value.length > 0 && value.length <= 128;
const disabled = value => value === undefined || value === false;
const timestamp = value => typeof value === 'string' && Number.isFinite(Date.parse(value));

export function createCookieConsentSource(win, input) {
    let config;
    try {
        config = typeof input === 'string' ? JSON.parse(input) : {...input};
        const categories = config.categories === undefined ? {analytics:'analytics', marketing:'marketing'} : config.categories;
        if (config.provider !== 'cookieconsent' || ![config.organization, config.unit].every(v => Number.isSafeInteger(v) && v > 0) ||
            typeof config.consentRevision !== 'string' || !/^[a-f0-9]{32}$/.test(config.consentRevision) || !revision(config.revision) ||
            !categoryName(categories?.analytics) || !categoryName(categories?.marketing) || categories.analytics === categories.marketing) config = null;
        else config = Object.freeze({...config, categories:Object.freeze({...categories})});
    } catch { config = null; }
    const listeners = new Set();
    let timer, last, pending = false;
    const read = scope => {
        try {
            if (!config || pending || (scope && (scope.organization !== config.organization || scope.unit !== config.unit ||
                scope.consentRevision !== config.consentRevision))) return null;
            const cmp = win.CookieConsent;
            if (cmp?.validConsent() !== true || cmp.getConfig('mode') !== 'opt-in' || cmp.getConfig('revision') !== config.revision) return null;
            // validConsent/acceptedCategory are cached by the library. Always read
            // storage too, including expirationTime (upstream v3 utils/cookies.js).
            const cookie = cmp.getCookie(), categories = cmp.getConfig('categories');
            if (cookie?.revision !== config.revision || !Array.isArray(cookie.categories) || !cookie.categories.every(categoryName) ||
                typeof cookie.consentId !== 'string' || !cookie.consentId || !timestamp(cookie.consentTimestamp) ||
                !timestamp(cookie.lastConsentTimestamp) || !Number.isFinite(cookie.expirationTime) || cookie.expirationTime <= win.Date.now() ||
                !cookie.services || typeof cookie.services !== 'object' || Array.isArray(cookie.services)) return null;
            const choice = {};
            for (const purpose of ['analytics', 'marketing']) {
                const name = config.categories[purpose], category = categories?.[name];
                if (!category || typeof category !== 'object' || !disabled(category.enabled) || !disabled(category.readOnly) ||
                    (category.services !== undefined && (!category.services || typeof category.services !== 'object' ||
                        Array.isArray(category.services) || Object.keys(category.services).length)) ||
                    !Array.isArray(cookie.services[name]) || cookie.services[name].length) return null;
                const accepted = cmp.acceptedCategory(name);
                // Stale other-tab state cannot create a grant or hide a refusal.
                if (typeof accepted !== 'boolean' || accepted !== cookie.categories.includes(name)) return null;
                choice[purpose] = accepted;
            }
            if (typeof win.__tcfapi !== 'undefined') choice.marketing = false;
            return {consentRevision:config.consentRevision, ...choice};
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
        win.queueMicrotask(() => { pending = false; tick(); });
    };
    return {read, subscribe(listener) {
        listeners.add(listener);
        if (listeners.size === 1 && config) {
            last = JSON.stringify(read());
            for (const event of events) win.addEventListener(event, changed);
            timer = win.setInterval(tick, 1000);
        }
        return () => {
            listeners.delete(listener);
            if (!listeners.size) {
                win.clearInterval(timer); timer = undefined; last = undefined;
                for (const event of events) win.removeEventListener(event, changed);
            }
        };
    }};
}
