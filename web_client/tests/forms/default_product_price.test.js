import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!doctype html><body></body>', { url: 'http://localhost/' });
global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;
global.FormData = dom.window.FormData;
global.EventTarget = dom.window.EventTarget;
global.Event = dom.window.Event;
global.CustomEvent = dom.window.CustomEvent;
global.getComputedStyle = dom.window.getComputedStyle;
const { TicketFieldBuilder } = await import('../../src/components/forms/fields/ticket_field_builder.js');
const { FormSession } = await import('../../src/components/forms/form_session.js');
const { PriceWidget } = await import('../../src/components/forms/widgets/price_widget.js');
for (const maxTickets of [1, 3]) {
  for (const many of [false, true]) {
    test(`initial default products and floating price: max=${maxTickets}, many=${many}`, async () => {
      document.body.innerHTML = '<form></form>';
      const options = [{id: 10, title: 'Other', price: 25, currency: 'CZK'}, {id: 20, title: 'Dinner', price: 150, currency: 'CZK'}, {id: 30, title: 'Lunch', price: 100, currency: 'CZK'}];
      const sub = {id: 2, type: 'product_type', title: 'Meals', options, data: {default_value: many ? ['20', '30'] : '20', selection_type: many ? 'select_many' : 'select_one'}};
      const ticket = {id: 1, type: 'ticket', title: 'Tickets', subFields: [sub], data: {max_tickets: maxTickets}};
      const model = {key: 'test', secret: 'test', visibleFields: [ticket], relatedFields: [ticket], occasionFeatures: []};
      const session = new FormSession(model);
      const price = new PriceWidget(session, document.body);
      const form = document.querySelector('form');
      form.appendChild(TicketFieldBuilder.create(ticket, model, session));
      session.initialize(form);
      const expected = many ? 250 : 150;
      const selected = () => Array.from(form.querySelectorAll('input:checked')).map(i => i.value).sort();
      assert.deepEqual(selected(), many ? ['20', '30'] : ['20']);
      assert.equal(session.state.totalPrice, expected);
      assert.equal(session.payload.ticket.length, 1);
      assert.ok(document.querySelector('#floating-price-widget'));
      assert.match(document.querySelector('#floating-price-widget').textContent, new RegExp(String(expected)));
      // Re-emitting state must preserve every selected product.
      session.refreshPayload(form);
      assert.deepEqual(selected(), many ? ['20', '30'] : ['20']);
      if (maxTickets > 1) {
        session.addTicket();
        await new Promise(resolve => setImmediate(resolve));
        assert.equal(session.state.totalPrice, expected * 2);
        assert.deepEqual(selected(), many ? ['20', '20', '30', '30'] : ['20', '20']);
      }
      price.destroy();
    });
  }
}
test('card product options, recap rows and floating total retain exact fractional prices',async()=>{
 const {OptionBuilderHelper}=await import('../../src/components/forms/fields/option_builder_helper.js');
 const {FieldPreviewFactory}=await import('../../src/components/forms/previews/field_preview_factory.js');
 const option={id:20,title:'Admission',price:123.45,currency:'CZK'};
 const model={payments:{configured:{stripe:true}}};
 const row=OptionBuilderHelper.buildOptionWrapper({id:2,type:'product_type'},option,model,'radio',true);
 assert.match(row.textContent,/123[,.]45/);
 assert.match(FieldPreviewFactory.format({type:'product_type',options:[option]},20,{currency:'CZK',cardPricing:true}).price,/123[,.]45/);
 document.body.innerHTML='';
 const session=new dom.window.EventTarget();session.formModel=model;
 const widget=new PriceWidget(session,document.body);
 session.dispatchEvent(new dom.window.CustomEvent('state-changed',{detail:{totalPrice:123.45,totalItems:1,currency:'CZK',metaSurchargeSums:[]}}));
 assert.match(document.body.textContent,/123[,.]45/);widget.destroy();
});
