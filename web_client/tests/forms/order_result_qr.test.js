import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { OrderResult } from '../../src/components/forms/order_result.js';
import { LocalizationService } from '../../src/services/localization_service.js';
import cs from '../../public/assets/translations/cs.json' with { type: 'json' };

const cases = [
  { format: 'SPD', payload: 'SPD*1.0*ACC:CZ6508000000192000145399*AM:490.00*CC:CZK*X-VS:123456789', reference_kind: 'VS', reference: '123456789', amount: 490, currency_code: 'CZK' },
  { format: 'EPC_SCT', payload: 'BCD\n002\n1\nSCT\n\nExample\nDE89370400440532013000\nEUR12.50\n\nRF18539007547034\n\n', reference_kind: 'RF', reference: 'RF18 5390 0754 7034', amount: 12.5, currency_code: 'EUR' },
];

for (const payment of cases) {
  test(`order result renders downloadable ${payment.format} QR from server payload`, async () => {
    const dom = new JSDOM('<div id="host"></div>', { url: 'http://localhost/' });
    global.document = dom.window.document;
    LocalizationService.translations = cs;
    const host = document.querySelector('#host');
    OrderResult.render(host, true, {
      payment_qr: { ...payment, account_number: payment.currency_code === 'EUR' ? 'DE89370400440532013000' : 'CZ6508000000192000145399' },
      ticketOrder: { order: { data: { email: 'zakaznik@example.cz' } } },
    },
      { communicationTone: 'formal', visibleFields: [{ type: 'ticket' }] }, () => {});
    for (let attempt = 0; attempt < 30 && !host.querySelector('.result-payment-qr'); attempt++) {
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    const image = host.querySelector('.result-payment-qr');
    assert.ok(image, 'QR image should be visible');
    assert.match(image.src, /^data:image\/png;base64,iVBOR/);
    assert.equal(host.querySelector('.result-download')?.href, image.src);
    assert.equal(host.querySelector('.result-download')?.download, 'platba-qr.png');
    assert.equal(host.querySelector('.result-payment-more')?.open, false);
    assert.equal(host.querySelector('.result-payment-more summary')?.textContent, 'Zobrazit možnosti platby');
    host.querySelector('.result-payment-more').open = true;
    assert.equal(host.querySelector('.result-payment-more')?.open, true);
    assert.match(host.querySelector('.result-subtitle')?.textContent || '', /zakaznik@example.cz/);
    assert.match(host.querySelector('.result-subtitle')?.textContent || '', /obvykle během několika minut/);
    assert.doesNotMatch(host.querySelector('.result-payment-card')?.textContent || '', /zakaznik@example.cz/);
    assert.equal(host.querySelector('.result-payment-total')?.textContent,
      payment.currency_code === 'EUR' ? '12,50 EUR' : '490 CZK');
    assert.ok(host.textContent.includes(payment.reference));
    assert.equal(host.querySelectorAll('.result-copy').length, 3);
    dom.window.close();
  });
}

test('free or failed orders do not show a payment card', () => {
  const dom = new JSDOM('<div id="host"></div>', { url: 'http://localhost/' });
  global.document = dom.window.document;
  LocalizationService.translations = cs;
  const host = document.querySelector('#host');
  const model = { communicationTone: 'formal', visibleFields: [] };
  OrderResult.render(host, true, { code: 200, ticketOrder: { order: { data: { email: 'free@example.cz' } } } }, model, () => {});
  assert.equal(host.querySelector('.result-payment-card'), null);
  assert.match(host.querySelector('.result-subtitle')?.textContent || '', /free@example.cz/);
  assert.match(host.querySelector('.result-subtitle')?.textContent || '', /obvykle během několika minut/);
  assert.doesNotMatch(host.querySelector('.result-subtitle')?.textContent || '', /platební údaje/);
  OrderResult.render(host, false, { code: 999, payment_qr: cases[0] }, model, () => {});
  assert.equal(host.querySelector('.result-payment-card'), null);
  dom.window.close();
});

test('confirmation prints the returned email as text', () => {
  const dom = new JSDOM('<div id="host"></div>', { url: 'http://localhost/' });
  global.document = dom.window.document;
  LocalizationService.translations = cs;
  const host = document.querySelector('#host');
  const email = 'user@example.cz<script>bad()</script>';
  OrderResult.render(host, true, { ticketOrder: { order: { data: { email } } } },
    { communicationTone: 'formal', visibleFields: [] }, () => {});
  assert.equal(host.querySelectorAll('script').length, 0);
  assert.ok(host.querySelector('.result-subtitle')?.textContent.includes(email));
  dom.window.close();
});

test('Czech informal confirmation uses tykání with the returned address', () => {
  const dom = new JSDOM('<div id="host"></div>', { url: 'http://localhost/' });
  global.document = dom.window.document;
  LocalizationService.translations = cs;
  const host = document.querySelector('#host');
  OrderResult.render(host, true, {
    payment_qr: { amount: 490, currency_code: 'CZK' },
    ticketOrder: { order: { data: { email: 'zakaznik@example.cz' } } },
  }, { communicationTone: 'informal', visibleFields: [{ type: 'ticket' }] }, () => {});
  assert.match(host.querySelector('.result-title')?.textContent || '', /^Tvá objednávka/);
  assert.match(host.querySelector('.result-subtitle')?.textContent || '', /údaje ti přijdou na e-mail zakaznik@example.cz, obvykle během několika minut/);
  dom.window.close();
});
