export const namespace = 'festapp-embed';
export const protocol = 1;
export const limits = Object.freeze({minHeight:120, legacyMinHeight:240, viewportMax:4000, heightMax:20000});
export const validId = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value);
export const viewport = value => Number.isFinite(value) && value >= limits.legacyMinHeight && value <= limits.viewportMax;
export const minimumHeight = offer => offer === limits.minHeight ? limits.minHeight : limits.legacyMinHeight;
const toChild = new Set(['init','viewport','theme','price-ready','price-activate','measurement-consent','measurement-ack']);
const toHost = new Set(['ready','resize','scroll-request','scroll-save','scroll-restore','scroll-discard','price','measurement-context','measurement-activate','analytics']);
const bounded = (value, min, max) => Number.isFinite(value) && value >= min && value <= max;
export function validMessage(data, destination) {
    if (!data || typeof data !== 'object' || Array.isArray(data) || data.namespace !== namespace || data.protocol !== protocol ||
        !(destination === 'child' ? toChild : toHost).has(data.type)) return false;
    if (data.type === 'ready') return true;
    if (!validId(data.instance)) return false;
    switch (data.type) {
        case 'init': case 'viewport': return viewport(data.viewportHeight);
        case 'resize': return bounded(data.height, limits.minHeight, limits.heightMax);
        case 'scroll-request': return bounded(data.y, 0, limits.heightMax) &&
            (data.height === undefined || bounded(data.height, 0, limits.heightMax)) &&
            (data.block === undefined || ['start','end','nearest'].includes(data.block));
        case 'scroll-save': case 'scroll-restore': case 'scroll-discard': return validId(data.snapshot);
        default: return true; // Measurement and presentation retain their domain validators.
    }
}
export function envelope(type, instance, values = {}) { return {namespace, protocol, type, instance, ...values}; }
