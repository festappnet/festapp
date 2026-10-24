import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';
import {LocalizationService} from '../../src/services/localization_service.js';
import {formPaymentOptions} from '../../src/components/forms/form_payment_options.js';
import {renderPaymentMethodPicker} from '../../src/components/forms/payment_method_picker.js';
const id='12345678-1234-4234-8234-123456789abc';
const options=()=>({configured:{bank:true,stripe:true},available:['stripe','bank'],supportedSurfaces:['web'],reservationSeconds:1860,recipient:{connectionId:id,name:'Verified organizer'}});
function setup(t){const dom=new JSDOM('<main></main>');globalThis.window=dom.window;globalThis.document=dom.window.document;LocalizationService.translations=JSON.parse(fs.readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url),'utf8'));LocalizationService.currentLocale='cs';t.after(()=>dom.window.close());return document.querySelector('main');}
test('A06 unavailable methods never silently select bank and unverified iframe excludes card',()=>{
  assert.deepEqual(formPaymentOptions(null).available,['bank']);assert.deepEqual(formPaymentOptions({...options(),available:[]}).available,[]);assert.deepEqual(formPaymentOptions(options(),'embed').available,['bank']);
});
test('A06/A24 one method is a summary; two methods have a labelled choice and independent full-payment hint',t=>{
  const host=setup(t);const values=[];
  renderPaymentMethodPicker(host,formPaymentOptions({...options(),available:['stripe']}),value=>values.push(value));assert.equal(host.querySelector('input'),null);assert.match(host.textContent,/31 minut/);assert.match(host.textContent,/celé objednávky/);
  host.replaceChildren();renderPaymentMethodPicker(host,formPaymentOptions(options()),value=>values.push(value));assert.equal(host.querySelectorAll('input[type=radio]').length,2);const bank=host.querySelector('[value=bank]');bank.checked=true;bank.dispatchEvent(new window.Event('change'));assert.equal(values.at(-1),'bank');assert(!host.textContent.includes('31 minut'));
});
test('A07 recipient shown in the preview is a detached snapshot and names are text',t=>{
  const host=setup(t),raw=options();raw.recipient.name='<script>private</script>';const normalized=formPaymentOptions(raw);raw.recipient.connectionId='changed';renderPaymentMethodPicker(host,normalized,()=>{});assert.equal(normalized.recipient.connectionId,id);assert.equal(host.querySelector('script'),null);assert.match(host.textContent,/<script>/);
});

test('bank-only preview hides redundant payment UI while selecting bank; unavailable and card flows remain visible',t=>{
  const host=setup(t),values=[];
  const state=renderPaymentMethodPicker(host,formPaymentOptions(null),value=>values.push(value));
  assert.equal(host.hidden,true);assert.equal(host.textContent,'');assert.equal(state.selected,'bank');assert.deepEqual(values,['bank']);
  renderPaymentMethodPicker(host,formPaymentOptions({...options(),available:[]}),value=>values.push(value));
  assert.equal(host.hidden,false);assert.equal(host.querySelector('[role=alert]')!==null,true);assert.equal(values.at(-1),null);
  renderPaymentMethodPicker(host,formPaymentOptions(options()),value=>values.push(value));
  assert.equal(host.hidden,false);assert.equal(host.querySelectorAll('input[type=radio]').length,2);
});
