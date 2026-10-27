import { z } from 'zod';
import { orderId } from './orders.mjs';

// An explicit allowlist, not a blacklist of today's form types. The ordinary
// operator API retains its full DTO; the public ChatGPT client never receives
// buyer fields, registration answers, internal notes or product free text.
const text = z.string().nullable();
const order = z.strictObject({
    id: orderId, occasionId: orderId, symbol: text, state: z.string(),
    ticketCount: z.number().int().nonnegative(), price: text, currency: text,
    allowedActions: z.array(z.literal('view')),
    payment: z.strictObject({ amount: text, paid: text, returned: text }).nullable(),
});
export const publicOrderPage = z.strictObject({
    occasionId: orderId, orders: z.array(order).max(50), nextCursor: orderId.nullable(),
});
export const publicOrderSearch = z.string().regex(/^[A-Z0-9]{10}$/)
    .describe('Exact 10-character order symbol. Names and email addresses are not supported.');
export function publicOrders(data, args) {
    return publicOrderPage.parse({
        occasionId: data.occasionId,
        // The canonical operator search also searches contacts. Never expose
        // a contact match or its pagination through the public symbol search.
        orders: data.orders.filter(row => !args.search || row.symbol === args.search).map(row => ({
            id: row.id, occasionId: row.occasionId, symbol: row.symbol, state: row.state,
            ticketCount: row.ticketCount, price: row.price, currency: row.currency,
            allowedActions: row.allowedActions.filter(action => action === 'view'),
            payment: row.payment && { amount: row.payment.amount, paid: row.payment.paid, returned: row.payment.returned },
        })),
        nextCursor: args.search ? null : data.nextCursor,
    });
}
