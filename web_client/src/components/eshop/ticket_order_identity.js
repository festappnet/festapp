import { browserStorage } from '../../services/browser_storage.js';
export function canonicalCommandPayload(value) {
    if (Array.isArray(value)) return value.map(canonicalCommandPayload);
    if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonicalCommandPayload(value[key])]));
    return value;
}
export function terminalOrderResponse(data) {
    const code = data?.code ?? data?.data?.code;
    // SQL rolls back this admission rejection and freezes it in the receipt.
    // A new explicit attempt must not replay the same rejected command forever.
    if (code === 429 && (data?.errorCode ?? data?.data?.errorCode) === 'ABUSE_LIMIT_EXCEEDED') return true;
    return Number.isInteger(code) && (code === 200 || code >= 1000 && code < 2000 || code >= 400 && code < 500 && ![408, 429].includes(code));
}
const pendingOrderPrefix = 'client_command_pending:ticket_order:';

async function orderKey(endpoint, purchase) {
    const input = JSON.stringify(canonicalCommandPayload([endpoint, purchase.form, purchase]));
    const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
    const fingerprint = Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, '0')).join('');
    return pendingOrderPrefix + fingerprint;
}

function readPendingOrder(storage, key) {
    try { return JSON.parse(storage.getItem(key) || 'null'); }
    catch { throw new Error('PAYMENT_RECOVERY_REQUIRED'); }
}

export async function claimTicketOrderIdentity(endpoint, payload, principal, storage = browserStorage, {requirePending = false} = {}) {
    // Preserve the original proof; consent and optional matching can change on reload.
    const { checkoutOrigin, metaPurchaseConsent, ...purchase } = payload;
    const canonicalKey = await orderKey(endpoint, purchase);
    const actor = principal ?? null;
    let key = canonicalKey;
    let saved = readPendingOrder(storage, key);

    if (metaPurchaseConsent !== undefined) {
        // Old clients put the exact consent in the fingerprint. Recover such a
        // receipt when it is still identifiable without persisting the consent.
        let legacyConsent = metaPurchaseConsent;
        if (legacyConsent && typeof legacyConsent === 'object' && !Array.isArray(legacyConsent)) {
            const {matching, ...decision} = legacyConsent;
            legacyConsent = decision;
        }
        const legacyKey = await orderKey(endpoint, {...purchase,metaPurchaseConsent:legacyConsent});
        const legacy = readPendingOrder(storage, legacyKey);
        // Reread after hashing in case another caller claimed the canonical key.
        saved = readPendingOrder(storage, canonicalKey);
        if (saved && legacy && saved.commandId !== legacy.commandId) throw new Error('PAYMENT_RECOVERY_REQUIRED');
        if (!saved && legacy) {
            key = legacyKey;
            saved = legacy;
        }
    }

    if (saved && saved.principal !== actor) throw new Error('PAYMENT_RECOVERY_PRINCIPAL_CHANGED');
    if (!saved) {
        if (requirePending || storage.getItem('client_command_pending:ticket_order')) throw new Error('PAYMENT_RECOVERY_REQUIRED');
        // Old hashed keys cannot be tied back to a cart once the old consent is
        // gone. Require recovery for the same buyer instead of risking a replay
        // under a new command. Orders using the stable key are unaffected.
        const unknownLegacy = storage.keys(pendingOrderPrefix).some(pendingKey => {
            const pending = readPendingOrder(storage, pendingKey);
            return pending && pending.consentIndependent !== true && (pending.principal ?? null) === actor;
        });
        if (unknownLegacy) throw new Error('PAYMENT_RECOVERY_REQUIRED');
        saved = { commandId: crypto.randomUUID(), clientId: crypto.randomUUID(), principal: actor, consentIndependent: true };
        if (checkoutOrigin !== undefined) saved.checkoutOrigin = checkoutOrigin;
        storage.setItem(key, JSON.stringify(saved));
    }
    const orderDetails = { ...purchase };
    if (metaPurchaseConsent !== undefined) orderDetails.metaPurchaseConsent = metaPurchaseConsent;
    if (saved.checkoutOrigin !== undefined) orderDetails.checkoutOrigin = saved.checkoutOrigin;
    return { ...saved, orderDetails, complete: () => storage.removeItem(key) };
}
