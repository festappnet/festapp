import { orderTemplateValues, resolveEmailLanguage } from "./emailCommunication.ts";
import { resolveCommunicationTone } from "./communicationTone.ts";
/** Ticket delivery reuses the canonical payment presentation and order text. */
import { confirmedNetPayment, paidPaymentSubstitutions } from "./orderEmailPresentation.ts";
import { generateFullOrder } from "./orderOverview.ts";
export function ticketEmailSubstitutions(data: any, requestedLanguage = "cs", methodName?: string) {
  const lang = resolveEmailLanguage(requestedLanguage);
  const { order, occasion, payment_info, form_data } = data;
  const tone = resolveCommunicationTone(form_data?.communication_tone);
  return {
    paymentAction: '', paymentMethodName: methodName ?? String(payment_info?.payment_method ?? ''),
    ...orderTemplateValues("TICKET_ORDER_PAYMENT_DONE", occasion.title, order.order_symbol, tone, lang),
    ...paidPaymentSubstitutions(
      Number(payment_info?.amount ?? order.price ?? 0),
      confirmedNetPayment(payment_info, Number(order.price ?? 0)),
      order.currency_code ?? "CZK",
      occasion.features ?? [],
      lang,
      tone,
      payment_info,
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
