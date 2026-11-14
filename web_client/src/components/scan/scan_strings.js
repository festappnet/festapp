import { OrderItemStrings } from '../eshop/order_item_strings.js';
export const tr = (key, args = {}, hasTickets = true) =>
    OrderItemStrings.text(`Scanner.${key}`, { args, hasTickets, fallback: key });
export const reasonText = (reason, hasTickets = true) => tr(`reason_${reason}`, {}, hasTickets);
export const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
