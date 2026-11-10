// Read-only consent projection. Google's internal state is undocumented, so only
// boolean entries are understood. A present but broken source fails closed.
const keys = ['analytics_storage', 'ad_storage', 'ad_user_data', 'ad_personalization'];
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
// The runtime grants ad_storage, ad_user_data and ad_personalization together,
// so marketing requires an explicit grant for all three types.
const project = state => ({analytics:state.analytics_storage === true,
    marketing:state.ad_storage === true && state.ad_user_data === true && state.ad_personalization === true});
function createReader(win) {
    let layerRef, lastEntry, index = 0, defaults = {}, updates = {}, regional = new Set();
    return () => {
        try {
            const entries = win.google_tag_data?.ics?.entries;
            if (entries !== undefined) {
                if (!object(entries)) return project({});
                const state = {};
                for (const key of keys) {
                    const entry = entries[key];
                    if (entry === undefined) continue;
                    if (!object(entry)) { state[key] = false; continue; }
                    const value = entry.update !== undefined ? entry.update : entry.default;
                    // Google creates entries for types the website never set (e.g.
                    // ad_user_data on OneTrust sites): no value means missing.
                    if (value === undefined) continue;
                    state[key] = value === true;
                }
                return {...project(state), ...(typeof win.__tcfapi !== 'undefined' ? {marketing:false} : {})};
            }
            const layer = win.dataLayer;
            if (!Array.isArray(layer)) return project({});
            // Websites may trim or replace old entries; if the last entry read is no
            // longer where it was, re-read the whole queue instead of trusting the cursor.
            if (layer !== layerRef || layer.length < index || (index > 0 && layer[index - 1] !== lastEntry)) {
                layerRef = layer; index = 0; defaults = {}; updates = {}; regional = new Set();
            }
            while (index < layer.length) {
                const command = layer[index++];
                lastEntry = command;
                if (Object.prototype.toString.call(command) !== '[object Arguments]') continue;
                const [kind, action, values] = command;
                if (kind !== 'consent' || !['default', 'update'].includes(action) || !object(values)) continue;
                // The visitor's region is unknown here: a regional default makes that
                // purpose undecidable until the website's CMP sends an update.
                if (action === 'default' && 'region' in values) {
                    for (const key of keys) if (Object.hasOwn(values, key)) regional.add(key);
                    continue;
                }
                const target = action === 'update' ? updates : defaults;
                for (const key of keys) if (Object.hasOwn(values, key)) target[key] = values[key] === 'granted';
            }
            const state = {...defaults, ...updates};
            for (const key of regional) if (!Object.hasOwn(updates, key)) state[key] = false;
            return {...project(state), ...(typeof win.__tcfapi !== 'undefined' ? {marketing:false} : {})};
        } catch {
            layerRef = undefined; lastEntry = undefined; index = 0; defaults = {}; updates = {}; regional = new Set();
            return project({});
        }
    };
}
export const readHostConsentMode = win => createReader(win)();
// Whether the website exposes any Consent Mode state at all. Without it a linked
// visit has no source and keeps the form's own notice.
export function hasHostConsentMode(win) {
    try {
        const entries = win.google_tag_data?.ics?.entries;
        // A Google tag without Consent Mode still creates entries, but only with
        // `implicit` flags; only a default or an update means the website set consent.
        if (entries !== undefined) {
            if (!object(entries)) return true;
            if (Object.values(entries).some(entry => !object(entry) || entry.default !== undefined || entry.update !== undefined)) return true;
        }
        const layer = win.dataLayer;
        return Array.isArray(layer) && layer.some(command => Object.prototype.toString.call(command) === '[object Arguments]' && command[0] === 'consent');
    } catch { return false; }
}

// Linked visits only: the website has decided once its CMP sent any update, or
// the projected state grants a purpose (a CMP restoring a saved choice as the
// default). Denied or missing defaults alone are undecided; regional defaults
// stay denied and decide nothing. The automatic iframe bridge does not use this.
export function hostConsentModeDecided(win) {
    if (!hasHostConsentMode(win)) return false;
    try {
        const entries = win.google_tag_data?.ics?.entries;
        const updated = (object(entries) && Object.values(entries).some(entry => object(entry) && entry.update !== undefined)) ||
            (Array.isArray(win.dataLayer) && win.dataLayer.some(command => Object.prototype.toString.call(command) === '[object Arguments]' &&
                command[0] === 'consent' && command[1] === 'update' && object(command[2])));
        if (updated) return true;
        const choice = readHostConsentMode(win);
        return choice.analytics || choice.marketing;
    } catch { return false; }
}

// Polling keeps the host page untouched: no dataLayer or push interception.
// Each listener is notified only when the projected choice changes.
// `linked` reads null while the website is undecided, so a linked visit also
// ends when a decided state is cleared. The iframe bridge keeps the default.
export function createHostConsentMode(win, {linked = false} = {}) {
    const listeners = new Set();
    const reader = createReader(win);
    const read = linked ? () => { const choice = reader(); return hostConsentModeDecided(win) ? choice : null; } : reader;
    let timer = null, last = null, delay = null;
    const schedule = () => {
        let next = 1000;
        try { if (win.google_tag_data?.ics) next = 250; } catch { /* Retry conservatively. */ }
        if (timer !== null && next === delay) return;
        if (timer !== null) win.clearInterval(timer);
        delay = next; timer = win.setInterval(tick, delay);
    };
    const tick = () => {
        if (!listeners.size) return;
        schedule();
        const next = JSON.stringify(read());
        if (next === last) return;
        last = next;
        for (const listener of listeners) { try { listener(); } catch { /* Other frames still update. */ } }
    };
    return {
        read() { return read(); },
        subscribe(listener) {
            listeners.add(listener);
            last ??= JSON.stringify(read());
            schedule();
            return () => {
                listeners.delete(listener);
                if (!listeners.size && timer !== null) { win.clearInterval(timer); timer = null; last = null; }
            };
        },
    };
}
