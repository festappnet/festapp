export function parseOrderLocation(location) {
    if (location.pathname !== '/order' || location.hash) return null;
    const params = new URLSearchParams(location.search || '');
    if (params.get('waitlist') === '1') return null;
    if (!params.has('order_id') && !params.has('token')) return null;
    const token = params.get('token');
    const id = params.get('order_id');
    if (params.getAll('token').length !== 1 || params.getAll('order_id').length !== 1 ||
        !/^[a-f0-9]{64}$/.test(token || '') || !/^[1-9][0-9]*$/.test(id || '') || !Number.isSafeInteger(Number(id))) throw new Error('INVALID_CAPABILITY');
    return { token, orderId: Number(id) };
}
export const orderOverviewSearch = scope => `?${new URLSearchParams({ order_id: String(scope.orderId), token: scope.token })}`;

export function parseWaitlistLocation(location) {
    if (location.pathname !== '/order' || location.hash) return null;
    const p = new URLSearchParams(location.search);
    if (p.get('waitlist') !== '1') return null;
    const token = p.get('token');
    const offerId = p.get('offer_id');
    const orderId = p.get('order_id');
    if (!p.has('token')) {
        // The marker only selects session-authenticated access. The server
        // still checks the signed-in actor's occasion editor permission.
        if (p.get('admin') === '1' && p.getAll('admin').length === 1 &&
            p.getAll('offer_id').length === 1 && !p.has('order_id') &&
            /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(offerId || '')) {
            return { token: null, offerId };
        }
        throw new Error('INVALID_CAPABILITY');
    }
    if (!/^[a-f0-9]{64}$/i.test(token || '')) throw new Error('INVALID_CAPABILITY');
    if (offerId && /^[a-f0-9-]{36}$/i.test(offerId)) return { token, offerId };
    if (orderId && /^\d+$/.test(orderId)) return { token, orderId: Number(orderId) };
    throw new Error('INVALID_CAPABILITY');
}
