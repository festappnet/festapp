import QRCode from "npm:qrcode";
import type { Tone } from "./communicationTone.ts";
import type { DeliverEmailInput } from "./emailDelivery.ts";
import { resolveEmailLanguage } from "./emailCommunication.ts";
import { formatDisplayNumber } from "./numberFormatting.ts";
import { bankCollectionAllowed } from "./orderEmailPresentation.ts";
import {
  formatCreditorReference,
  normalizeEpcCreditorName,
  paymentReferenceValue,
  presentPayment,
} from "./paymentPresentation.ts";
import { decoratePaymentQr, paymentQrSize } from "./paymentQrArtwork.ts";
import { formatIBAN } from "./utilities.ts";

interface PaymentQrDetails {
  account_number?: string;
  account_number_human_readable?: string;
  creditor_name?: string;
}

function encodePaymentQr(payload: string): Promise<Uint8Array> {
  return QRCode.toBuffer(payload, {
    width: paymentQrSize,
    margin: 4,
    errorCorrectionLevel: "M",
  });
}

async function paymentQrPng(
  payload: string,
  payment: PaymentQrDetails,
  caption: {
    title: string;
    lang: unknown;
    amount: number;
    currency: string;
    reference: string;
  },
): Promise<Uint8Array> {
  const png = await encodePaymentQr(payload);
  const cs = resolveEmailLanguage(caption.lang) === "cs";
  const formattedAmount = formatDisplayNumber(
    caption.amount,
    cs ? "cs-CZ" : "en-GB",
    {
      style: "currency",
      currency: caption.currency,
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    },
  );
  const referenceLabel = caption.currency === "EUR"
    ? "Reference"
    : cs
    ? "VS"
    : "Variable symbol";
  const account = caption.currency === "EUR"
    ? formatIBAN(payment.account_number)
    : payment.account_number_human_readable ||
      formatIBAN(payment.account_number);
  return await decoratePaymentQr(png, {
    title: normalizeEpcCreditorName(caption.title),
    recipient: normalizeEpcCreditorName(payment.creditor_name) ||
      normalizeEpcCreditorName(account),
    amount: formattedAmount,
    reference: caption.reference
      ? `${referenceLabel} ${caption.reference}`
      : "",
  });
}

export function showPaymentQrInEmail(
  formData: Record<string, unknown> | null | undefined,
): boolean {
  return formData?.show_payment_qr_in_email !== false;
}

function determinePaymentMessage(order: any, occasionTitle: string): string {
  const type = order?.form?.data?.payment_message?.type;
  if (type === "none") return "";
  if (type === "occasion_title") return occasionTitle || "";
  return `${order?.data?.name || ""} ${order?.data?.surname || ""}`.trim();
}

function paymentForQr(
  paymentInfo: any,
  order: any,
  occasionTitle: string,
) {
  if (
    !bankCollectionAllowed(paymentInfo) || !(Number(paymentInfo.amount) > 0) ||
    !["CZK", "EUR"].includes(paymentInfo.currency_code)
  ) throw new Error("payment_qr_action_forbidden");

  return presentPayment(
    paymentInfo,
    determinePaymentMessage(order, occasionTitle),
  );
}

export function generatePlainPaymentQr(
  paymentInfo: any,
  order: any,
  occasionTitle: string,
): Promise<Uint8Array> {
  return encodePaymentQr(
    paymentForQr(paymentInfo, order, occasionTitle).qrPayload,
  );
}

export async function generateQrCode(
  paymentInfo: any,
  order: any,
  occasionTitle: string,
  lang: unknown = "cs",
): Promise<Uint8Array> {
  const payment = paymentForQr(paymentInfo, order, occasionTitle);
  return await paymentQrPng(payment.qrPayload, paymentInfo, {
    title: occasionTitle,
    lang,
    amount: payment.amount,
    currency: payment.currency,
    reference: payment.referenceDisplay,
  });
}

export async function previewPaymentQr(
  payment: Record<string, unknown>,
  lang: unknown,
  occasionTitle: string,
  tone?: Tone,
): Promise<DeliverEmailInput["paymentQr"]> {
  if (
    !bankCollectionAllowed(payment) || !(Number(payment.amount) > 0) ||
    (payment.currency_code !== "CZK" && payment.currency_code !== "EUR")
  ) return undefined;

  const reference = paymentReferenceValue(payment, { required: false });
  // Deliberately invalid for both bank payments and ticket admission.
  return {
    png: await paymentQrPng("festapp-preview:payment", payment, {
      title: occasionTitle,
      lang,
      amount: Number(payment.amount),
      currency: payment.currency_code,
      reference: payment.currency_code === "EUR"
        ? formatCreditorReference(reference)
        : reference,
    }),
    lang,
    inline: showPaymentQrInEmail(payment),
    tone,
  };
}
