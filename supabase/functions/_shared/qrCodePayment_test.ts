import QRCode from "npm:qrcode";
import { PNG } from "npm:pngjs@5.0.0";
import { Buffer } from "node:buffer";
import { buildSpdPayload } from "./paymentPresentation.ts";
import { generatePaymentDetails } from "./translations/payment-details.helpers.ts";
import assert from "node:assert/strict";
import { generateQrCode } from "./qrCodePayment.ts";
Deno.test("direct collection QR owner refuses missing purpose, disabled and gateway sources before rendering", async () => {
  const bank = {
    payment_method: "bank",
    amount: 100,
    currency_code: "CZK",
    collectionAction: {
      method: "bank",
      purpose: "collect_payment",
      allowed: true,
    },
  };
  for (
    const payment of [
      { amount: 100 },
      { ...bank, payment_method: "stripe" },
      { ...bank, payment_method: "orchard" },
      {
        ...bank,
        collectionAction: { ...bank.collectionAction, allowed: false },
      },
      {
        ...bank,
        collectionAction: {
          ...bank.collectionAction,
          purpose: "bank_refund_instruction",
        },
      },
      { ...bank, currency_code: "USD" },
      { ...bank, collectionAction: undefined },
      { ...bank, amount: 0 },
    ]
  ) {
    await assert.rejects(
      () => generateQrCode(payment, {}, "Testovací ples"),
      /payment_qr_action_forbidden/,
    );
  }
});

Deno.test("long SEPA IBAN is a single, grouped HTML value and the PNG includes the caption", async () => {
  const iban = "MT84MALT011000012345MTLCAST001S";
  const html = generatePaymentDetails({
    accountNumber: iban,
    iban,
    variableSymbol: "RF18539007547034",
    amount: "80 EUR",
    lang: "en",
  });
  assert.match(html, /MT84 MALT 0110 0001 2345 MTLC AST0 01S/);
  assert.doesNotMatch(html, /Account Number:/);
  const png = await generateQrCode(
    {
      payment_method: "bank",
      collectionAction: {
        method: "bank",
        purpose: "collect_payment",
        allowed: true,
      },
      account_number: iban,
      currency_code: "EUR",
      amount: 80,
      creditor_name: "Organizer",
      creditor_reference: "RF18539007547034",
    },
    {},
    "Sample",
  );
  const imageHeader = new DataView(png.buffer, png.byteOffset);
  assert.equal(imageHeader.getUint32(16), 480);
  assert.ok(imageHeader.getUint32(20) > 384);
});

Deno.test("a 500-character title wraps outside an unchanged QR and uses a valid short bank memo", async () => {
  const title = "Ž".repeat(500);
  const payment = {
    payment_method: "bank",
    collectionAction: {
      method: "bank",
      purpose: "collect_payment",
      allowed: true,
    },
    amount: 802.5,
    currency_code: "CZK",
    account_number: "CZ6508000000192000145399",
    creditor_name:
      "Spolek českých pořadatelů, organizátorů slavností a kulturních akcí",
    variable_symbol: "0000062492",
  };
  const order = {
    form: { data: { payment_message: { type: "occasion_title" } } },
  };
  const payload = buildSpdPayload(payment, title);
  assert.equal(decodeURIComponent(payload.split("*MSG:")[1]), "Ž".repeat(60));
  const original = PNG.sync.read(
    await QRCode.toBuffer(payload, {
      width: 384,
      margin: 4,
      errorCorrectionLevel: "M",
    }),
  );
  const large = PNG.sync.read(
    Buffer.from(await generateQrCode(payment, order, title)),
  );
  const short = PNG.sync.read(
    Buffer.from(await generateQrCode(payment, {}, "Ples")),
  );
  assert.ok(large.height > short.height + 500);
  for (let row = 0; row < original.height; row++) {
    const start = (row * large.width + (large.width - original.width) / 2) * 4;
    const source = row * original.width * 4;
    assert.ok(
      large.data.subarray(start, start + original.width * 4)
        .equals(original.data.subarray(source, source + original.width * 4)),
    );
  }
});
