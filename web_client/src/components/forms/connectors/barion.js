/** Sandbox browser protocol. Public availability remains server-owned. */
export const barionPaymentConnector = Object.freeze({
    id: 'barion', payPath: '/payments/barion/pay', returnPath: '/payments/barion/return',
    historyKey: 'festappPayment:barion', labelKey: 'card', hintKey: 'cardHint',
    quote(order, quote) {
        return {...order, payment_method: this.id, payment_type: 'full',
            payment_connection_id: quote.connectionId, payment_surface: quote.surface,
            expected_payment_amount_minor: quote.amountMinor, expected_payment_currency: quote.currency};
    },
    validateCheckoutUrl(value) {
        const url = new URL(value), keys = [...url.searchParams.keys()];
        if (url.protocol !== 'https:' || url.hostname !== 'secure.test.barion.com' || url.username || url.password || url.port || url.hash ||
            url.pathname.toLowerCase() !== '/pay' || keys.length !== 1 || keys[0].toLowerCase() !== 'id' ||
            !/^(?:[a-f0-9]{32}|[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})$/i.test(url.searchParams.get(keys[0]) ?? ''))
            throw new Error('payment_checkout_url_invalid');
        return url.toString();
    },
    availability(value) {
        const projection = value?.providers?.barion ?? {};
        // No production/merchant eligibility is implied by a registered sandbox.
        return {configured: projection.configured === true, recipient: projection.recipient ?? null,
            available: false, unavailableReason: 'sandbox_only'};
    },
});
