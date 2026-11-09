import { orderTemplateValues, resolveEmailLanguage } from "./emailCommunication.ts";
import { resolveCommunicationTone } from "./communicationTone.ts";
// Pure confirmation content. Producers own identity, attachments and delivery.
import { confirmationPaymentSubstitutions } from "./orderEmailPresentation.ts";
import { generateFullOrder } from "./orderOverview.ts";
import { isBankPaymentInfo, hasNoPaymentDeadline, paymentReferenceValue } from "./paymentPresentation.ts";
import { formatDatetime, formatIBAN } from "./utilities.ts";

export function confirmationSubstitutions(
  order: any,
  requestedLanguage = "cs",
) {
  const lang = resolveEmailLanguage(requestedLanguage);
  const occasion = order.occasion;
  const paymentInfo = order.payment_info;
  const tone = resolveCommunicationTone(order.form?.data?.communication_tone);
  const paymentPresentation = confirmationPaymentSubstitutions(
    paymentInfo,
    occasion.features ?? [],
    lang,
    tone,
  );
  return {
    ...orderTemplateValues("TICKET_ORDER_CONFIRMATION", occasion.title, order.order_symbol, tone, lang),
    balanceReasoning: paymentPresentation.balanceReasoning,
    price: paymentInfo.amount,
    currencyCode: paymentInfo.currency_code,
    amount: paymentPresentation.amount,
    accountNumber: paymentInfo.account_number_human_readable,
    iban: formatIBAN(paymentInfo.account_number),
    // Free registrations have no payment reference; preserve one if already set.
    variableSymbol: paymentReferenceValue(paymentInfo, {
      required: Number(paymentInfo.amount) > 0 && isBankPaymentInfo(paymentInfo),
    }),
    deadline: hasNoPaymentDeadline(paymentInfo) ? null : formatDatetime(paymentInfo.deadline, lang),
    fullOrder: generateFullOrder(
      order.data,
      order.data.tickets,
      occasion.features,
      lang,
      order.order_symbol,
    ),
  };
}
