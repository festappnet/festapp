/** Stripe's browser protocol. Shared payment UI never knows its hosts or fields. */
export const stripePaymentConnector = Object.freeze({
    id: 'stripe',
    payPath: '/stripe/pay',
    returnPath: '/stripe/return',
    historyKey: 'festappPayment',
    labelKey: 'stripe',
    hintKey: 'stripeHint',
    quote(order, quote) {
        return {...order, payment_method: this.id, payment_type: 'full',
            expected_payment_amount_minor: quote.amountMinor, expected_payment_currency: quote.currency,
            stripe_connection_id: quote.connectionId, payment_surface: quote.surface};
    },
    validateCheckoutUrl(value) {
        const url = new URL(value);
        if (url.protocol !== 'https:' || url.hostname !== 'checkout.stripe.com' || url.username || url.password || url.port)
            throw new Error('payment_checkout_url_invalid');
        return url.toString();
    },
    availability(value, surface) {
        const canonical = value.providers != null;
        value = canonical ? (value.providers[this.id] ?? {}) : value;
        const reasons = new Set(['not_configured','paused','stripe_restricted','model_unverified','recipient_changed','payments_disabled','return_origin_unavailable','currency_unsupported','deposit_unsupported','surcharge_unsupported','fakturoid_unsupported','sale_ending','surface_unverified','organizer_unavailable']);
        const recipient = typeof value.recipient?.connectionId === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value.recipient.connectionId)
            ? {connectionId: value.recipient.connectionId, name: typeof value.recipient.name === 'string' ? value.recipient.name : null} : null;
        const allowed = Array.isArray(value.supportedSurfaces) && value.supportedSurfaces.includes(surface);
        return {configured: canonical ? value.configured === true : value.configured?.stripe === true, recipient,
            available: (canonical ? value.available === true : value.available?.includes(this.id)) && !!recipient && allowed,
            unavailableReason: (canonical ? value.available === true : value.available?.includes(this.id)) && !allowed ? 'surface_unverified' : reasons.has(value.reason?.code ?? value.stripeUnavailableReason) ? (value.reason?.code ?? value.stripeUnavailableReason) : 'unavailable'};
    },
});
