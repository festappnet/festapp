// Cookiebot's SDK has no public policy revision. The organizer archives a CBID,
// origin and effective-date mapping; consent IDs are not policy versions.
const events = ['CookiebotOnConsentReady', 'CookiebotOnLoad', 'CookiebotOnAccept',
    'CookiebotOnDecline', 'CookiebotOnDialogDisplay'];
const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);
const instant = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value) &&
    Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
// Measured on Cookiebot uc.js (Chromium, Firefox, WebKit): the SDK keeps the
// tab's last state in memory. A decision in another tab or an expired/removed
// cookie leaves hasResponse, consent.* and consentID unchanged until reload.
// Only the persisted record's stamp is checked against this tab's consentID;
// other cookie fields (categories, ver, utc, region) are not interpreted.
const consentId = value => typeof value === 'string' && value.length <= 256 && /^[A-Za-z0-9+/=_-]+$/.test(value) && !/^-?[01]$/.test(value);
function persisted(doc, id) {
    const cookies = doc.cookie.split(';').map(value => value.trim()).filter(value => value.startsWith('CookieConsent='));
    if (cookies.length !== 1) return false;
    let value;
    try { value = decodeURIComponent(cookies[0].slice('CookieConsent='.length)); } catch { return false; }
    // Exactly one stamp field, equal to this tab's ID (the ID charset has no quotes).
    const key = `stamp:'${id}'`, at = value.indexOf(key);
    return value.startsWith('{') && value.endsWith('}') && (value.match(/[{,]stamp:/g) || []).length === 1 &&
        at > 0 && '{,'.includes(value[at - 1]) && ',}'.includes(value[at + key.length]);
}
function loader(win, config) {
    const scripts = [...win.document.querySelectorAll('script[src]')].filter(script => {
        const url = new URL(script.src, win.document.baseURI);
        return url.origin === 'https://consent.cookiebot.com' && url.pathname === '/uc.js';
    });
    if (scripts.length !== 1) return null;
    const script = scripts[0], url = new URL(script.src);
    const attribute = script.getAttribute('data-cbid'), query = url.searchParams.getAll('cbid');
    // Ordinary embeds carry only id, src and data-cbid; the consent mode comes from
    // the account configuration and is checked at runtime, not from attributes.
    if (query.length > 1 || (!attribute && !query.length) ||
        [attribute, ...query].filter(value => value !== null).some(value => !uuid(value) || value.toLowerCase() !== config.cbid)) return null;
    return {tcf:!!script.getAttribute('data-framework') || !!url.searchParams.get('data-framework')};
}
export function createCookiebotSource(win, input) {
    let config;
    try {
        config = typeof input === 'string' ? JSON.parse(input) : {...input};
        const origin = new URL(config.origin);
        if (config.provider !== 'cookiebot' || ![config.organization, config.unit].every(value => Number.isSafeInteger(value) && value > 0) ||
            typeof config.consentRevision !== 'string' || !/^[a-f0-9]{32}$/.test(config.consentRevision) || !uuid(config.cbid) ||
            origin.origin !== config.origin || origin.protocol !== 'https:' || !instant(config.consentValidFrom) ||
            !Number.isSafeInteger(config.maxAgeSeconds) || config.maxAgeSeconds <= 0 || config.maxAgeSeconds > 365 * 86400) config = null;
        else config = Object.freeze({...config, cbid:config.cbid.toLowerCase(), validFrom:Date.parse(config.consentValidFrom)});
    } catch { config = null; }
    const listeners = new Set();
    let timer, last, pending = false;
    const read = scope => {
        try {
            if (!config || pending || win.location.origin !== config.origin || (scope && (scope.organization !== config.organization ||
                scope.unit !== config.unit || scope.consentRevision !== config.consentRevision))) return null;
            const script = loader(win, config), cmp = win.Cookiebot, consent = cmp?.consent;
            // Opt-in comes from the documented runtime state: GDPR applies and the
            // saved choice is explicit. hasResponse is false while the renew dialog
            // is open although the saved choice still applies (measured), so it
            // must be boolean but does not gate; the persisted consent ID does.
            if (!script || consent?.method !== 'explicit' || consent.necessary !== true ||
                ![consent.preferences, consent.statistics, consent.marketing, cmp.consented, cmp.declined, cmp.hasResponse].every(value => typeof value === 'boolean') ||
                cmp.regulations?.gdprApplies !== true || cmp.regulations.ccpaApplies !== false ||
                typeof cmp.regulations.lgpdApplies !== 'boolean' || consent.services !== undefined ||
                // Undocumented account mode; when exposed it must be an opt-in mode.
                (cmp.responseMode !== undefined && !['optin', 'leveloptin', 'inlineoptin'].includes(cmp.responseMode))) return null;
            const accepted = consent.preferences || consent.statistics || consent.marketing;
            if (cmp.consented !== accepted || cmp.declined !== !accepted) return null;
            const id = cmp.consentID, utc = cmp.consentUTC?.getTime(), now = win.Date.now();
            // consentUTC can lead Date.now() by a few ms right after a choice (measured).
            if (!consentId(id) || consent.stamp !== id || !Number.isSafeInteger(utc) || utc < config.validFrom ||
                utc > now + 60000 || now - utc >= config.maxAgeSeconds * 1000) return null;
            // Cookiebot writes storage and its cached API non-atomically. Until
            // both agree, no reader may reuse the previous grant: the same
            // mismatch also means withdrawal in another tab or cookie removal.
            if (!persisted(win.document, id)) return null;
            return {consentRevision:config.consentRevision, analytics:consent.statistics,
                marketing:consent.marketing && !script.tcf && typeof win.__tcfapi === 'undefined'};
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
