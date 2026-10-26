
import { test, describe, it, before, beforeEach, after } from 'node:test';
import assert from 'node:assert';
import { FormSession } from '../../src/components/forms/form_session.js';
import { DbForms } from '../../src/components/forms/db_forms.js';
import { JSDOM } from 'jsdom';

// Setup global JSDOM
const dom = new JSDOM('<!DOCTYPE html><html><body><form id="test-form"></form></body></html>', {
    url: 'http://localhost/',
});
global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;
global.FormData = dom.window.FormData;

// Mock DbForms.selectSpot to prevent network calls
DbForms.selectSpot = async (formKey, secret, spotId, selecting) => {
    // Return mock success
    return { status: 'mocked', spot_id: spotId };
};

describe('FormSession State Inversion', () => {
    let session;
    let mockFormModel;

    after(() => {
        if (global.window) global.window.close();
    });

    beforeEach(() => {
        document.body.innerHTML = '<form id="test-form"></form>';
        
        mockFormModel = {
            key: 'test_form',
            secret: 'test_secret',
            visibleFields: [
                { 
                    id: 'ticket_1', 
                    type: 'ticket', 
                    subFields: [
                        { id: 'sub_spot', type: 'spot', isRequired: true, options: [] },
                        { id: 'sub_prod', type: 'product_type', options: [{id: 'prod_1', price: 50}] } 
                    ]
                }
            ],
            relatedFields: [
                { type: 'ticket', data: { max_tickets: 10 } }
            ]
        };

        session = new FormSession(mockFormModel);
    });

    it('should sync payload immediately when adding a ticket via state', () => {
        // structural sync check
        assert.strictEqual(session.payload.ticket.length, 0);

        session.addTicket({
            spot: 101, // ID
            spotPrice: 200
        });

        assert.strictEqual(session.payload.ticket.length, 1);
        assert.strictEqual(session.payload.ticket[0].spot, 101);
        assert.strictEqual(session.payload.ticket[0].spotPrice, 200);
        
        // Check Price immediately
        assert.strictEqual(session.state.totalPrice, 250); // Spot 200 + Prod 50
        assert.strictEqual(session.state.totalItems, 1);
    });

    it('should sync payload immediately when removing a ticket via state', async () => {
        session.addTicket({ spot: 101, spotPrice: 200 });
        session.addTicket({ spot: 102, spotPrice: 300 });

        assert.strictEqual(session.payload.ticket.length, 2);
        assert.strictEqual(session.state.totalPrice, 600); // (200+50) + (300+50)

        // Remove first one
        await session.removeTicket(0);

        assert.strictEqual(session.payload.ticket.length, 1);
        assert.strictEqual(session.payload.ticket[0].spot, 102); // Remaining should be 102
        
        // Check Price immediately
        assert.strictEqual(session.state.totalPrice, 350); // 300+50
    });

    it('should update ticket fields via updateTicket', () => {
        session.addTicket(); // Empty ticket

        // Update sub_prod
        const valueObj = { product_type: 'prod_1', _subFieldId: 'sub_prod', price: 50 };
        session.updateTicket(0, 'sub_prod', valueObj);

        assert.strictEqual(session.payload.ticket[0].fields.length, 1);
        assert.strictEqual(session.payload.ticket[0].fields[0].product_type, 'prod_1');
        
        // Check Price (assuming update doesn't clear spotPrice if it was just fields)
        // With product price 50
        assert.strictEqual(session.state.totalPrice, 50);
    });
    
    it('should handle State Inversion correctly (DOM reflection)', () => {
        // This test verifies that we don't need DOM scraping for basic operations anymore
        // We simulate "Add Ticket" purely via State.
        
        session.addTicket();
        assert.strictEqual(session.payload.ticket.length, 1);
        
        // Even if DOM is empty (as it is now), payload is correct.
        const form = document.getElementById('test-form');
        assert.strictEqual(form.innerHTML, ''); // Empty DOM
        
        // Since we ignore the DOM, refreshPayload should respect the State as the source of truth.
        
        session.refreshPayload(form);
        assert.strictEqual(session.payload.ticket.length, 1, "Refresh should respect State for tickets");
    });
});
