import { formatCurrency } from "./utilities.ts";

interface Product {
  id?: number;
  title?: string;
  price?: number;
  currency_code?: string;
}
interface TicketChange {
  id?: number;
  ticket_symbol?: string;
  products?: Product[];
  added?: Product[];
  removed?: Product[];
  changed?: { from: Product; to: Product }[];
}
export interface OrderChangeSummary {
  version: number;
  cancelledTickets: TicketChange[];
  removedTickets: TicketChange[];
  addedTickets: TicketChange[];
  productChanges: TicketChange[];
  referenceTotal: number;
  currentTotal: number;
  currencyCode: string;
  hasChanges: boolean;
}

const escape = (value: unknown): string => String(value ?? "").replace(
  /[&<>"']/g,
  (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!,
);

/** Render the canonical database summary. Ticket/product classification lives in SQL. */
export function generateChangeOverview(changes: OrderChangeSummary, lang: 'cs' | 'en' = 'cs'): string {
  if (!changes || changes.version !== 1) throw new Error('order_change_summary_unavailable');
  if (!changes.hasChanges) return '';
  const tr = {
    cs: {title: 'Změny v objednávce', cancelled: 'Stornované vstupenky', removedTickets: 'Odebrané vstupenky',
      addedTickets: 'Přidané vstupenky', ticket: 'Vstupenka', unnamed: 'bez označení',
      products: 'Změny produktů na vstupence', added: 'Přidané položky', removed: 'Odebrané položky', total: 'Celková cena'},
    en: {title: 'Changes in Your Order', cancelled: 'Cancelled tickets', removedTickets: 'Removed tickets',
      addedTickets: 'Added tickets', ticket: 'Ticket', unnamed: 'without a symbol',
      products: 'Product changes on ticket', added: 'Added items', removed: 'Removed items', total: 'Total price'},
  }[lang];
  const price = (product: Product) => escape(formatCurrency(Number(product.price) || 0, product.currency_code || changes.currencyCode));
  const row = (title: string, amount: string) => `<tr><td style="padding:4px 8px 4px 0">${title}</td><td style="text-align:right;white-space:nowrap">${amount}</td></tr>`;
  const products = (items: Product[], prefix = '') => items.map(p => row(`${prefix}${escape(p.title)}`, price(p))).join('');
  const section = (title: string, content: string) => content ? `<section style="margin-bottom:20px"><p style="font-weight:600">${title}</p><table style="width:100%;border-collapse:collapse"><tbody>${content}</tbody></table></section>` : '';
  const symbol = (ticket: TicketChange) => escape(ticket.ticket_symbol || tr.unnamed);
  const tickets = (title: string, items: TicketChange[]) => items.length ? `<section><h3>${title}</h3>${items.map(t => section(`${tr.ticket} ${symbol(t)}`, products(t.products ?? [])) || `<p>${tr.ticket} ${symbol(t)}</p>`).join('')}</section>` : '';
  let html = `<div style="margin:20px auto;padding:24px;font-family:sans-serif;color:#333;background-color:#f9fafb;border:1px solid #e2e8f0;border-radius:8px"><h2>${tr.title}</h2>`;
  html += tickets(tr.cancelled, changes.cancelledTickets);
  html += tickets(tr.removedTickets, changes.removedTickets);
  html += tickets(tr.addedTickets, changes.addedTickets);
  for (const ticket of changes.productChanges) {
    html += `<section><h3>${tr.products} ${symbol(ticket)}</h3>`;
    html += section(tr.added, products(ticket.added ?? [], '+ '));
    html += section(tr.removed, products(ticket.removed ?? [], '- '));
    html += section('', (ticket.changed ?? []).map(p => row(
      `${escape(p.from.title)} → ${escape(p.to.title)}`,
      `<s>${price(p.from)}</s> → <strong>${price(p.to)}</strong>`,
    )).join(''));
    html += '</section>';
  }
  if (changes.referenceTotal !== changes.currentTotal) html += `<p style="text-align:right;font-weight:bold">${tr.total}: <s>${escape(formatCurrency(changes.referenceTotal, changes.currencyCode))}</s> → ${escape(formatCurrency(changes.currentTotal, changes.currencyCode))}</p>`;
  return html + '</div>';
}
