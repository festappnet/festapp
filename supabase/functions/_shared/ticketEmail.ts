/** Ticket delivery reuses the canonical payment presentation and order text. */
import { paidPaymentSubstitutions } from "./orderEmailPresentation.ts";
import { generateFullOrder } from "./orderOverview.ts";
export function ticketEmailSubstitutions(data: any, requestedLanguage = "cs") {
  const lang = requestedLanguage === "en" ? "en" : "cs";
  const { order, occasion, payment_info, form_data } = data;
  return {
    occasionTitle: occasion.title,
    orderSymbol: order.order_symbol,
    ...paidPaymentSubstitutions(
      Number(payment_info?.amount ?? order.price ?? 0),
      Number(payment_info?.paid ?? order.price ?? 0),
      order.currency_code ?? "CZK",
      occasion.features ?? [],
      lang,
      form_data?.communication_tone === "informal" ? "informal" : "formal",
    ),
    fullOrder: generateFullOrder(
      order.data,
      order.data?.tickets ?? [],
      occasion.features,
      lang,
      order.order_symbol,
    ),
  };
}
