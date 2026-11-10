import {measurementConsent} from './form_measurement_contract.js';
// One public scope/record contract for iframe adapters and linked visits. The
// revision must come from the saved CMP record, never from the requested scope.
export function consentScope(policy) {
    const revision = policy?.processingRevision ?? policy?.processing_revision;
    const purposes = policy?.requiredPurposes ?? policy?.required_purposes;
    if (![policy?.organization, policy?.unit].every(v => Number.isSafeInteger(v) && v > 0) ||
        typeof revision !== 'string' || !revision.length || revision.length > 128 ||
        (purposes !== undefined && (!Array.isArray(purposes) || purposes.length !== 2 ||
            !purposes.includes('analytics') || !purposes.includes('marketing')))) return null;
    return {organization:policy.organization, unit:policy.unit, processingRevision:revision, requiredPurposes:['analytics','marketing']};
}
export const sameConsentScope = (a, b) => !!a && !!b && JSON.stringify(a) === JSON.stringify(b);
export function readConsentSource(source, scope) {
    if (!scope) return null;
    try {
        const value = source?.read({...scope, requiredPurposes:[...scope.requiredPurposes]});
        return value?.processingRevision === scope.processingRevision ? measurementConsent(value) : null;
    } catch { return null; }
}
export function createConsentSourceRegistry() {
    let current, configured = false, generation = 0;
    const listeners = new Set();
    const notify = () => { for (const listener of [...listeners]) { try { listener(); } catch { /* Independent consumers. */ } } };
    return {
        get configured() { return configured; },
        get generation() { return generation; },
        read:scope => readConsentSource(current?.source, scope),
        subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener); },
        connect(source) {
            if (typeof source?.read !== 'function' || typeof source?.subscribe !== 'function') return null;
            const record = {source};
            // Subscribe before granting. A broken replacement retires any old grant.
            configured = true; generation++;
            const old = current; current = null;
            try { old?.stop?.(); } catch { /* Retired callbacks are inert. */ }
            try {
                record.stop = source.subscribe(() => { if (current === record) notify(); });
                if (typeof record.stop !== 'function') throw new Error('Consent source must return a disposer');
                current = record;
            } catch { try { record.stop?.(); } catch { /* Denied. */ } }
            notify();
            return () => {
                if (current !== record) return;
                current = null;
                try { record.stop(); } finally { notify(); }
            };
        },
    };
}
