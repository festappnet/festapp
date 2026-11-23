import { PageSizes, PDFDocument, rgb } from "npm:pdf-lib";
import * as fontkit from "../_shared/vendor/fontkit/fontkit.mjs";
import {
  isValidIban,
  normalizeEpcCreditorName,
  presentPayment,
} from "../_shared/paymentPresentation.ts";
import { formatIBAN } from "../_shared/utilities.ts";

export async function appendFakturoidPaymentPage(
  invoice: Uint8Array,
  payment: {
    amount: number;
    currency_code: string;
    account_number: string;
    account_number_human_readable?: string | null;
    iban?: string | null;
    creditor_name?: string | null;
    creditor_reference?: string | null;
    variable_symbol?: string | number | null;
  },
  qrPng: Uint8Array,
  lang: "cs" | "en",
): Promise<Uint8Array> {
  const instruction = presentPayment(payment);
  if (instruction.currency !== "CZK" && instruction.currency !== "EUR") {
    throw new Error("fakturoid_payment_page_currency_unsupported");
  }
  const sepa = instruction.qrFormat === "EPC_SCT";

  // Extend the original PDF so its existing pages and embedded invoice data stay in place.
  const pdf = await PDFDocument.load(invoice, { updateMetadata: false });
  const page = pdf.addPage(PageSizes.A4);
  pdf.registerFontkit(fontkit);
  const font = await pdf.embedFont(
    await Deno.readFile(
      new URL("../_shared/ticket-assets/roboto.ttf", import.meta.url),
    ),
  );
  const qr = await pdf.embedPng(qrPng);
  const cs = lang === "cs";
  const margin = 64;
  const contentWidth = page.getWidth() - 2 * margin;
  const dark = rgb(0.09, 0.13, 0.2);
  const muted = rgb(0.31, 0.37, 0.44);
  const amount = new Intl.NumberFormat(cs ? "cs-CZ" : "en-IE", {
    style: "currency",
    currency: instruction.currency,
    currencyDisplay: "code",
  }).format(instruction.amount);
  const draw = (value: string, y: number, size: number, color = dark) => {
    const fittedSize = Math.min(
      size,
      size * contentWidth / font.widthOfTextAtSize(value, size),
    );
    page.drawText(value, { x: margin, y, size: fittedSize, font, color });
  };

  const top = page.getHeight() - 75;
  const title = sepa
    ? (cs ? "Platba SEPA" : "SEPA bank transfer")
    : (cs ? "Platba převodem" : "Bank transfer");
  draw(title, top, 28);
  draw(
    cs
      ? "Naskenujte QR kód v bankovní aplikaci."
      : "Scan the QR code in your banking app.",
    top - 30,
    13,
    muted,
  );
  page.drawImage(qr, { x: margin, y: top - 270, width: 216, height: 216 });

  const fields = [[cs ? "Částka" : "Amount", amount]];
  const payee = normalizeEpcCreditorName(payment.creditor_name);
  if (payee) fields.push([cs ? "Příjemce" : "Beneficiary", payee]);
  const iban = isValidIban(payment.account_number)
    ? payment.account_number
    : payment.iban;
  const localAccount = payment.account_number_human_readable ||
    (!iban ? payment.account_number : "");
  if (!sepa && localAccount && localAccount !== iban) {
    fields.push([cs ? "Číslo účtu" : "Account number", localAccount]);
  }
  if (iban) fields.push(["IBAN", formatIBAN(iban)]);
  const referenceLabel = sepa
    ? (cs ? "Reference platby" : "Payment reference")
    : (cs ? "Variabilní symbol" : "Variable symbol");
  fields.push([referenceLabel, instruction.referenceRaw]);
  for (const [index, [label, value]] of fields.entries()) {
    const y = top - 316 - index * 65;
    draw(label, y, 11, muted);
    draw(value, y - 23, 19);
  }
  return await pdf.save({ updateFieldAppearances: false });
}
