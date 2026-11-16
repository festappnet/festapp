import { formatDisplayNumber } from "./numberFormatting.ts";
import { escapeEmailHtml } from "./emailActionLink.ts";
import { usesTicketTerminology } from "./orderItemTerminology.ts";
import { formatCurrency } from "./utilities.ts";
import {
  aggregateMetaSurchargeSums,
  extractMetaSurcharge,
  formatSignedMetaSurcharge,
  type MetaSurchargeAmount,
} from "./metaSurcharge.ts";

export const ORDER_OVERVIEW_LINK_SLOT = '<!-- customer-order-overview-link -->';
export function generateFullOrder(orderData: any, tickets: any[], occasionFeatures: any[], lang: 'cs' | 'en' = 'cs', orderSymbol?: string, decimalDigits = 0): string {
    const currencyFormat = (amount: number, currency: string) => orderData.discount
        ? formatDisplayNumber(amount, lang === 'cs' ? 'cs-CZ' : 'en', {style: 'currency', currency, minimumFractionDigits: 0, maximumFractionDigits: 2})
        : formatCurrency(amount, currency, decimalDigits);
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
            table: "Stůl",
            seat: "Místo",
            standing: "Stání",
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
            table: "Table",
            seat: "Seat",
            standing: "Standing",
            totalPrice: "Total Price",
        }
    }[lang];

    // --- 1. Personal Info ---
    let personalInfoHtml = '';
    const fullName = [name, surname].filter(Boolean).join(' ');

    if (fullName) {
        personalInfoHtml += `<div style="margin-bottom:4px;">${tr.name}: <strong>${escapeEmailHtml(fullName)}</strong></div>`;
    }
    if (email) {
        personalInfoHtml += `<div style="margin-bottom:4px;">${tr.email}: <strong>${escapeEmailHtml(email)}</strong></div>`;
    }
    if (phone) {
        personalInfoHtml += `<div style="margin-bottom:4px;">${tr.phone}: <strong>${escapeEmailHtml(phone)}</strong></div>`;
    }
    if (note) {
        personalInfoHtml += `<div style="margin-top:8px;">${tr.orderNote}: <div><em>${escapeEmailHtml(note)}</em></div></div>`;
    }
    if (personalInfoHtml) {
        personalInfoHtml = `<div style="margin-bottom: 24px;">${personalInfoHtml}</div>`;
    }

    // --- 2. Tickets / Applications ---
    let overallTotal = 0;
    const itemLabel = usesTicketTerminology(occasionFeatures) ? tr.ticket : tr.application;
    const currencyCode = orderData.discount?.currency || tickets?.[0]?.products?.[0]?.currency_code || "CZK";

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
        const amountText = formatSignedMetaSurcharge(meta.amount, meta.currency, currencyFormat);
        return metaSurchargeDescription
            ? `${amountText} — ${metaSurchargeDescription}`
            : amountText;
    }

    const ticketsDetails = tickets.map((ticket) => {
        const productsRows = ticket.products.map((product: any) => {
            const price = Number(product.price || 0);
            overallTotal += price;
            const displayedPrice = orderData.discount ? Number(product.base_price ?? product.price ?? 0) : price;
            const formattedPrice = currencyFormat(displayedPrice, product.currency_code || currencyCode);

            const title = [product.type_title, product.title].filter((value, index, values) => value && values.indexOf(value) === index).map(escapeEmailHtml).join(': ');
            const seating = [[tr.table, product.spot_group_title], [tr.seat, product.spot_title]]
                .filter(([, value]) => value != null && String(value).trim() !== '')
                .map(([label, value]) => `${label}: ${escapeEmailHtml(value)}`).join(' · ');
            const admission = product.is_standing ? [tr.standing, product.standing_area_title].filter(value => value != null && String(value).trim()).map(escapeEmailHtml).join(': ') : seating;
            const seatingHtml = admission ? `<div style="margin-top: 4px; font-weight: 600;">${admission}</div>` : '';

            const rowStyle = 'style="border-bottom: 1px solid #e2e8f0;"';

            const metaText = buildMetaSurchargeText(product);
            const metaRow = metaText
                ? `<tr><td colspan="2" style="padding: 0 0 8px 0; color: #555; font-size: 13px; font-style: italic;">${escapeEmailHtml(metaText)}</td></tr>`
                : '';

            return `
                <tr ${rowStyle}>
                    <td style="padding: 12px 0; vertical-align: top;">${title}${seatingHtml}</td>
                    <td style="padding: 12px 0; text-align: right; white-space: nowrap; vertical-align: bottom; padding-left: 16px;"><strong>${formattedPrice}</strong></td>
                </tr>${metaRow}`;
        }).join("");

        const ticketNote = ticket.note ? `
            <tr>
                <td colspan="2" style="padding: 8px 0 4px 0; color: #555; font-size: 13px;">
                    <em>${tr.itemNote}: ${escapeEmailHtml(ticket.note)}</em>
                </td>
            </tr>` : '';

        return `
            <div style="margin-bottom: 24px;">
                <p style="margin:0 0 12px 0;"><strong>${itemLabel} ${escapeEmailHtml(ticket.ticket_symbol)}</strong></p>
                <table style="width: 100%; border-collapse: collapse;">
                    <tbody>
                        ${productsRows}
                        ${ticketNote}
                    </tbody>
                </table>
            </div>`;
    }).join("");

    // --- 3. Total Price ---
    const formattedOverallTotal = currencyFormat(overallTotal, currencyCode);
    const discount = orderData.discount;
    const historicalDiscount = discount && (tickets.length === 0 || Math.round(overallTotal * 100) !== Math.round(Number(discount.net) * 100));
    const discountLabels = lang === 'cs'
        ? {code: 'Slevový kód', base: 'Původní cena', discount: 'Sleva', net: 'Cena po slevě'}
        : {code: 'Discount code', base: 'Original price', discount: 'Discount', net: 'Discounted price'};
    const discountHtml = discount ? `
        <div class="order-discount-summary" style="max-width:480px;margin:16px auto 0;text-align:left;font-size:16px;font-weight:400;line-height:1.5;">
            ${historicalDiscount ? `<p>${lang === 'cs' ? 'Původní prodej před stornem' : 'Original sale before cancellation'}</p>` : ''}
            <p style="margin:0 0 16px;overflow-wrap:anywhere;">${discountLabels.code}: <strong>${escapeEmailHtml(discount.code)}</strong></p>
            <table role="presentation" style="width:100%;border-collapse:collapse;">
                <tr><td style="padding:4px 16px 4px 0;">${discountLabels.base}</td><td style="padding:4px 0;text-align:right;white-space:nowrap;">${currencyFormat(Number(discount.base), discount.currency)}</td></tr>
                <tr><td style="padding:4px 16px 14px 0;">${discountLabels.discount}</td><td style="padding:4px 0 14px;text-align:right;white-space:nowrap;">−${currencyFormat(Number(discount.discount), discount.currency)}</td></tr>
                <tr><td style="border-top:1px solid #cbd5e1;padding:14px 16px 0 0;font-size:18px;font-weight:700;">${discountLabels.net}</td><td style="border-top:1px solid #cbd5e1;padding:14px 0 0;text-align:right;white-space:nowrap;font-size:18px;font-weight:700;">${currencyFormat(Number(discount.net), discount.currency)}</td></tr>
            </table>
        </div>` : '';


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
            ${discountHtml}${!discount || historicalDiscount ? `<div style="margin-top:16px;font-size:18px;font-weight:bold;">${tr.totalPrice}: ${formattedOverallTotal}</div>` : ''}
            ${metaSumHtml}
        </div>`;

    // --- 4. Final Assembly ---
    return `
        <div style="margin: 20px auto; padding: 24px; font-family: sans-serif; color: #333; background-color: #f9fafb; border: 1px solid #e2e8f0; border-radius: 8px;">
            <p style="font-size: 20px; font-weight: bold; margin: 0 0 16px 0; padding-bottom: 16px; border-bottom: 1px solid #e2e8f0;">${tr.overviewTitle}${orderSymbol ? ` ${escapeEmailHtml(orderSymbol)}` : ''}</p>
            ${personalInfoHtml}
            ${ticketsDetails}
            ${totalSection}
            ${ORDER_OVERVIEW_LINK_SLOT}
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
