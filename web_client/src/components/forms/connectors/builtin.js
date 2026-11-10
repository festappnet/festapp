/** Ledger methods share registration and server capability projections. */
export function builtinPaymentConnector(id, confirmation, currencies) {
    return Object.freeze({
        id, labelKey: id, hintKey: `${id}Hint`, confirmation, currencies,
        quote(order) { return {...order, payment_method: id}; },
        availability(value) {
            const projection = value?.[id];
            return {configured: projection?.configured === true, recipient: null,
                // Released bank payloads could omit the bank object.
                available: projection == null ? id === 'bank' && value?.available?.includes(id) : projection.available === true,
                unavailableReason: projection?.reason?.code ?? 'unavailable'};
        },
    });
}
export const bankPaymentConnector = builtinPaymentConnector('bank', 'bank_event', ['CZK', 'EUR', 'USD']);
export const cashPaymentConnector = builtinPaymentConnector('cash', 'local_commit', ['CZK', 'EUR', 'PLN', 'USD', 'GBP']);
