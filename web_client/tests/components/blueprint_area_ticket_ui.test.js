import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<body></body>', {url:'http://localhost/form'});
for (const key of ['window','document','HTMLElement','NodeList','HTMLInputElement','EventTarget','Event','CustomEvent']) {
    globalThis[key] = key === 'window' ? dom.window : dom.window[key];
}
const {FormModel} = await import('../../src/components/forms/form_models.js');
const {FormSession} = await import('../../src/components/forms/form_session.js');
const {TicketFieldBuilder} = await import('../../src/components/forms/fields/ticket_field_builder.js');
const {FormValidator} = await import('../../src/components/forms/form_validator.js');

test('standing ticket shows its admission product without a required addressed seat', () => {
    const model = new FormModel({key:'k',secret:'s',fields:[
        {id:99,type:'ticket',data:{max_tickets:5}},
        {id:17,type:'spot',is_ticket_field:true,is_required:true,title:'Seat'},
        {id:23,type:'product_type',is_ticket_field:true,product_type_data:{id:3,type:'spot',products:[{id:9,title:'Standing admission',price:80,currency_code:'CZK'}]}},
    ]});
    const session = new FormSession(model);
    session.setAreaQuantity({nodeId:'standing',productId:9},2,5,{id:9,title:'Standing admission',price:80,currency_code:'CZK'});
    const view = TicketFieldBuilder.create(model.visibleFields.find(field=>field.type==='ticket'),model,session);
    const form = document.createElement('form');
    form.appendChild(view);
    document.body.appendChild(form);
    assert.equal(view.querySelectorAll('.ticket-area-product').length,2);
    assert.match(view.textContent,/Standing admission/);
    assert.equal(view.querySelectorAll('input[required]').length,0);
    assert.doesNotMatch(view.textContent,/Seat\s*\*/);
    assert.equal(session.payload.ticket[0].fields[0].product_type,9);
    assert.equal(session.payload.ticket[0].spot,undefined);
    assert.equal(FormValidator.validateAndShowErrors(form,model,session),true);
});

test('standing summary and payload work without a duplicate admission product field', () => {
    const model = new FormModel({key:'k',secret:'s',fields:[{id:99,type:'ticket'},{id:17,type:'spot',is_ticket_field:true,is_required:true}]});
    const session = new FormSession(model);
    session.setAreaQuantity({nodeId:'standing',productId:9},1,3,{id:9,title:'Bound standing',price:80,currency_code:'CZK'});
    const view=TicketFieldBuilder.create(model.visibleFields.find(f=>f.type==='ticket'),model,session);
    assert.match(view.textContent,/Bound standing/);
    assert.equal(session.state.totalPrice,80);
    assert.equal(session.payload.ticket[0].fields[0].product_type,9);
    assert.equal(session.payload.ticket[0].spot,undefined);
    assert.equal(session.payload.ticket[0]._blueprintProduct,undefined);
    assert.equal(view.querySelectorAll('input[required]').length,0);
});
