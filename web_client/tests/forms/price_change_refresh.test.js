import test from 'node:test';
import assert from 'node:assert/strict';
import {register} from 'node:module';
import {JSDOM} from 'jsdom';
register('../css_loader.mjs', import.meta.url);
const dom = new JSDOM('<main id="form-page-container"></main>', {url: 'https://example.test/form/test'});
for (const name of ['window', 'document', 'HTMLElement', 'EventTarget', 'Event', 'CustomEvent']) globalThis[name] = name === 'window' ? dom.window : dom.window[name];
const [{FormSession}, {FormModel}, {FormPage}, {DbForms}] = await Promise.all([
  import('../../src/components/forms/form_session.js'), import('../../src/components/forms/form_models.js'),
  import('../../src/components/forms/form_page.js'), import('../../src/components/forms/db_forms.js'),
]);
const model = (price = 200) => new FormModel({
  key: 'test', secret: 'read-secret', is_open: true, registrationMode: 'regular',
  payments: {recipient: {connectionId: 'new-account', name: 'Current organizer'}},
  fields: [
    {id: 1, type: 'ticket', data: {max_tickets: 4}},
    {id: 2, type: 'name', is_ticket_field: true},
    {id: 3, type: 'product_type', is_ticket_field: true, product_type_data: {products: [{id: 30, title: 'Admission', price, currency_code: 'CZK'}]}},
    {id: 4, type: 'id_document', is_ticket_field: true}, {id: 5, type: 'email'},
    {id: 6, type: 'product_type', product_type_data: {products: [{id: 60, title: 'Extra', price: 25, currency_code: 'CZK'}]}},
    {id: 7, type: 'spot', is_ticket_field: true},
  ],
});
const previous = () => {
  const session = new FormSession(model(100)); session.formModel.secret = 'held-seat-secret';
  session.state.fields.set('5', 'person@example.test'); session.state.fields.set('6', '60');
  session.state.tickets = [{spot: 40, spotPrice: 999, fields: [
    {_subFieldId: 2, name: 'Alex'}, {_subFieldId: 3, product_type: '30', price: 100, currency_code: 'CZK'},
    {_subFieldId: 4, id_document: {id_document_number: 'ABC', id_document_expiry_date: '2030-01-01'}},
  ]}]; return session;
};
test('refreshed form renders retained email and checkbox answers in the real controls', async () => {
  const {FormRenderer} = await import('../../src/components/forms/form_renderer.js');
  const form = new FormModel({key:'refresh', fields:[
    {id:51,type:'email',is_required:true},
    {id:52,type:'select_many',data:{options:[{id:'a',title:'A'},{id:'b',title:'B'}]}},
  ]});
  const old = new FormSession(form);
  old.state.fields.set('51','person+refresh@example.test');
  old.state.fields.set('52','a | b');
  const next = new FormSession(form); next.restoreDraft(old);
  const host=document.createElement('main');
  FormRenderer.render(host,next,form,false,{});
  assert.equal(host.querySelector('input[type=email]').value,'person+refresh@example.test');
  assert.equal(host.querySelectorAll('input[type=checkbox]:checked').length,2);
  assert.equal(next.state.fields.get('51'),'person+refresh@example.test');
});
test('restores personal answers and fresh product/seat prices, including free seat', () => {
  const old = previous();
  for (const price of [300, 0]) {
    const next = new FormSession(model());
    next.restoreDraft(old, [{id: 40, title: 'Current seat', state: 'selected_by_me', productModel: {price}}]);
    assert.equal(next.state.fields.get('5'), 'person@example.test');
    assert.equal(next.state.tickets[0].fields[0].name, 'Alex');
    assert.deepEqual(next.state.tickets[0].fields[2].id_document, old.state.tickets[0].fields[2].id_document);
    assert.equal(next.state.totalPrice, 225 + price);
    assert.equal(next.state.tickets[0].spotPrice, price);
  }
  assert.equal(old.state.tickets[0].spotPrice, 999);
});
test('booked seat loses old quote but keeps person for reselection', () => {
  const next = new FormSession(model());
  next.restoreDraft(previous(), [{id: 40, state: 'ordered', productModel: {price: 300}}]);
  assert.equal(next.state.tickets[0].spot, undefined);
  assert.equal(next.state.tickets[0].spotPrice, undefined);
  assert.equal(next.state.tickets[0].fields[0].name, 'Alex');
  assert.equal(next.state.totalPrice, 225);
});
test('explicit recovery fetches current recipient and held seat prices without submitting', async () => {
  const read = DbForms.getFormByLink, blueprint = DbForms.getBlueprint;
  const page = new FormPage('form-page-container');
  page.currentSession = previous(); page.currentLink = 'test'; page.host = document.querySelector('main'); page.host.replaceChildren();
  let reads = 0, submits = 0, rendered;
  page.submitOrder = () => submits++;
  page.renderForm = (latest, preview, draft) => { rendered = {latest, draft}; };
  DbForms.getFormByLink = async () => { reads++; const latest = model(); latest.blueprint = 9; return latest; };
  DbForms.getBlueprint = async (secret, key, id) => {
    assert.deepEqual([secret, key, id], ['held-seat-secret', 'test', 9]);
    return {layout:{nodes:[]}, seatBindings:[{nodeId:'seat40',spotId:40,productId:90}], spots: [{id: 40, state: 'selected_by_me', product: 90}], products: [{id: 90, price: 300}]};
  };
  try {
    await page.refreshCapacityChoice(page.currentSession.formModel, 'STRIPE_PRICE_CHANGED');
    assert.equal(reads, 0); assert.equal(rendered, undefined);
    await page.host.querySelector('button').onclick();
    assert.equal(reads, 1); assert.equal(rendered.draft.review, true);
    assert.equal(rendered.latest.payments.recipient.connectionId, 'new-account');
    assert.equal(rendered.draft.spots[0].productModel.price, 300);
    assert.equal(page._pendingPaymentQuote, null); assert.equal(submits, 0);
  } finally { DbForms.getFormByLink = read; DbForms.getBlueprint = blueprint; }
});
test('failed refresh preserves draft and permits explicit retry', async () => {
  const read = DbForms.getFormByLink; const page = new FormPage('form-page-container');
  const old = previous(); page.currentSession = old; page.currentLink = 'test';
  page.host = document.querySelector('main'); page.host.replaceChildren();
  DbForms.getFormByLink = async () => { throw new Error('offline'); };
  try {
    await page.refreshCapacityChoice(old.formModel, 'STRIPE_PRICE_CHANGED');
    const button = page.host.querySelector('button'); await button.onclick();
    assert.equal(button.disabled, false); assert.equal(page.currentSession, old);
    assert.equal(old.state.fields.get('5'), 'person@example.test');
  } finally { DbForms.getFormByLink = read; }
});
test('recipient change mandates fresh catalog/recipient review, preserves answers and never resubmits', async () => {
  const [{paymentMethodText}, {WaitlistStrings}, {OrderResult}] = await Promise.all([
    import('../../src/components/forms/payment_method_strings.js'),
    import('../../src/components/forms/waitlist_strings.js'),
    import('../../src/components/forms/order_result.js'),
  ]);
  const read = DbForms.getFormByLink;
  const page = new FormPage('form-page-container');
  const old = previous(); page.currentSession = old; page.currentLink = 'test';
  page.host = document.querySelector('main'); page.host.replaceChildren();
  let reads = 0, submits = 0, rendered;
  page.submitOrder = () => submits++;
  page.renderForm = (latest, preview, draft) => {
    const restored = new FormSession(latest);
    restored.restoreDraft(draft.previous, draft.spots);
    rendered = {latest, draft, restored};
  };
  DbForms.getFormByLink = async () => { reads++; return model(250); };
  try {
    await page.refreshCapacityChoice(old.formModel, 'STRIPE_RECIPIENT_CHANGED');
    assert.equal(reads, 0);
    assert.equal(page._paymentReviewPending, true);
    assert.equal(page.host.querySelector('p').textContent, paymentMethodText('reason_recipient_changed'));
    assert.equal(page.host.querySelector('button').textContent, WaitlistStrings.refresh);
    // The ordinary continue action must also go through mandatory refresh.
    page.validateAndSubmit(document.createElement('form'), old.formModel);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(reads, 1); assert.equal(submits, 0);
    assert.equal(rendered.draft.review, true);
    assert.equal(rendered.latest.payments.recipient.connectionId, 'new-account');
    assert.equal(rendered.restored.state.fields.get('5'), 'person@example.test');
    assert.equal(rendered.restored.state.tickets[0].fields[0].name, 'Alex');
    assert.equal(rendered.restored.state.totalPrice, 275);
    assert.equal(page._pendingPaymentQuote, null);
    assert.equal(page._paymentReviewPending, false);
    const error = document.createElement('section');
    OrderResult.render(error, false, {errorCode: 'STRIPE_RECIPIENT_CHANGED'}, {...model(), visibleFields: [], communicationTone: 'formal'}, () => {});
    assert.equal(error.querySelector('.result-title').textContent, paymentMethodText('reason_recipient_changed'));
    assert.equal(error.querySelector('.result-subtitle').textContent, WaitlistStrings.refresh);
  } finally { DbForms.getFormByLink = read; }
});
