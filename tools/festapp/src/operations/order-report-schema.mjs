import { z } from 'zod';

// Shape of get_report_ws, shared by orders.report and reports.export.
// Older report producers may omit later blocks. Extensions stay on the wire.
const count = z.number().int().nonnegative();
const object = shape => z.object(shape).passthrough();
const decimal = z.union([z.string().regex(/^-?\d+(\.\d+)?$/), z.number()]);
const stateTotals = object({ total: count, by_state: z.array(object({ state: z.string(), count })).optional() });
const dayCount = object({ day: z.iso.date(), currency: z.string().nullable(), count });
const moneyFields = Object.fromEntries([
    'current_order_value', 'received', 'returned', 'net_received', 'manual_received', 'other_received',
    'deposit_received_gross', 'beyond_deposit_received_gross', 'stripe_received', 'stripe_refunded',
    'disputed', 'available_after_disputes', 'external_unattributed',
].map(key => [key, decimal.optional()]));
export const orderReportSchema = object({
    schema_version: z.literal(1),
    occasion: object({ id: z.string(), title: z.string() }).optional(),
    generated_at: z.iso.datetime({ offset: true }).optional(),
    spots: object({ total: count, occupied: count, free: count }).nullable().optional(),
    orders: stateTotals.optional(), tickets: stateTotals.optional(),
    valid: object({ tickets: stateTotals, orders: stateTotals.optional(),
        order_days: z.array(dayCount).optional(), ticket_days: z.array(dayCount).optional() }),
    money_by_currency: z.array(object({ currency: z.string().nullable(), ...moneyFields,
        has_deposits: z.boolean().optional() })).optional(),
    timeline: object({ order_timezone: z.string().optional(), payment_date_basis: z.string().optional(),
        orders: z.array(dayCount).optional(), tickets: z.array(dayCount).optional(),
        payments: z.array(object({ day: z.iso.date(), currency: z.string().nullable(), received: decimal, returned: decimal })).optional(),
    }).optional(),
    products: z.array(object({ product_id: z.string(), product_title: z.string(),
        type_id: z.string().nullable(), type_title: z.string().nullable(), confirmed_count: count })).optional(),
    ticket_batches: object(Object.fromEntries(['total', 'available', 'sold_active', 'voided_unsold', 'cancelled_after_sale']
        .map(key => [key, count]))).optional(),
    warnings: z.array(object({ code: z.string(), count: count.optional() })).optional(),
});
