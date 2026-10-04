export type PaymentQrFormat = "SPD" | "EPC_SCT";

export interface PaymentPresentation {
  referenceKind: "VS" | "RF";
  referenceRaw: string;
  referenceDisplay: string;
  qrFormat: PaymentQrFormat;
  qrPayload: string;
  amount: number;
  currency: string;
}

export function paymentReferenceValue(payment: any): string {
  const currency = String(payment?.currency_code ?? "").trim().toUpperCase();
  const value = currency === "EUR"
    ? payment?.creditor_reference
    : payment?.variable_symbol;
  const normalized = String(value ?? "").trim();
  if (!normalized) {
    throw new Error(
      currency === "EUR" ? "EUR_REFERENCE_REQUIRED" : "VS_REQUIRED",
    );
  }
  return normalized;
}

function normalizeIban(value: unknown): string {
  return String(value ?? "").replace(/\s/g, "").toUpperCase();
}

export function isValidIban(value: unknown): boolean {
  const iban = normalizeIban(value);
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$/.test(iban)) return false;
  const rearranged = iban.slice(4) + iban.slice(0, 4);
  let remainder = 0;
  for (const char of rearranged) {
    const expanded = /[0-9]/.test(char)
      ? char
      : String(char.charCodeAt(0) - 55);
    for (const digit of expanded) {
      remainder = (remainder * 10 + Number(digit)) % 97;
    }
  }
  return remainder === 1;
}

export function isValidCreditorReference(value: unknown): boolean {
  const reference = String(value ?? "").replace(/\s/g, "").toUpperCase();
  if (!/^RF[0-9]{2}[A-Z0-9]{1,21}$/.test(reference)) return false;
  const rearranged = reference.slice(4) + reference.slice(0, 4);
  let remainder = 0;
  for (const char of rearranged) {
    const expanded = /[0-9]/.test(char)
      ? char
      : String(char.charCodeAt(0) - 55);
    for (const digit of expanded) {
      remainder = (remainder * 10 + Number(digit)) % 97;
    }
  }
  return remainder === 1;
}

export function buildSpdPayload(payment: any, message = ""): string {
  const amount = Number(payment.amount);
  const currency = String(payment.currency_code ?? "").trim().toUpperCase();
  const variableSymbol = String(payment.variable_symbol ?? "").trim();
  if (
    !Number.isFinite(amount) || amount < 0 || !/^[A-Z]{3}$/.test(currency) ||
    !/^[0-9]{1,10}$/.test(variableSymbol)
  ) {
    throw new Error("INVALID_SPD_PAYMENT_DATA");
  }
  let payload = `SPD*1.0*ACC:${normalizeIban(payment.account_number)}` +
    `*AM:${amount.toFixed(2)}*CC:${currency}*X-VS:${variableSymbol}`;
  if (message.trim()) {
    payload += `*MSG:${encodeURIComponent(message.normalize("NFC"))}`;
  }
  return payload;
}

export function normalizeEpcCreditorName(value: unknown): string {
  return String(value ?? "")
    .normalize("NFC")
    .replace(/[\u0000-\u001F\u007F-\u009F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function buildEpcSctPayload(payment: any): string {
  const amount = Number(payment.amount);
  const iban = normalizeIban(payment.account_number);
  const creditorName = normalizeEpcCreditorName(payment.creditor_name);
  const reference = String(payment.creditor_reference ?? "").replace(/\s/g, "")
    .toUpperCase();
  if (
    String(payment.currency_code ?? "").trim().toUpperCase() !== "EUR" ||
    !Number.isFinite(amount) || amount < 0.01 || amount > 999999999.99 ||
    !isValidIban(iban) || creditorName.length < 1 || creditorName.length > 70 ||
    !isValidCreditorReference(reference)
  ) {
    throw new Error("INVALID_EPC_PAYMENT_DATA");
  }
  const payload = [
    "BCD",
    "002",
    "1",
    "SCT",
    "",
    creditorName,
    iban,
    `EUR${amount.toFixed(2)}`,
    "",
    reference,
    "",
    "",
  ].join("\n");
  if (new TextEncoder().encode(payload).length > 331) {
    throw new Error("EPC_PAYLOAD_TOO_LONG");
  }
  return payload;
}

export function presentPayment(
  payment: any,
  message = "",
): PaymentPresentation {
  const currency = String(payment.currency_code ?? "").trim().toUpperCase();
  const amount = Number(payment.amount);
  if (currency === "EUR") {
    const referenceRaw = paymentReferenceValue(payment).replace(/\s/g, "")
      .toUpperCase();
    return {
      referenceKind: "RF",
      referenceRaw,
      referenceDisplay: referenceRaw.replace(/(.{4})(?=.)/g, "$1 "),
      qrFormat: "EPC_SCT",
      qrPayload: buildEpcSctPayload(payment),
      amount,
      currency,
    };
  }
  const referenceRaw = paymentReferenceValue(payment);
  return {
    referenceKind: "VS",
    referenceRaw,
    referenceDisplay: referenceRaw,
    qrFormat: "SPD",
    qrPayload: buildSpdPayload(payment, message),
    amount,
    currency,
  };
}
