/** Shared template data for payment notices and issued tickets; no transport or resources. */
import { formatCurrency } from "./utilities.ts";
import { generateFullOrder } from "./orderOverview.ts";
import { type Tone, translations } from "./translations/translations.ts";
export function paidEmailSubstitutions(data: any, requestedLanguage = "cs") {
  const lang = requestedLanguage in translations
    ? requestedLanguage as keyof typeof translations
    : "cs";
  const tr = translations[lang];
  const { order, occasion, payment_info, form_data } = data;
  const tone: Tone = form_data?.communication_tone === "informal"
    ? "informal"
    : "formal";
  const total = Number(payment_info?.amount ?? order.price ?? 0);
  const paid = Number(payment_info?.paid ?? order.price ?? 0);
  const currency = order.currency_code || "CZK";
  const feature = occasion.features?.find((f: any) => f.code === "deposit");
  const deadline = feature?.deposit_deadline === "on_site"
    ? (lang === "cs" ? "na místě" : "on site")
    : feature?.deposit_deadline_days
    ? `${feature.deposit_deadline_days} ${
      lang === "cs" ? "dní před akcí" : "days before the event"
    }`
    : lang === "cs"
    ? "na místě"
    : "on site";
  return {
    occasionTitle: occasion.title,
    orderSymbol: order.order_symbol,
    fullOrder: generateFullOrder(
      order.data,
      order.data?.tickets ?? [],
      occasion.features,
      lang,
      order.order_symbol,
    ),
    balanceReasoning: paid >= total
      ? tr.depositFullyPaid(formatCurrency(total, currency), tone)
      : tr.depositPaid(
        formatCurrency(paid, currency),
        formatCurrency(total - paid, currency),
        deadline,
        tone,
      ),
    amount: formatCurrency(paid, currency),
  };
}
