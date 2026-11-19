import {measurementConsent} from './form_measurement_contract.js';
// One public scope/record contract for iframe adapters and linked visits. The
// revision belongs to the saved record or archived CMP-policy mapping, never
// to a value copied from the requested scope.
export function consentScope(policy, origin) {
    const revision = policy?.processingRevision ?? policy?.processing_revision;
    const purposes = policy?.requiredPurposes ?? policy?.required_purposes;
    if (![policy?.organization, policy?.unit].every(v => Number.isSafeInteger(v) && v > 0) ||
        typeof revision !== 'string' || !revision.length || revision.length > 128 ||
        (purposes !== undefined && (!Array.isArray(purposes) || purposes.length !== 2 ||
            !purposes.includes('analytics') || !purposes.includes('marketing')))) return null;
    const consentRevision = policy.consentRevision ?? policy.consent_revision;
    if (consentRevision !== undefined && (typeof consentRevision !== 'string' || !/^[a-f0-9]{32}$/.test(consentRevision))) return null;
    let binding = policy.binding, websiteOrigin = policy.websiteOrigin;
    if (policy.website_consent_bindings !== undefined) {
        if (!Array.isArray(policy.website_consent_bindings)) return null;
        const records = policy.website_consent_bindings.filter(b => b.websiteOrigin === origin);
        if (records.length > 1) return null;
        if (records.length) {
            if (records[0].effective !== true) return null;
            binding = {id:records[0].id, version:records[0].version}; websiteOrigin = origin;
        }
    }
    if (binding !== undefined && (!validConsentBinding(binding) || typeof websiteOrigin !== 'string')) return null;
    return {...(binding !== undefined ? {binding:{id:binding.id,version:binding.version}, websiteOrigin} : {}), organization:policy.organization, unit:policy.unit, processingRevision:revision, requiredPurposes:['analytics','marketing'],
        ...(consentRevision !== undefined ? {consentRevision} : {})};
}
export const validConsentBinding = b => !!b && typeof b.id === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(b.id) && Number.isSafeInteger(b.version) && b.version > 0;
export const sameConsentBinding = (a,b) => validConsentBinding(a) && validConsentBinding(b) && a.id === b.id && a.version === b.version;
export const managedConsentOrigin = (policy, origin) => Array.isArray(policy?.website_consent_bindings) && policy.website_consent_bindings.some(b => b.websiteOrigin === origin);
export const sameConsentScope = (a, b) => !!a && !!b && JSON.stringify(a) === JSON.stringify(b);
export function readConsentSource(source, scope) {
    if (!scope) return null;
    try {
        const value = source?.read({...scope, requiredPurposes:[...scope.requiredPurposes]});
        // Semantic records bind to the archived notice; old external adapters keep
        // their stricter processing-revision contract. Neither echoes a request.
        const matches = value?.consentRevision !== undefined
            ? scope.consentRevision !== undefined && value.consentRevision === scope.consentRevision
            : value?.processingRevision === scope.processingRevision;
        if (!matches || (scope.binding && !sameConsentBinding(value?.binding, scope.binding))) return null;
        if (value.ordinaryValid === false && (scope.includePurchaseConsent !== true || !value.purchaseConsent)) return null;
        const choice = {...measurementConsent(value), ...(value.ordinaryValid === false ? {ordinaryValid:false} : {})};
        if (!value.purchaseConsent) return choice;
        // CMP adapters explicitly project their archived purpose mapping. Generic
        // sources must supply each purpose; marketing alone never fills gaps.
        const purpose = key => {
            const direct = value[key], saved = value.purchaseConsent[key];
            if (direct === false || saved === false) return false;
            const grants = [value, value.purchaseConsent].filter(record => Object.hasOwn(record,key));
            return grants.length && grants.every(record => record[key] === true) ? true : undefined;
        };
        const projected = Object.fromEntries(['ad_storage','ad_user_data','ad_personalization'].map(key => [key,purpose(key)]));
        // Preserve complete partial refusals. A contradictory generic marketing
        // state must still never authorize a grant, independently of denial.
        if (!choice.marketing && value.ordinaryValid !== false && Object.values(projected).every(value => value === true))
            return {...choice,purchaseConsent:null};
        return {...choice, purchaseConsent:{source:value.purchaseConsent.source,capturedAt:value.purchaseConsent.capturedAt,
            ...((value.purchaseConsent.decidedAt ?? value.purchaseConsent.timestamp) ? {decidedAt:value.purchaseConsent.decidedAt ?? value.purchaseConsent.timestamp} : {}),
            consentRevision:value.consentRevision, binding:value.binding, websiteOrigin:scope.websiteOrigin,
            ...projected}};
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
