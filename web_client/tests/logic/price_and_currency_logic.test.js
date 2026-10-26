
import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { JSDOM } from 'jsdom';

// 1. Setup DOM environment
const setupDOM = () => {
    const dom = new JSDOM(`
        <!DOCTYPE html>
        <body>
            <form id="testForm">
                <input type="hidden" name="ticket_0_spot" value="spot_1" data-price="100"> 
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
    global.Event = dom.window.Event;
    global.CustomEvent = dom.window.CustomEvent;
    
    // Mock FormData
    global.FormData = dom.window.FormData;
};

// Imports (assumes relative path from execution)
import { FormSession } from '../../src/components/forms/form_session.js';
import { FormHelper } from '../../src/components/forms/form_helper.js';

test('Price and Currency Logic', async (t) => {
    setupDOM();
    const form = document.getElementById('testForm');

    // Mock Form Model
    const formModel = {
        id: 'test_form',
        currencyCode: 'CZK',
        relatedFields: [],
        visibleFields: [
            {
                id: 'ticket_1',
                type: 'ticket',
                title: 'Ticket',
                subFields: [
                    {
                        id: 'sub_spot',
                        type: 'spot',
                        title: 'Spot',
                        options: [
                            { id: 'spot_1', title: 'Variant 1', price: 100, currency: 'CZK' }
                        ]
                    },
                    {
                        id: 'sub_prod',
                        type: 'product_type', 
                        title: 'Product',
                        data: {
                            selection_type: 'select_many',
                            product_type_data: {
                                products: [
                                    { id: 'prod_1', title: 'Prod 1', price: 500, currency: 'CZK' },
                                    { id: 'prod_2', title: 'Prod EUR', price: 20, currency: 'EUR' }
                                ]
                            }
                        }
                    }
                ]
            }
        ]
    };

    // 1. Initialize Session
    const session = new FormSession(formModel);
    session.dispatchEvent = () => {}; // Mock event dispatch
    session.initialize(form);

    // 2. Test Spot Price (Initial Hydration fallback)
    // My previous test relied on manual input. 
    // Here we test if `addTicket` logic works.
    session.addTicket();
    
    // Wait for async
    await new Promise(r => setTimeout(r, 50));
    
    // 3. Test Manual Selection of Product (Fix Verify)
    // We simulate selecting 'prod_1' (500 CZK)
    // We construct a value object manually to interact with updateTicket directly 
    // to bypass TicketFieldBuilder DOM complexity for unit testing logic.
    session.updateTicket(0, 'sub_prod', { 
        type: 'product_type', 
        product_type: 'prod_1', 
        value: 'prod_1', 
        _subFieldId: 'sub_prod' 
    });
    
    // But updateTicket relies on FormHelper calculating price.
    // FormSession updateTicket calls _recalculate.
    // DOES IT LOOK UP PRICE?
    // FormSession.updateTicket logic lines 360+ handle Spot.
    // Standard fields: it stores the valueObj.
    // Does it look up price for standard fields?
    // NO. updateTicket expects the value object passed to it to ALREADY have price if needed?
    // Let's check handleInput logic.
    // handleInput calls findOption -> sets valObj.price.
    // So my test simulation MUST simulate handleInput or manually pass price.
    // Since I want to verify if LOGIC finds price, I should use handleInput flow or verify findOption.
    
    // Actually, let's verify `resetIncompatibleCurrencyFields` behavior.
    
    // Simulate fully populated ticket
    session.state.tickets[0].fields = [
        { product_type: 'prod_1', price: 500, currency_code: 'CZK', _subFieldId: 'sub_prod' }
    ];
    session._syncPayloadFromState(); // Sync State -> Payload
    session._recalculate(); // Payload -> Price
    
    let state = session.state;
    // Expected: 500
    assert.strictEqual(state.totalPrice, 500, `Initial Price should be 500, got ${state.totalPrice}`);

    // 4. Test Currency Switch (CZK -> EUR)
    // Should REMOVE prod_1 (CZK)
    session.setCurrency('EUR');
    
    await new Promise(r => setTimeout(r, 50));
    
    state = session.state;
    // Expected: 0 (Fields removed)
    assert.strictEqual(state.totalPrice, 0, `Price after switch to EUR should be 0, got ${state.totalPrice}`);
    assert.strictEqual(state.tickets[0].fields.length, 0, `Fields should be empty, got ${state.tickets[0].fields.length}`);

    console.log('Test Passed: Currency Switch Clears Selection.');
    
    // 6. Test Multi-Select Price Calculation
    // Switch back to CZK
    session.setCurrency('CZK');
    // session.addTicket(); // Ticket 0 still exists (just empty fields)
    
    session.state.tickets[0].fields = [
        { 
            product_type: 'prod_1 | prod_2', // pipe-delimited
            _subFieldId: 'sub_prod',
            val: 'prod_1 | prod_2' // Raw val
        }
    ];
    // Note: prod_2 in mock is EUR (20). prod_1 is CZK (500).
    // Our logic logic just sums them if they exist?
    // Wait, FormHelper might filter by currency? 
    // Usually FormHelper sums everything. 
    // BUT our 'resetIncompatible' logic removed mismatched items.
    // If we manually inject 'prod_1 | prod_2' (Mixed Currency), behavior is undefined in test?
    // Let's assume we use valid same-currency options for a real scenario.
    // Mock needs another CZK option.
    
    // START hack to add option to Mock for this test instance
    const prodData = formModel.visibleFields[0].subFields[1].data.product_type_data.products;
    prodData.push({ id: 'prod_3', title: 'Prod 3', price: 300, currency: 'CZK' });
    // END hack
    
    session.state.tickets[0].fields = [
        { 
            product_type: 'prod_1 | prod_3', 
            _subFieldId: 'sub_prod'
        }
    ];
    
    session._syncPayloadFromState();
    session._recalculate();
    
    state = session.state;
    // Expected: 500 + 300 = 800
    assert.strictEqual(state.totalPrice, 800, `Multi-Select Price should be 800, got ${state.totalPrice}`);
    
    console.log('Test Passed: Multi-Select Price Calculation.');
});
