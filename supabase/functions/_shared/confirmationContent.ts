// Pure confirmation content. This module must not import senders, clients or invoice services.
import { generateFullOrder } from "./orderOverview.ts";
import { paymentReferenceValue } from "./paymentPresentation.ts";
import { formatCurrency, formatDatetime, formatIBAN } from "./utilities.ts";
import { type Tone, translations } from "./translations/translations.ts";

export function confirmationSubstitutions(
  order: any,
  requestedLanguage = "cs",
) {
  const lang = requestedLanguage in translations
    ? requestedLanguage as keyof typeof translations
    : "cs";
  const tr = translations[lang];
  const occasion = order.occasion;
  const paymentInfo = order.payment_info;
  const tone: Tone = order.form?.data?.communication_tone === "informal"
    ? "informal"
    : "formal";
  let balanceReasoning: string;
  if (paymentInfo.amount <= 0) {
    balanceReasoning = tr.zeroOrder(paymentInfo.currency_code, tone);
  } else if (
    paymentInfo.deposit_amount &&
    paymentInfo.deposit_amount < paymentInfo.amount
  ) {
    const deposit = Number(paymentInfo.deposit_amount);
    const remaining = paymentInfo.amount - deposit;
    const feature = (occasion.features ?? []).find((item: any) =>
      item.code === "deposit"
    );
    const deadline = feature?.deposit_deadline === "on_site"
      ? (lang === "cs" ? "na místě" : "on site")
      : feature?.deposit_deadline_days
      ? `${feature.deposit_deadline_days} ${
        lang === "cs" ? "dní před akcí" : "days before the event"
      }`
      : (lang === "cs" ? "na místě" : "on site");
    balanceReasoning = tr.depositRequired(
      formatCurrency(deposit, paymentInfo.currency_code),
      formatCurrency(remaining, paymentInfo.currency_code),
      deadline,
      paymentInfo.account_number_human_readable,
      formatIBAN(paymentInfo.account_number),
      paymentReferenceValue(paymentInfo),
      tone,
    );
  } else {
    balanceReasoning = tr.unpaid(
      formatCurrency(paymentInfo.amount, paymentInfo.currency_code),
      paymentInfo.account_number_human_readable,
      formatIBAN(paymentInfo.account_number),
      paymentReferenceValue(paymentInfo),
      formatDatetime(paymentInfo.deadline, lang) ?? "",
      tone,
    );
  }

  return {
    occasionTitle: occasion.title,
    orderSymbol: order.order_symbol,
    balanceReasoning,
    price: paymentInfo.amount,
    currencyCode: paymentInfo.currency_code,
    amount: formatCurrency(paymentInfo.amount, paymentInfo.currency_code),
    accountNumber: paymentInfo.account_number_human_readable,
    iban: formatIBAN(paymentInfo.account_number),
    variableSymbol: paymentInfo.amount > 0
      ? paymentReferenceValue(paymentInfo)
      : "",
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
