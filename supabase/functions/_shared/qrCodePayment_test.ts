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
