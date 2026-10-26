
import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { JSDOM } from 'jsdom';

// 1. Setup DOM environment
const setupDOM = () => {
    const dom = new JSDOM(`
        <!DOCTYPE html>
        <body>
            <form id="testForm">
            </form>
        </body>
    `, { 
        url: 'http://localhost',
        pretendToBeVisual: true
    });
    
    global.window = dom.window;
    global.document = dom.window.document;
    global.HTMLElement = dom.window.HTMLElement;
    global.NodeList = dom.window.NodeList;

    
    // Mock FormData
    global.FormData = dom.window.FormData;
};

// Imports
import { FormSession } from '../../src/components/forms/form_session.js';

test('Reproduce Currency Switching Bug', async (t) => {
    setupDOM();
    const form = document.getElementById('testForm');

    // Mock Form Model with mixed currencies
    const formModel = {
        id: 'test_form',
        currencyCode: 'CZK',
        relatedFields: [],
        visibleFields: [
            {
                id: 'ticket',
                type: 'ticket',
                subFields: [
                    {
                        id: 'sub_prod',
                        type: 'product_type', 
                        data: {
                            product_type_data: {
                                products: [
                                    { id: 'prod_czk', title: 'Prod CZK', price: 100, currencyCode: 'CZK' },
                                    { id: 'prod_eur', title: 'Prod EUR', price: 10, currencyCode: 'EUR' }
                                ]
                            }
                        }
                    }
                ]
            },
            {
                id: 'user_name',
                type: 'text',
                title: 'Name'
            }
        ]
    };

    const session = new FormSession(formModel);
    session.initialize(form);
    
    // Add standard field to trigger loop logic
    session.state.fields.set('user_name', 'Test User');

    // Initial state check
    assert.strictEqual(session.state.currency, 'CZK', 'Should default to CZK (first available/priority)');

    // 1. Select a CZK product
    session.addTicket();
    // Simulate selection
    session.updateTicket(0, 'sub_prod', { 
        type: 'product_type', 
        product_type: 'prod_czk', 
        price: 100, 
        _subFieldId: 'sub_prod' 
    });

    // Verify selection
    assert.strictEqual(session.state.totalPrice, 100);
    assert.strictEqual(session.state.currency, 'CZK');

    // 2. Attempt to switch to EUR
    // logic: setCurrency should clear incompatible fields (CZK product) and set currency to EUR.
    session.setCurrency('EUR');

    // Wait for any async queue (though setCurrency is synchronous-ish, spotQueue is async)
    await new Promise(r => setTimeout(r, 10));

    // Verify
    // The bug report says "cannot switch". 
    // This implies either the currency stays CZK OR it switches but immediately switches back?
    // Or maybe the UI widget doesn't update?
    
    const state = session.state;
    console.log('State after switch:', { currency: state.currency, price: state.totalPrice, tickets: state.tickets[0].fields });

    assert.strictEqual(state.currency, 'EUR', 'Currency should match requested currency');
    assert.strictEqual(state.totalPrice, 0, 'Price should be 0 after clearing incompatible items');
    assert.strictEqual(state.tickets[0].fields.length, 0, 'Fields should be cleared');
    
});
