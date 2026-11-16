import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { FormSession } from '../../src/components/forms/form_session.js';

function fixture(t) {
    const dom = new JSDOM('<form></form>', { url: 'http://localhost/' });
    for (const name of ['window', 'document', 'HTMLElement', 'NodeList', 'FormData']) {
        const original = Object.getOwnPropertyDescriptor(globalThis, name);
        globalThis[name] = name === 'window' ? dom.window : dom.window[name];
        t.after(() => original ? Object.defineProperty(globalThis, name, original) : delete globalThis[name]);
    }
    t.after(() => dom.window.close());
    const product = {
        id: 'sub_prod', type: 'product_type', data: {
            selection_type: 'select_many', product_type_data: { products: [
                { id: 'prod_1', price: 500, currency: 'CZK' },
                { id: 'prod_2', price: 20, currency: 'EUR' },
                { id: 'prod_3', price: 300, currency: 'CZK' },
            ] },
        },
    };
    const session = new FormSession({
        id: 'test_form', currencyCode: 'CZK', relatedFields: [], visibleFields: [
            { id: 'ticket', type: 'ticket', subFields: [product] },
            { id: 'user_name', type: 'text' },
        ],
    });
    session.initialize(document.querySelector('form'));
    return session;
}

test('switching currency clears selected products and prices while accepting text fields', t => {
    const session = fixture(t);
    session.state.fields.set('user_name', 'Test User');
    session.addTicket();
    session.updateTicket(0, 'sub_prod', {
        product_type: 'prod_1', price: 500, currency_code: 'CZK', _subFieldId: 'sub_prod',
    });
    assert.equal(session.state.totalPrice, 500);
    assert.equal(session.state.currency, 'CZK');
    session.setCurrency('EUR');
    assert.equal(session.state.currency, 'EUR');
    assert.equal(session.state.totalPrice, 0);
    assert.equal(session.state.tickets[0].fields.length, 0);
});

test('pipe-separated product IDs resolve catalog prices without stored field prices', t => {
    const session = fixture(t);
    session.addTicket();
    session.state.tickets[0].fields = [{ product_type: 'prod_1 | prod_3', _subFieldId: 'sub_prod' }];
    session._syncPayloadFromState();
    session._recalculate();
    assert.equal(session.state.totalPrice, 800);
});
