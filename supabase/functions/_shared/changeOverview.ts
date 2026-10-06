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

const escape = (value: unknown): string =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );

/** Render the canonical database summary. Ticket/product classification lives in SQL. */
export function generateChangeOverview(
  changes: OrderChangeSummary,
  lang: "cs" | "en" = "cs",
): string {
  if (!changes || changes.version !== 1) {
    throw new Error("order_change_summary_unavailable");
  }
  if (!changes.hasChanges) return "";
  const tr = {
    cs: {
      title: "Změny v objednávce",
      cancelled: "Storno",
      removedTickets: "Odebraná",
      addedTickets: "Přidaná",
      ticket: "Vstupenka",
      unnamed: "bez označení",
      total: "Celková cena",
    },
    en: {
      title: "Changes in Your Order",
      cancelled: "Cancelled",
      removedTickets: "Removed",
      addedTickets: "Added",
      ticket: "Ticket",
      unnamed: "without a symbol",
      total: "Total price",
    },
  }[lang];
  const renderSection = (title: string, contentRows: string) => {
    return `<div style="margin-bottom: 20px;">
                    <p style="margin: 0 0 8px 0; font-weight: 600; font-size: 14px; color: #4b5563;">${title}</p>
                    <table style="width: 100%; border-collapse: collapse;">
                        <tbody>
                            ${contentRows}
                        </tbody>
                    </table>
                </div>`;
  };

  const price = (product: Product) =>
    escape(
      formatCurrency(
        Number(product.price) || 0,
        product.currency_code || changes.currencyCode,
      ),
    );
  const products = (items: Product[], color: string, prefix: string) =>
    items.map((p) => `
        <tr>
            <td style="padding: 4px 8px 4px 0; color: ${color};">${prefix}${
      escape(p.title)
    }</td>
            <td style="padding: 4px 0 4px 8px; color: ${color}; text-align: right; white-space: nowrap; font-weight: 500;">${
      price(p)
    }</td>
        </tr>`).join("");
  const symbol = (ticket: TicketChange) =>
    escape(ticket.ticket_symbol || tr.unnamed);
  const ticketLabel = (ticket: TicketChange, status = "", cancelled = false) =>
    `<span${
      cancelled ? ' style="text-decoration: line-through; color: #991b1b;"' : ""
    }>${tr.ticket} ${symbol(ticket)}</span>${
      status
        ? ` <span style="color: ${
          cancelled ? "#991b1b" : "#4b5563"
        }; font-weight: normal;">(${status})</span>`
        : ""
    }`;
  const tickets = (
    status: string,
    items: TicketChange[],
    color: string,
    prefix: string,
    cancelled = false,
  ) =>
    items.map((t) =>
      renderSection(
        ticketLabel(t, status, cancelled),
        products(t.products ?? [], color, prefix),
      )
    ).join("");
  let html =
    `<div style="margin: 20px auto; padding: 24px; font-family: sans-serif; color: #333; background-color: #f9fafb; border: 1px solid #e2e8f0; border-radius: 8px;">`;
  html +=
    `<p style="font-size: 20px; font-weight: bold; margin: 0 0 16px 0; padding-bottom: 16px; border-bottom: 1px solid #e2e8f0;">${tr.title}</p>`;
  html += tickets(
    tr.cancelled,
    changes.cancelledTickets,
    "#991b1b",
    "- ",
    true,
  );
  html += tickets(tr.removedTickets, changes.removedTickets, "#991b1b", "- ");
  html += tickets(tr.addedTickets, changes.addedTickets, "#166534", "+ ");
  for (const ticket of changes.productChanges) {
    const changedHtml = (ticket.changed ?? []).map((c) => `
        <tr>
            <td style="padding: 4px 8px 4px 0;">${
      c.from.title === c.to.title
        ? escape(c.to.title)
        : `${escape(c.from.title)} → ${escape(c.to.title)}`
    }</td>
            <td style="padding: 4px 0 4px 8px; text-align: right; white-space: nowrap;">
                <span style="color:#6b7280; font-size: 90%;">${
      price(c.from)
    }</span>
                <span style="color: #d97706; font-weight: bold; margin: 0 4px;">→</span>
                <strong>${price(c.to)}</strong>
            </td>
        </tr>`).join("");
    html += renderSection(
      ticketLabel(ticket),
      products(ticket.added ?? [], "#166534", "+ ") +
        products(ticket.removed ?? [], "#991b1b", "- ") + changedHtml,
    );
  }
  if (changes.referenceTotal !== changes.currentTotal) {
    html += `
        <div style="text-align: right; padding-top: 16px; margin-top: 8px; border-top: 1px solid #e2e8f0; font-weight: bold;">
            <span style="font-size: 18px;">${tr.total}:&nbsp;</span>
            <span style="white-space: nowrap;">
                <span style="color:#6b7280; font-weight: normal; font-size: 90%;">${
      escape(formatCurrency(changes.referenceTotal, changes.currencyCode))
    }</span>
                <span style="color: #d97706; margin: 0 4px;">→</span>
                <span>${
      escape(formatCurrency(changes.currentTotal, changes.currencyCode))
    }</span>
            </span>
        </div>`;
  }
  return html + "</div>";
}
