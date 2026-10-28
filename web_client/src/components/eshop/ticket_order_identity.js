import { browserStorage } from '../../services/browser_storage.js';
export function canonicalCommandPayload(value) {
    if (Array.isArray(value)) return value.map(canonicalCommandPayload);
    if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonicalCommandPayload(value[key])]));
    return value;
}
export function terminalOrderResponse(data) {
    const code = data?.code ?? data?.data?.code;
    return Number.isInteger(code) && (code === 200 || code >= 1000 && code < 2000 || code >= 400 && code < 500 && ![408, 429].includes(code));
}
export async function claimTicketOrderIdentity(endpoint, payload, principal, storage = browserStorage) {
    // Transport provenance can refresh without changing the purchase intent.
    // Keep ordinary fingerprints unchanged and pin the original proof alongside
    // the pending command so its SQL payload hash also remains unchanged.
    const { checkoutOrigin, ...purchase } = payload;
    const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(canonicalCommandPayload([endpoint, payload.form, purchase]))));
    const fingerprint = Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, '0')).join('');
    const key = `client_command_pending:ticket_order:${fingerprint}`;
    let saved;
    try { saved = JSON.parse(storage.getItem(key) || 'null'); } catch { throw new Error('PAYMENT_RECOVERY_REQUIRED'); }
    if (saved && saved.principal !== (principal ?? null)) throw new Error('PAYMENT_RECOVERY_PRINCIPAL_CHANGED');
    if (!saved) {
        // Older requests did not bind their actor. Do not silently replace an
        // outstanding old command with a newly authenticated purchase.
        if (storage.getItem('client_command_pending:ticket_order')) throw new Error('PAYMENT_RECOVERY_REQUIRED');
        saved = { commandId: crypto.randomUUID(), clientId: crypto.randomUUID(), principal: principal ?? null };
        if (checkoutOrigin !== undefined) saved.checkoutOrigin = checkoutOrigin;
        storage.setItem(key, JSON.stringify(saved));
    }
    const orderDetails = { ...purchase };
    if (saved.checkoutOrigin !== undefined) orderDetails.checkoutOrigin = saved.checkoutOrigin;
    return { ...saved, orderDetails, complete: () => storage.removeItem(key) };
}
