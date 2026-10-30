// Pure confirmation content. Producers own identity, attachments and delivery.
import { confirmationPaymentSubstitutions } from "./orderEmailPresentation.ts";
import { generateFullOrder } from "./orderOverview.ts";
import { paymentReferenceValue } from "./paymentPresentation.ts";
import { formatDatetime, formatIBAN } from "./utilities.ts";
import { type Tone, translations } from "./translations/translations.ts";

export function confirmationSubstitutions(
  order: any,
  requestedLanguage = "cs",
) {
  const lang = requestedLanguage in translations
    ? requestedLanguage as keyof typeof translations
    : "cs";
  const occasion = order.occasion;
  const paymentInfo = order.payment_info;
  const tone: Tone = order.form?.data?.communication_tone === "informal"
    ? "informal"
    : "formal";
  const paymentPresentation = confirmationPaymentSubstitutions(
    paymentInfo,
    occasion.features ?? [],
    lang,
    tone,
  );
  return {
    occasionTitle: occasion.title,
    orderSymbol: order.order_symbol,
    balanceReasoning: paymentPresentation.balanceReasoning,
    price: paymentInfo.amount,
    currencyCode: paymentInfo.currency_code,
    amount: paymentPresentation.amount,
    accountNumber: paymentInfo.account_number_human_readable,
    iban: formatIBAN(paymentInfo.account_number),
    // Free registrations have no payment reference; preserve one if already set.
    variableSymbol: paymentReferenceValue(paymentInfo, {
      required: Number(paymentInfo.amount) > 0,
    }),
    deadline: formatDatetime(paymentInfo.deadline, lang),
    fullOrder: generateFullOrder(
      order.data,
      order.data.tickets,
      occasion.features,
      lang,
      order.order_symbol,
    ),
  };
}
