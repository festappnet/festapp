// Origin is presentation provenance only. The database verifies the signed
// context and binds its form; neither it nor a query instanceId grants rights.
export function readCheckoutOrigin(location) {
    const params = new URLSearchParams(location?.search || '');
    const contexts = params.getAll('checkout_origin');
    if (!contexts.length || !/^\/form\/[^/]+\/?$/.test(location?.pathname || '')) return null;
    if (contexts.length !== 1 || contexts[0].length > 2048 || !/^[A-Za-z0-9_-]+\.[0-9a-f]{64}$/.test(contexts[0])) {
        throw new Error('INVALID_CHECKOUT_ORIGIN');
    }
    return contexts[0];
}

export function withCheckoutOrigin(order, location = globalThis.location ?? globalThis.window?.location) {
    const checkoutOrigin = readCheckoutOrigin(location);
    return checkoutOrigin ? {...order, checkoutOrigin} : order;
}
