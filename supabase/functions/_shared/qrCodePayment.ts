import QRCode from "npm:qrcode";
import type { DeliverEmailInput } from "./emailDelivery.ts";
import { bankCollectionAllowed } from "./orderEmailPresentation.ts";
import { presentPayment } from "./paymentPresentation.ts";

export function showPaymentQrInEmail(
  formData: Record<string, unknown> | null | undefined,
): boolean {
  return formData?.show_payment_qr_in_email === true;
}

function determinePaymentMessage(order: any, occasionTitle: string): string {
  const type = order?.form?.data?.payment_message?.type;
  if (type === "none") return "";
  if (type === "occasion_title") return occasionTitle || "";
  return `${order?.data?.name || ""} ${order?.data?.surname || ""}`.trim();
}

export async function generateQrCode(
  paymentInfo: any,
  order: any,
  occasionTitle: string,
): Promise<Uint8Array> {
  if (
    !bankCollectionAllowed(paymentInfo) || !(Number(paymentInfo.amount) > 0) ||
    !["CZK", "EUR"].includes(paymentInfo.currency_code)
  ) throw new Error("payment_qr_action_forbidden");

  const message = determinePaymentMessage(order, occasionTitle);
  const payment = presentPayment(paymentInfo, message);
  return await QRCode.toBuffer(payment.qrPayload, {
    width: 384,
    margin: 4,
    errorCorrectionLevel: "M",
  });
}

export async function previewPaymentQr(
  payment: Record<string, unknown>,
  lang: unknown,
): Promise<DeliverEmailInput["paymentQr"]> {
  if (
    !bankCollectionAllowed(payment) || !(Number(payment.amount) > 0) ||
    (payment.currency_code !== "CZK" && payment.currency_code !== "EUR")
  ) return undefined;

  // Deliberately invalid for both bank payments and ticket admission.
  return {
    png: await QRCode.toBuffer("festapp-preview:payment", { width: 256 }),
    lang,
    inline: showPaymentQrInEmail(payment),
  };
}
