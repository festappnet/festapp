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
  const palette = {
    removed: { text: '#991b1b', background: '#fef2f2', border: '#fecaca' },
    added: { text: '#166534', background: '#f0fdf4', border: '#bbf7d0' },
    changed: { text: '#1e3a5f', background: '#fffbeb', border: '#fde68a' },
  };
  type Tone = keyof typeof palette;
  const price = (product: Product) => escape(formatCurrency(Number(product.price) || 0, product.currency_code || changes.currencyCode));
  const row = (title: string, amount: string, tone: Tone) => `<tr><td style="padding:6px 8px 6px 0;color:${palette[tone].text};font-size:14px;line-height:1.5">${title}</td><td style="padding:6px 0 6px 8px;color:${palette[tone].text};font-size:14px;text-align:right;white-space:nowrap;font-weight:500;vertical-align:top">${amount}</td></tr>`;
  const products = (items: Product[], tone: Tone, prefix = '') => items.map(p => row(`${prefix}${escape(p.title)}`, price(p), tone)).join('');
  const section = (title: string, content: string, tone: Tone) => content ? `<p style="margin:12px 0 4px;font-size:13px;font-weight:600;color:${palette[tone].text}">${title}</p><table role="presentation" style="width:100%;border-collapse:collapse"><tbody>${content}</tbody></table>` : '';
  const card = (title: string, content: string, tone: Tone) => `<table role="presentation" style="width:100%;margin:0 0 16px;border-collapse:separate;border-spacing:0;background-color:${palette[tone].background};border:1px solid ${palette[tone].border};border-radius:8px"><tbody><tr><td style="padding:16px"><h3 style="margin:0 0 8px;font-size:16px;line-height:1.4;color:${palette[tone].text}">${title}</h3>${content}</td></tr></tbody></table>`;
  const symbol = (ticket: TicketChange) => escape(ticket.ticket_symbol || tr.unnamed);
  const tickets = (title: string, items: TicketChange[], tone: Tone, prefix: string) => items.length ? card(title, items.map(t => `<p style="margin:12px 0 4px;color:${palette[tone].text};font-size:14px;font-weight:600">${tr.ticket} ${symbol(t)}</p>` + (t.products?.length ? `<table role="presentation" style="width:100%;border-collapse:collapse"><tbody>${products(t.products, tone, prefix)}</tbody></table>` : '')).join(''), tone) : '';
  let html = `<div style="margin:20px auto;padding:24px;font-family:Arial,sans-serif;color:#1f2937;background-color:#f9fafb;border:1px solid #e2e8f0;border-radius:10px"><h2 style="margin:0 0 20px;padding-bottom:16px;border-bottom:1px solid #e2e8f0;font-size:20px;line-height:1.4;color:#1e3a5f">${tr.title}</h2>`;
  html += tickets(tr.cancelled, changes.cancelledTickets, 'removed', '- ');
  html += tickets(tr.removedTickets, changes.removedTickets, 'removed', '- ');
  html += tickets(tr.addedTickets, changes.addedTickets, 'added', '+ ');
  for (const ticket of changes.productChanges) {
    let content = section(tr.added, products(ticket.added ?? [], 'added', '+ '), 'added');
    content += section(tr.removed, products(ticket.removed ?? [], 'removed', '- '), 'removed');
    const changedRows = (ticket.changed ?? []).map(p => row(
      p.from.title === p.to.title ? escape(p.to.title) : `${escape(p.from.title)} <span style="color:#b45309">→</span> ${escape(p.to.title)}`,
      `<s style="color:#6b7280;font-weight:normal">${price(p.from)}</s> <span style="color:#b45309;font-weight:bold">→</span> <strong>${price(p.to)}</strong>`,
      'changed',
    )).join('');
    if (changedRows) content += `<table role="presentation" style="width:100%;border-collapse:collapse;margin-top:8px"><tbody>${changedRows}</tbody></table>`;
    html += card(`${tr.products} ${symbol(ticket)}`, content, 'changed');
  }
  if (changes.referenceTotal !== changes.currentTotal) html += `<p style="margin:8px 0 0;padding-top:16px;border-top:1px solid #e2e8f0;text-align:right;font-size:16px;font-weight:bold;color:#1e3a5f">${tr.total}: <span style="display:inline-block;white-space:nowrap"><s style="color:#6b7280;font-size:14px;font-weight:normal">${escape(formatCurrency(changes.referenceTotal, changes.currencyCode))}</s> <span style="color:#b45309">→</span> ${escape(formatCurrency(changes.currentTotal, changes.currencyCode))}</span></p>`;
  return html + '</div>';
}
