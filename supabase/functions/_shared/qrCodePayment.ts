import { formatCurrency } from "./utilities.ts";
import { presentPayment } from "./paymentPresentation.ts";
import { qrcode } from "https://deno.land/x/qrcode/mod.ts";
import { createCanvas, loadImage } from "https://deno.land/x/canvas/mod.ts";

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
  const message = determinePaymentMessage(order, occasionTitle);
  const payment = presentPayment(paymentInfo, message);
  const canvas = createCanvas(500, 700);
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "white";
  ctx.fillRect(0, 0, 500, 700);
  const base64Qr = await qrcode(payment.qrPayload, {
    size: 500,
  }) as unknown as string;
  const qrImage = await loadImage(
    `data:image/png;base64,${base64Qr.split(",")[1]}`,
  );
  ctx.drawImage(qrImage, 0, 0, 500, 500);
  ctx.font = "20px Arial";
  ctx.fillStyle = "black";
  ctx.textAlign = "left";
  let y = 550;
  ctx.fillText(`Objednávka: ${occasionTitle}`, 32, y);
  y += 30;
  ctx.fillText(
    `Bankovní účet: ${paymentInfo.account_number_human_readable}`,
    32,
    y,
  );
  y += 30;
  ctx.fillText(`${payment.referenceKind}: ${payment.referenceDisplay}`, 32, y);
  y += 30;
  if (payment.qrFormat === "SPD" && message) {
    ctx.fillText(`Poznámka: ${message}`, 32, y);
    y += 30;
  }
  ctx.fillText(
    `Celková cena: ${formatCurrency(payment.amount, payment.currency)}`,
    32,
    y,
  );
  return canvas.toBuffer();
}
