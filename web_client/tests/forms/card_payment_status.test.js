import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { JSDOM } from 'jsdom';
import { LocalizationService } from '../../src/services/localization_service.js';
import { renderCardPaymentStatus, canContinueCardPayment } from '../../src/components/forms/card_payment_status.js';
import { renderOrderOverview } from '../../src/components/forms/order_overview.js';
import { OrderResult } from '../../src/components/forms/order_result.js';
const cs=JSON.parse(fs.readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url),'utf8'));
const payment = patch => ({ method:'stripe',status:'open',amount:'1234.50',received:'0',returned:'0',currency:'CZK',admissionState:'pending',allowedActions:['refresh','pay'],...patch });
function setup(t) {
 const dom=new JSDOM('<!doctype html><html lang="cs"><body><main></main></body></html>',{url:'https://tickets.example/form/test'});
 globalThis.window=dom.window;globalThis.document=dom.window.document;LocalizationService.translations=cs;LocalizationService.currentLocale='cs';
 t.after(()=>dom.window.close());return document.querySelector('main');
}
test('A08 safe projection cannot supply pay capability; view remains read only even with a pay label',t=>{
 const host=setup(t);renderCardPaymentStatus(host,payment(),{onRefresh:()=>{}});
 assert.equal(host.querySelectorAll('button').length,1);
 assert.match(host.textContent,/soukromý platební odkaz/);
 assert.equal(host.querySelector('a,input,img,canvas'),null);
 assert.equal(host.querySelector('[role=status]').getAttribute('aria-atomic'),'true');
 assert.match(host.textContent,/1234,50/);
});
test('A15 paid and failed email remain distinct, with no second payment invitation',t=>{
 const host=setup(t);renderCardPaymentStatus(host,payment({status:'paid',received:'1234.50',deliveryState:'suppressed'}),{onPay:()=>assert.fail('must not pay')});
 assert.match(host.textContent,/Zaplaceno\./);assert.match(host.textContent,/email se nepodařilo odeslat/);
 assert.equal(host.querySelectorAll('button').length,0);
});
test('A17/A18 refund, partial refund and admission hold never create a new card debt',t=>{
 const host=setup(t);
 for(const state of ['refunded','partially_refunded','disputed','action_required','unknown','expired','pending']) {
  const p=payment({status:state,admissionState:'hold'});assert.equal(canContinueCardPayment(p),false);
  renderCardPaymentStatus(host,p,{onPay:()=>assert.fail('must not pay')});assert.equal(host.querySelectorAll('button').length,0);
 }
});
test('A09 pay button blocks duplicate clicks and remains disabled after an uncertain failure',async t=>{
 const host=setup(t);let calls=0;let reject;
 renderCardPaymentStatus(host,payment(),{onPay:()=>{calls++;return new Promise((_resolve,r)=>{reject=r;});},onRefresh:()=>{}});
 const button=host.querySelector('button');button.click();button.click();assert.equal(calls,1);assert.equal(button.disabled,true);
 reject(new Error('provider secret must not be rendered'));await new Promise(resolve=>setImmediate(resolve));
 assert.equal(button.disabled,true);assert.match(host.textContent,/Aktuální stav nelze ověřit/);assert(!host.textContent.includes('provider secret'));
});
test('A15 delivery observation changes only delivery copy and preserves keyboard focus',t=>{
 const host=setup(t);const view=renderCardPaymentStatus(host,payment({status:'paid'}),{onRefresh:()=>{}});
 const button=host.querySelector('button');button.focus();view.updateDelivery('accepted');assert.equal(document.activeElement,button);
 assert.match(host.textContent,/předán k odeslání/);assert.equal(host.querySelectorAll('[role=status]').length,1);
});
test('A08 overview and result route render real card states without bank QR or success animation',t=>{
 const host=setup(t);
 renderOrderOverview(host,{root:{title:'Synthetic',symbol:'ORDER'},serverTime:'2026-10-21',people:[],offers:[],orders:[{symbol:'ORDER',state:'ordered',total:1234.5,currency:'CZK',items:[],tickets:[],payment:payment()}]},()=>{});
 assert.match(host.textContent,/Dokončete platbu/);assert.equal(host.querySelector('a,input,img,canvas'),null);
 OrderResult.render(host,true,{payment:payment({status:'pending'}),ticketOrder:{order:{order_symbol:'ORDER'}}},{visibleFields:[],communicationTone:'formal'},()=>{});
 assert.match(host.textContent,/Ověřujeme výsledek/);assert.equal(host.querySelector('.success-color,img,canvas'),null);
});
test('A24 all supported locales define every card state and long translations use flexible controls',t=>{
 const host=setup(t),keys=Object.keys(cs.CardPayments);
 for(const lang of ['en','sk','pl','de','uk']) {
  const catalog=JSON.parse(fs.readFileSync(new URL(`../../../assets/translations/${lang}.json`,import.meta.url),'utf8'));
  assert.deepEqual(Object.keys(catalog.CardPayments).sort(),[...keys].sort());
  LocalizationService.translations=catalog;LocalizationService.currentLocale=lang;
  renderCardPaymentStatus(host,payment(),{onPay:()=>{}});
  assert(!host.textContent.includes('CardPayments.'));assert.equal(host.querySelector('button').style.whiteSpace,'normal');
 }
});
