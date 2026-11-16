import { escapeEmailHtml } from "./emailActionLink.ts";
import type { Tone } from "./communicationTone.ts";
import { formatCurrency, formatDatetime, formatIBAN } from "./utilities.ts";
import { hasNoPaymentDeadline, paymentReferenceValue } from "./paymentPresentation.ts";
import { translations } from "./translations/translations.ts";

// Pure email presentation over committed payment facts. Producers own access,
// eligibility, attachments and sending; preview fixtures use these same branches.
type Fields = Record<string, any>;
export function confirmedNetPayment(payment: Fields | null | undefined, fallback = 0): number {
  return Number(payment?.paid ?? fallback) - Number(payment?.returned ?? 0);
}

const translation = (lang: string) =>
  translations[lang as keyof typeof translations] || translations.cs;

function cashBalance(payment: Fields, amount: number, lang: string, tone: Tone) {
  if (payment.collectionAction?.allowed === false) return unavailableCollectionText(lang);
  const instructions = payment.data?.payment_policy?.cashInstructions || (lang === 'cs' ? (tone === 'informal' ? 'Zaplať prosím v hotovosti na místě.' : 'Zaplaťte prosím v hotovosti na místě.') : 'Please pay in cash at the venue.');
  return `<p>${lang === 'cs' ? 'Rezervace potvrzena. K úhradě na místě' : 'Reservation confirmed. Pay at the venue'}: ${escapeEmailHtml(formatCurrency(amount, payment.currency_code))}</p><p>${escapeEmailHtml(instructions)}</p>`;
}
export function bankCollectionAllowed(payment: Fields | null | undefined): boolean {
  return payment?.payment_method === 'bank' && payment?.collectionAction?.purpose === 'collect_payment' &&
    payment?.collectionAction?.method === 'bank' && payment?.collectionAction?.allowed === true;
}
export function unavailableCollectionText(lang: string): string {
  return `<p>${lang === 'cs' ? 'Platební instrukce nyní nejsou dostupné. Stav objednávky a případné vrácení platby ověřte u pořadatele.' : 'Payment instructions are currently unavailable. Contact the organizer to confirm the order or refund status.'}</p>`;
}
/** Shared factual copy for every hosted connector; connector names do not imply cards. */
export function providerPaymentSubstitutions(payment: Fields, name: string, lang: string, action = '') {
  const state = String(payment.providerPayment?.status ?? 'unknown');
  const cs = lang === 'cs';
  const copy: Record<string, string> = cs ? {
    paid: 'Platba byla přijata.', partially_refunded: 'Část platby byla vrácena. Nevzniká tím nová platba.',
    refunded: 'Platba byla vrácena. Tato zpráva nepotvrzuje platnost vstupenek.',
    disputed: 'Platba je ve sporu. Stav vstupenek ověřte u pořadatele. Znovu neplaťte.',
    action_required: 'Platbu musí vyřešit pořadatel. Znovu neplaťte.', expired: 'Čas pro dokončení objednávky vypršel. Novou platbu nezahajujte.',
    pending: 'Stav platby se ověřuje. Znovu neplaťte.',
  } : {
    paid: 'Payment received.', partially_refunded: 'Part of the payment was refunded. This does not create a new payment.',
    refunded: 'The payment was refunded. This message does not confirm ticket validity.',
    disputed: 'The payment is disputed. Confirm admission with the organizer. Do not pay again.',
    action_required: 'The organizer must resolve this payment. Do not pay again.', expired: 'The reservation has expired. Do not start another payment.',
    pending: 'Payment status is being verified. Do not pay again.',
  };
  const canContinue = ['open','preparing'].includes(state) && payment.collectionAction?.allowed === true;
  const paymentAction = canContinue ? action : '';
  const balanceReasoning = canContinue
    ? `<p>${cs ? 'Objednávka čeká na platbu přes' : 'Your order awaits payment through'} ${escapeEmailHtml(name)}.</p>` + paymentAction
    : copy[state] ? `<p>${escapeEmailHtml(copy[state])}</p>` : unavailableCollectionText(lang);
  return {balanceReasoning, paymentDetails: balanceReasoning, paymentAction, paymentMethodName: name,
    accountNumber: '', iban: '', variableSymbol: ''};
}
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
  } else if (paymentInfo.payment_method === 'cash') {
    balanceReasoning = cashBalance(paymentInfo, Number(paymentInfo.amount), lang, tone);
  } else if (!bankCollectionAllowed(paymentInfo)) {
    balanceReasoning = unavailableCollectionText(lang);
  } else if (
    paymentInfo.deposit_amount &&
    paymentInfo.deposit_amount < paymentInfo.amount
  ) {
    const deposit = Number(paymentInfo.deposit_amount);
    const remaining = paymentInfo.amount - deposit;
    const feature = features.find((item: any) => item.code === "deposit");
    const deadline = hasNoPaymentDeadline(paymentInfo) ? null : feature?.deposit_deadline === "on_site"
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
      hasNoPaymentDeadline(paymentInfo) ? null : formatDatetime(paymentInfo.deadline, lang),
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
  if (payment_info.payment_method !== 'bank' && payment_info.payment_method !== 'cash') return providerPaymentSubstitutions(payment_info, String(payment_info.payment_method ?? ''), lang).balanceReasoning;
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
  } else if (balance > 0 && payment_info.payment_method === 'cash') {
    balanceReasoning = cashBalance(payment_info, balance, lang, tone);
  } else if (balance > 0 && !bankCollectionAllowed(payment_info)) {
    balanceReasoning = unavailableCollectionText(lang);
  } else if (balance > 0) {
    const iban = formatIBAN(bank_account.account_number);
    if (amountPaid === 0) {
      balanceReasoning = tr.unpaid(
        formatCurrency(orderPrice, currency),
        bank_account.account_number_human_readable,
        iban,
        paymentReferenceValue(payment_info),
        hasNoPaymentDeadline(payment_info) ? null : formatDatetime(payment_info.deadline, lang),
        tone,
      );
    } else {
      balanceReasoning = tr.underpaid(
        formatCurrency(amountPaid, currency),
        formatCurrency(balance, currency),
        bank_account.account_number_human_readable,
        iban,
        paymentReferenceValue(payment_info),
        hasNoPaymentDeadline(payment_info) ? null : formatDatetime(payment_info.deadline, lang),
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
  paymentInfo?: Fields,
) {
  if (paymentInfo && paymentInfo.payment_method !== 'bank' && paymentInfo.payment_method !== 'cash') return {...providerPaymentSubstitutions(paymentInfo, String(paymentInfo.payment_method ?? ''), lang), amount: formatCurrency(amountPaid, currency)};
  const tr = translation(lang);
  let balanceReasoning = "";

  const isFullyPaid = amountPaid >= totalAmount;

  if (isFullyPaid) {
    balanceReasoning = tr.depositFullyPaid(
      formatCurrency(totalAmount, currency),
      tone,
    );
  } else if (paymentInfo?.payment_method === 'cash') {
    balanceReasoning = cashBalance(paymentInfo, totalAmount - amountPaid, lang, tone);
  } else if (hasNoPaymentDeadline(paymentInfo)) {
    balanceReasoning = `<p>${lang === 'cs' ? 'Přijato' : 'Received'}: ${escapeEmailHtml(formatCurrency(amountPaid, currency))}</p>` +
      `<p>${lang === 'cs' ? 'Zbývá k úhradě' : 'Remaining to pay'}: ${escapeEmailHtml(formatCurrency(totalAmount - amountPaid, currency))}</p>`;
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
  if (!bankCollectionAllowed(payment_info)) return unavailableCollectionText(lang);
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
  if (!bankCollectionAllowed(payment_info)) return unavailableCollectionText(lang);
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
