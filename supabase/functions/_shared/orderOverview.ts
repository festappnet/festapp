import { formatCurrency } from "./utilities.ts";
import {
  aggregateMetaSurchargeSums,
  extractMetaSurcharge,
  formatSignedMetaSurcharge,
  MetaSurchargeAmount,
} from "./metaSurcharge.ts";

export function generateFullOrder(orderData: any, tickets: any[], occasionFeatures: any[], lang: 'cs' | 'en' = 'cs', orderSymbol?: string): string {
    const { name, surname, email, phone, note } = orderData;

    const tr = {
        cs: {
            overviewTitle: "Přehled objednávky",
            name: "Jméno",
            email: "E-mail",
            phone: "Telefon",
            orderNote: "Poznámka k objednávce",
            ticket: "Vstupenka",
            application: "Přihláška",
            itemNote: "Poznámka",
            totalPrice: "Celková cena",
        },
        en: {
            overviewTitle: "Order Overview",
            name: "Name",
            email: "E-mail",
            phone: "Phone",
            orderNote: "Order Note",
            ticket: "Ticket",
            application: "Application",
            itemNote: "Note",
            totalPrice: "Total Price",
        }
    }[lang];

    // --- 1. Personal Info ---
    let personalInfoHtml = '';
    const fullName = [name, surname].filter(Boolean).join(' ');

    if (fullName) {
        personalInfoHtml += `<div style="margin-bottom:4px;">${tr.name}: <strong>${fullName}</strong></div>`;
    }
    if (email) {
        personalInfoHtml += `<div style="margin-bottom:4px;">${tr.email}: <strong>${email}</strong></div>`;
    }
    if (phone) {
        personalInfoHtml += `<div style="margin-bottom:4px;">${tr.phone}: <strong>${phone}</strong></div>`;
    }
    if (note) {
        personalInfoHtml += `<div style="margin-top:8px;">${tr.orderNote}: <div><em>${note}</em></div></div>`;
    }
    if (personalInfoHtml) {
        personalInfoHtml = `<div style="margin-bottom: 24px;">${personalInfoHtml}</div>`;
    }

    // --- 2. Tickets / Applications ---
    let overallTotal = 0;
    const ticketFeature = occasionFeatures?.find(f => f.code === "ticket");
    const itemLabel = ticketFeature?.is_enabled ? tr.ticket : tr.application;
    const currencyCode = tickets?.[0]?.products?.[0]?.currency_code || "CZK";

    // Visual-only meta surcharge: shown under product (and summed per-currency under
    // Total Price), NEVER added to overallTotal. Only renders in virtual mode — real
    // mode uses a payment-linked deposit so meta_surcharge would be misleading.
    const depositFeatureRaw = occasionFeatures?.find(f => f.code === "deposit");
    const depositFeature = depositFeatureRaw?.is_enabled ? depositFeatureRaw : null;
    const isVirtualMode = depositFeature?.deposit_mode === 'virtual';
    const metaSurchargeDescription = isVirtualMode &&
            depositFeature?.meta_surcharge_description &&
            String(depositFeature.meta_surcharge_description).trim().length > 0
        ? String(depositFeature.meta_surcharge_description).trim()
        : null;

    // Per-product amounts collected during the tickets loop, summed under Total Price.
    const metaSurchargeAmounts: MetaSurchargeAmount[] = [];

    function buildMetaSurchargeText(product: any): string | null {
        const meta = extractMetaSurcharge(product, depositFeature?.deposit_mode);
        if (!meta) return null;
        metaSurchargeAmounts.push(meta);
        const amountText = formatSignedMetaSurcharge(meta.amount, meta.currency, formatCurrency);
        return metaSurchargeDescription
            ? `${amountText} — ${metaSurchargeDescription}`
            : amountText;
    }

    const ticketsDetails = tickets.map((ticket) => {
        const productsRows = ticket.products.map((product: any) => {
            const price = Number(product.price || 0);
            overallTotal += price;
            const formattedPrice = formatCurrency(price, product.currency_code || currencyCode);

            const title = product.spot_title || product.title;

            const rowStyle = 'style="border-bottom: 1px solid #e2e8f0;"';

            const metaText = buildMetaSurchargeText(product);
            const metaRow = metaText
                ? `<tr><td colspan="2" style="padding: 0 0 8px 0; color: #555; font-size: 13px; font-style: italic;">${metaText}</td></tr>`
                : '';

            return `
                <tr ${rowStyle}>
                    <td style="padding: 12px 0; vertical-align: top;">${product.type_title}: ${title}</td>
                    <td style="padding: 12px 0; text-align: right; white-space: nowrap; vertical-align: bottom; padding-left: 16px;"><strong>${formattedPrice}</strong></td>
                </tr>${metaRow}`;
        }).join("");

        const ticketNote = ticket.note ? `
            <tr>
                <td colspan="2" style="padding: 8px 0 4px 0; color: #555; font-size: 13px;">
                    <em>${tr.itemNote}: ${ticket.note}</em>
                </td>
            </tr>` : '';

        return `
            <div style="margin-bottom: 24px;">
                <p style="margin:0 0 12px 0;"><strong>${itemLabel} ${ticket.ticket_symbol}</strong></p>
                <table style="width: 100%; border-collapse: collapse;">
                    <tbody>
                        ${productsRows}
                        ${ticketNote}
                    </tbody>
                </table>
            </div>`;
    }).join("");

    // --- 3. Total Price ---
    const formattedOverallTotal = formatCurrency(overallTotal, currencyCode);

    // Per-currency meta surcharge sums (visual-only, NOT included in overallTotal).
    // Renders as separate lines under Total Price, one per currency.
    const metaSumLines = aggregateMetaSurchargeSums(metaSurchargeAmounts).map(
        ({ currency, sum }) => formatSignedMetaSurcharge(sum, currency, formatCurrency),
    );
    const metaSumHtml = metaSumLines.length > 0
        ? `<div style="margin-top: 4px;">
             ${metaSumLines.map(line =>
                 `<span style="font-size: 16px; font-weight: 700;">${line}</span>`
             ).join('<br>')}
           </div>`
        : '';

    const totalSection = `
        <div style="text-align: right; padding-top: 16px; margin-top: 8px;">
            <span style="font-size: 18px; font-weight: bold;">${tr.totalPrice}: ${formattedOverallTotal}</span>
            ${metaSumHtml}
        </div>`;

    // --- 4. Final Assembly ---
    return `
        <div style="margin: 20px auto; padding: 24px; font-family: sans-serif; color: #333; background-color: #f9fafb; border: 1px solid #e2e8f0; border-radius: 8px;">
            <p style="font-size: 20px; font-weight: bold; margin: 0 0 16px 0; padding-bottom: 16px; border-bottom: 1px solid #e2e8f0;">${tr.overviewTitle}${orderSymbol ? ` ${orderSymbol}` : ''}</p>
            ${personalInfoHtml}
            ${ticketsDetails}
            ${totalSection}
        </div>`;
}
/** Metadata-only read adapter for retained confirmation/replay snapshots.
 * No query for current snapshots, no mutation of payload/hash or business data.
 */
export async function withOrderIdentity(
    order: any,
    read: (params: { p_order: number; p_occasion: number; p_organization: number }) => Promise<string | null>,
    scope = order.occasion,
): Promise<any> {
    if (typeof order.order_symbol === "string" && /^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$/.test(order.order_symbol)) return order;
    if (order.order_symbol != null) throw new Error("invalid_order_symbol");
    if (!order.id || !scope?.id || !scope?.organization) throw new Error("order_identity_scope_missing");
    const symbol = await read({ p_order: order.id, p_occasion: scope.id, p_organization: scope.organization });
    if (!symbol || !/^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$/.test(symbol)) throw new Error("order_identity_unavailable");
    return { ...order, order_symbol: symbol };
}
