import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { OrderResult } from '../../src/components/forms/order_result.js';
import { LocalizationService } from '../../src/services/localization_service.js';

for (const locale of ['cs', 'en']) {
    test(`reservation errors render actionable ${locale} text and return to the form`, () => {
        const dom = new JSDOM('<div id="host"></div>', {url:'http://localhost/'});
        globalThis.document = dom.window.document;
        const original = LocalizationService.translations;
        try {
            const catalog = JSON.parse(readFileSync(new URL(`../../../assets/translations/${locale}.json`, import.meta.url)));
            LocalizationService.translations = catalog;
            const host = document.querySelector('#host');
            let returned = 0;
            for (const errorCode of ['reservation_state_unknown', 'reservation_changed', 'reservation_expired', 'CHECKOUT_CONTEXT_EXPIRED']) {
                OrderResult.render(host, false, {code:999, errorCode}, {visibleFields:[]}, () => returned++);
                const message = host.querySelector('.result-subtitle').textContent;
                assert.equal(message, catalog.PublicOrder[errorCode]);
                assert.ok(message.length > 50);
                assert.ok(!message.includes('Waitlist.'));
                host.querySelector('.btn-back-to-form').click();
            }
            assert.equal(returned, 4);
        } finally {
            LocalizationService.translations = original;
            dom.window.close();
        }
    });
}

test('cash confirmation shows saved reservation instructions without bank payment QR',()=>{
 const dom=new JSDOM('<div id="host"></div>',{url:'http://localhost/'});globalThis.document=dom.window.document;
 const previous=LocalizationService.translations;
 try {
  const catalog=JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url)));
  LocalizationService.translations=catalog;
  const host=document.querySelector('#host');
  OrderResult.render(host,true,{ticketOrder:{order:{id:4,order_symbol:'CASH',data:{email:'test@example.invalid'},payment_info:{payment_method:'cash',amount:250.50,currency_code:'CZK',data:{payment_policy:{mode:'none',cashInstructions:'Zaplaťte u vstupu <img src=x>'}}}}},payment_qr:null},{visibleFields:[]},()=>{});
  assert.match(host.textContent,/Rezervace potvrzena/);assert.match(host.textContent,/Zaplaťte u vstupu <img src=x>/);
  assert.equal(host.querySelector('.result-payment-qr'),null);assert.equal(host.querySelector('img[src=x]'),null);
  assert.doesNotMatch(host.textContent,/IBAN|Zaplaťte do/);
 } finally {LocalizationService.translations=previous;dom.window.close();}
});
