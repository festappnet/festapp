import { formatCurrency, formatDatetime, formatIBAN } from "./utilities.ts";
import { paymentReferenceValue } from "./paymentPresentation.ts";
import { type Tone, translations } from "./translations/translations.ts";

// Pure email presentation over committed payment facts. Producers own access,
// eligibility, attachments and sending; preview fixtures use these same branches.
type Fields = Record<string, any>;
const translation = (lang: string) =>
  translations[lang as keyof typeof translations] || translations.cs;

export function confirmationPaymentSubstitutions(
  paymentInfo: Fields,
  features: Fields[],
  lang: string,
  tone: Tone,
) {
  const tr = translation(lang);
  let balanceReasoning: string;
  if (paymentInfo.amount <= 0) {
    balanceReasoning = tr.zeroOrder(paymentInfo.currency_code, tone);
  } else if (
    paymentInfo.deposit_amount &&
    paymentInfo.deposit_amount < paymentInfo.amount
  ) {
    const deposit = Number(paymentInfo.deposit_amount);
    const remaining = paymentInfo.amount - deposit;
    const feature = features.find((item: any) => item.code === "deposit");
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
    balanceReasoning,
    amount: formatCurrency(paymentInfo.amount, paymentInfo.currency_code),
  };
}

export function updateBalanceReasoning(
  orderPrice: number,
  amountPaid: number,
  currency: string,
  bank_account: Fields,
  payment_info: Fields,
  lang: string,
  tone: Tone,
) {
  const tr = translation(lang);
  const balance = orderPrice - amountPaid;
  let balanceReasoning = "";

  if (orderPrice === 0) {
    balanceReasoning = tr.zeroOrder(currency, tone);
  } else if (balance < 0) {
    balanceReasoning = tr.overpaid(
      formatCurrency(Math.abs(balance), currency),
      tone,
    );
  } else if (balance > 0) {
    const iban = formatIBAN(bank_account.account_number);
    if (amountPaid === 0) {
      balanceReasoning = tr.unpaid(
        formatCurrency(orderPrice, currency),
        bank_account.account_number_human_readable,
        iban,
        paymentReferenceValue(payment_info),
        formatDatetime(payment_info.deadline, lang),
        tone,
      );
    } else {
      balanceReasoning = tr.underpaid(
        formatCurrency(amountPaid, currency),
        formatCurrency(balance, currency),
        bank_account.account_number_human_readable,
        iban,
        paymentReferenceValue(payment_info),
        formatDatetime(payment_info.deadline, lang),
        tone,
      );
    }
  } else {
    balanceReasoning = tr.fullyPaid(tone);
  }
  return balanceReasoning;
}

export function paidPaymentSubstitutions(
  totalAmount: number,
  amountPaid: number,
  currency: string,
  features: Fields[],
  lang: string,
  tone: Tone,
) {
  const tr = translation(lang);
  let balanceReasoning = "";

  const isFullyPaid = amountPaid >= totalAmount;

  if (isFullyPaid) {
    balanceReasoning = tr.depositFullyPaid(
      formatCurrency(totalAmount, currency),
      tone,
    );
  } else {
    const remainingAmount = totalAmount - amountPaid;

    const depositFeature = features.find((f: any) => f.code === "deposit");
    let depositDeadline: string;
    const deadlineType = depositFeature?.deposit_deadline;
    const deadlineDays = depositFeature?.deposit_deadline_days;

    if (deadlineType === "on_site") {
      depositDeadline = lang === "cs" ? "na místě" : "on site";
    } else if (deadlineDays) {
      depositDeadline = lang === "cs"
        ? `${deadlineDays} dní před akcí`
        : `${deadlineDays} days before the event`;
    } else {
      depositDeadline = lang === "cs" ? "na místě" : "on site";
    }

    balanceReasoning = tr.depositPaid(
      formatCurrency(amountPaid, currency),
      formatCurrency(remainingAmount, currency),
      depositDeadline,
      tone,
    );
  }
  return { balanceReasoning, amount: formatCurrency(amountPaid, currency) };
}

export function reminderBalanceReasoning(
  timeDiff: number,
  daysDiff: number,
  balance: number,
  amountPaid: number,
  currency: string,
  bank_account: Fields,
  payment_info: Fields,
  lang: string,
  tone: Tone,
) {
  const tr = translation(lang);
  const iban = formatIBAN(bank_account.account_number);
  const formattedPaidAmount = formatCurrency(amountPaid, currency);
  let balanceReasoning = "";

  if (timeDiff > 0) { // Deadline is in the future
    balanceReasoning = tr.reminder_before_deadline(
      daysDiff,
      formatCurrency(balance, currency),
      bank_account.account_number_human_readable,
      iban,
      paymentReferenceValue(payment_info),
      formattedPaidAmount,
      tone,
    );
  } else { // Deadline is in the past
    balanceReasoning = tr.reminder_after_deadline(
      daysDiff,
      formatCurrency(balance, currency),
      bank_account.account_number_human_readable,
      iban,
      paymentReferenceValue(payment_info),
      formattedPaidAmount,
      tone,
    );
  }

  return balanceReasoning;
}

export function depositReminderBalanceReasoning(
  remainingAmount: number,
  currency: string,
  features: Fields[],
  startTimeValue: string,
  bank_account: Fields,
  payment_info: Fields,
  lang: string,
  tone: Tone,
) {
  const tr = translation(lang);
  const iban = formatIBAN(bank_account.account_number);
  const depositFeature = features.find((f: any) => f.code === "deposit");
  let depositDeadline: string;
  const deadlineDays = depositFeature?.deposit_deadline_days;

  if (deadlineDays) {
    // Calculate actual deadline date from occasion start_time
    const startTime = new Date(startTimeValue);
    const deadlineDate = new Date(
      startTime.getTime() - (deadlineDays * 24 * 60 * 60 * 1000),
    );
    depositDeadline = deadlineDate.toLocaleDateString(
      lang === "cs" ? "cs-CZ" : "en-US",
    );
  } else {
    depositDeadline = lang === "cs" ? "na místě" : "on site";
  }

  const balanceReasoning = tr.depositReminder(
    formatCurrency(remainingAmount, currency),
    depositDeadline,
    bank_account.account_number_human_readable,
    iban,
    paymentReferenceValue(payment_info),
    tone,
  );

  return balanceReasoning;
}
