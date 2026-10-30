import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('', { url: 'https://forms.example/' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
    HTMLElement: dom.window.HTMLElement, Node: dom.window.Node, Event: dom.window.Event });
after(() => dom.window.close());
const { FormModel } = await import('../../src/components/forms/form_models.js');
const { FormFieldBuilder } = await import('../../src/components/forms/fields/form_field_builder.js');

test('application-only ticket container renders its prices and note without enabling issuance', () => {
    const model = new FormModel({ fields: [
        { id: 1, type: 'ticket', is_hidden: true, data: { max_tickets: 1 } },
        { id: 2, type: 'product_type', title: 'Registration', is_ticket_field: true,
            is_hidden: false, product_type_data: { products: [
                { id: 10, title: 'Standard', price: 2650, currency_code: 'CZK' },
            ] } },
        { id: 3, type: 'note', title: 'Note', is_ticket_field: true, is_hidden: false },
    ] });
    assert.equal(model.visibleFields.length, 1);
    const container = model.visibleFields[0];
    assert.equal(container.isHidden, true, 'issuance setting is preserved');
    const session = { maxTickets: 1, state: { tickets: [] },
        addTicket() { this.state.tickets.push({ fields: [] }); },
        addEventListener() {}, removeEventListener() {} };
    const node = FormFieldBuilder.createFormField(container, model, session);
    document.body.append(node);
    const price = node.querySelector('input[value="10"]');
    const note = node.querySelector('input[data-sub-id="3"]');
    assert.ok(price, 'actual product selector is rendered');
    assert.ok(note, 'participant note is rendered');
    for (const input of [price, note]) {
        for (let ancestor = input; ancestor; ancestor = ancestor.parentElement) {
            assert.notEqual(ancestor.style.display, 'none', 'application fields stay visible');
        }
    }
    assert.match(node.textContent, /2650/);
    price.click();
    assert.equal(price.checked, true);
    node.destroy?.();
    node.remove();
});
