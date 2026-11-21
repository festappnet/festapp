import { generatePaymentDetails } from "./translations/payment-details.helpers.ts";
import assert from 'node:assert/strict';
import {generateQrCode} from './qrCodePayment.ts';
Deno.test('direct collection QR owner refuses missing purpose, disabled and gateway sources before rendering', async () => {
  const bank={payment_method:'bank',amount:100,currency_code:'CZK',collectionAction:{method:'bank',purpose:'collect_payment',allowed:true}};
  for (const payment of [
    {amount:100}, {...bank,payment_method:'stripe'}, {...bank,payment_method:'orchard'},
    {...bank,collectionAction:{...bank.collectionAction,allowed:false}},
    {...bank,collectionAction:{...bank.collectionAction,purpose:'bank_refund_instruction'}},
    {...bank,currency_code:'USD'}, {...bank,collectionAction:undefined},{...bank,amount:0},
  ]) await assert.rejects(()=>generateQrCode(payment,{},'Testovací ples'), /payment_qr_action_forbidden/);
});

Deno.test("long SEPA IBAN is a single, grouped HTML value and the PNG is square", async () => {
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
  const png = await generateQrCode({
    payment_method: "bank",
    collectionAction: { method: "bank", purpose: "collect_payment", allowed: true },
    account_number: iban,
    currency_code: "EUR",
    amount: 80,
    creditor_name: "Organizer",
    creditor_reference: "RF18539007547034",
  }, {}, "Sample");
  const imageHeader = new DataView(png.buffer, png.byteOffset);
  assert.equal(imageHeader.getUint32(16), 384);
  assert.equal(imageHeader.getUint32(20), 384);
});
