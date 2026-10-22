import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';
import {OrderResult} from '../../src/components/forms/order_result.js';
import {CardPaymentController} from '../../src/components/forms/card_payment_controller.js';
import {LocalizationService} from '../../src/services/localization_service.js';
const token = 'b'.repeat(64);
const payment = {method: 'stripe', status: 'open', amount: '100', currency: 'CZK', allowedActions: ['pay', 'refresh']};
const access = {kind: 'handoff', token, url: `https://tickets.example/stripe/pay#handoff=${token}`};
const model = {visibleFields: [], communicationTone: 'formal'};
function setup(t) {
  const dom = new JSDOM('<iframe src="https://tickets.example/form/test?embed=1"></iframe>', {url: 'https://host.example/event'});
  const frame = dom.window.document.querySelector('iframe').contentWindow;
  frame.document.open(); frame.document.write('<main></main>'); frame.document.close();
  globalThis.window = frame; globalThis.document = frame.document;
  frame.open = () => assert.fail('must not open a popup programmatically');
  dom.window.postMessage = () => assert.fail('must not send handoff to parent');
  LocalizationService.translations = JSON.parse(fs.readFileSync(new URL('../../../assets/translations/cs.json', import.meta.url)));
  LocalizationService.currentLocale = 'cs';
  t.after(() => dom.window.close());
  return {host: frame.document.querySelector('main'), frame, parent: dom.window};
}
test('embedded handoff is an explicit protected new-tab link, never an automatic payment owner', t => {
  const {host, frame, parent} = setup(t);
  assert.notEqual(frame.top, frame);
  OrderResult.render(host, true, {payment, payment_access: access}, model, () => {}, {
    onPay: () => assert.fail('iframe must not consume handoff'),
    onRefresh: () => assert.fail('iframe must not read handoff'),
  });
  const link = host.querySelector('a.card-payment-handoff');
  assert.ok(link); assert.equal(link.href, access.url);
  assert.equal(link.target, '_blank'); assert.equal(link.rel, 'noopener noreferrer');
  assert.equal(link.onclick, null); assert.match(link.textContent, /nové kartě/);
  assert.equal(host.querySelector('[data-payment-action]'), null);
  assert.equal(frame.history.state, null); assert.equal(frame.localStorage.length, 0); assert.equal(frame.sessionStorage.length, 0);
  assert.equal(parent.location.href, 'https://host.example/event');
  assert.equal(CardPaymentController.fromResult({payment, payment_access: access}), null);
});
test('handoff kind cannot be relabeled as a reusable pay capability by its fragment', () => {
  assert.equal(CardPaymentController.fromResult({payment, payment_access: {...access, url: `https://tickets.example/stripe/pay#pay=${token}`}}), null);
});
test('unsafe, foreign or wrong-scope handoffs never produce a navigation link', t => {
  const {host} = setup(t);
  for (const url of [
    `https://foreign.example/stripe/pay#handoff=${token}`,
    `http://tickets.example/stripe/pay#handoff=${token}`,
    `https://tickets.example/stripe/pay?handoff=${token}`,
    `https://tickets.example/stripe/pay#pay=${token}`,
    `https://tickets.example/stripe/pay#handoff=${'c'.repeat(64)}`,
    `https://user@tickets.example/stripe/pay#handoff=${token}`,
    'javascript:alert(1)',
  ]) {
    OrderResult.render(host, true, {payment, payment_access: {...access, url}}, model, () => {});
    assert.equal(host.querySelector('a'), null, url);
  }
});
test('ordinary pay result keeps its existing controller and has no handoff link', t => {
  const {host} = setup(t);
  const regular = {payment, payment_access: {kind: 'pay', token, url: `https://tickets.example/stripe/pay#pay=${token}`}};
  const controller = CardPaymentController.fromResult(regular, {invoke: async () => ({payment})});
  assert.ok(controller); controller.dispose();
  OrderResult.render(host, true, regular, model, () => {});
  assert.equal(host.querySelector('a.card-payment-handoff'), null);
});
