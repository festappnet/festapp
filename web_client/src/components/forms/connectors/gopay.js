/** Explicit sandbox merchant storefronts. Public policy is resolved by SQL. */
export const goPayPaymentConnector = Object.freeze({
    id: 'gopay',
    payPath: '/payments/gopay/pay',
    returnPath: '/payments/gopay/return',
    historyKey: 'festappPayment',
    labelKey: 'card',
    hintKey: 'cardHint',
    checkoutReferrerPolicy: 'origin',
    quote(order, quote) {
        return {...order, payment_method: this.id, payment_type: 'full',
            payment_connection_id: quote.connectionId, payment_surface: quote.surface,
            expected_payment_amount_minor: quote.amountMinor, expected_payment_currency: quote.currency};
    },
    validateCheckoutUrl(value) {
        const url = new URL(value);
        if (url.origin !== 'https://gw.sandbox.gopay.com' || url.username || url.password ||
            url.search || url.hash || !/^\/gw\/v3\/[A-Za-z0-9_-]+$/.test(url.pathname)) throw new Error('payment_checkout_url_invalid');
        return url.href;
    },
    availability(value, surface) {
        const projection = value?.providers?.gopay;
        const recipient = projection?.recipient ?? null;
        const configured = projection?.configured === true;
        const available = configured && projection.available === true && recipient?.livemode === false &&
            Array.isArray(projection.supportedSurfaces) && projection.supportedSurfaces.includes(surface) &&
            recipient.storefrontOrigin === globalThis.location?.origin;
        return {configured, recipient, available, unavailableReason: available ? null : 'sandbox_only'};
    },
});

/** Move only a public form link before any personal data or reservation exists. */
export function goPayStorefrontUrl(payments, location) {
    const projection = payments?.providers?.gopay;
    const origin = projection?.recipient?.storefrontOrigin;
    if (location.origin !== 'https://vstupenky.online' || location.search || location.hash ||
        !/^\/form\/[A-Za-z0-9_-]+\/?$/.test(location.pathname) || projection?.available !== true ||
        projection.recipient?.livemode !== false ||
        !/^https:\/\/[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.vstupenky\.online$/.test(origin ?? '')) return null;
    return new URL(location.pathname, origin).href;
}
