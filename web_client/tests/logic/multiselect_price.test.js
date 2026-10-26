
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import { JSDOM, VirtualConsole } from 'jsdom';

describe('Multiselect Price Logic', () => {
    let TicketFieldBuilder;
    let FormSession;
    let FormHelper;
    let session;
    let mockFormModel;
    let dom;

    before(async () => {
        const virtualConsole = new VirtualConsole();
        virtualConsole.on("log", (message) => console.log("JSDOM log:", message)); 
        virtualConsole.on("error", (message) => console.error("JSDOM error:", message));
        
        dom = new JSDOM('<!DOCTYPE html><html><body><form id="test-form"></form></body></html>', {
            url: 'http://localhost/',
            virtualConsole
        });
        global.document = dom.window.document;
        global.window = dom.window;
        global.HTMLElement = dom.window.HTMLElement;
        global.Event = dom.window.Event;
        global.NodeList = dom.window.NodeList;
        global.HTMLCollection = dom.window.HTMLCollection;
        global.document.createRange = () => ({
            setStart: () => {},
            setEnd: () => {},
            commonAncestorContainer: {
                nodeName: 'BODY',
                ownerDocument: document,
            },
        });

        const sessionModule = await import('../../src/components/forms/form_session.js');
        FormSession = sessionModule.FormSession;
        
        const builderModule = await import('../../src/components/forms/fields/ticket_field_builder.js');
        TicketFieldBuilder = builderModule.TicketFieldBuilder;
        
        const helperModule = await import('../../src/components/forms/form_helper.js');
        FormHelper = helperModule.FormHelper;
    });

    after(() => {
        if (global.window) global.window.close();
    });

    it('should calculate TOTAL price for multiselect product fields', async (t) => {
         const ticketFieldDef = {
             id: 'ticket',
             type: 'ticket',
             subFields: [
                 { 
                     id: 'sub_prod', 
                     type: 'product_type', 
                     title: ' Extras',
                     data: {
                         selection_type: 'select_many',
                         product_type_data: {
                             products: [
                                 { id: '101', title: 'Extra A', price: 100, currency: 'CZK' },
                                 { id: '102', title: 'Extra B', price: 50, currency: 'CZK' },
                                 { id: '103', title: 'Extra C', price: 200, currency: 'CZK' }
                             ]
                         }
                     }
                 }
             ]
         };
         
         mockFormModel = {
            fields: [ticketFieldDef],
            visibleFields: [ticketFieldDef], 
            relatedFields: [ { id: 'ticket', type: 'ticket', data: { max_tickets: 5, fields: ticketFieldDef.subFields } } ], 
            blueprint: false,
            currencyCode: 'CZK'
         };
         
         session = new FormSession(mockFormModel);
         const form = document.getElementById('test-form');
         const container = TicketFieldBuilder.create(ticketFieldDef, mockFormModel, session);
         form.appendChild(container);
         
         session.addTicket(); // Ticket 1

         // Find Inputs
         const checkboxes = container.querySelectorAll('input[type="checkbox"]');
         // Ticket 1 (index 0) inputs. Ticket 0 might exist from initial create?
         // Check session count
         console.log('DEBUG: Session tickets count:', session.state.tickets.length);
         console.log('DEBUG: Checkboxes found:', checkboxes.length);
         Array.from(checkboxes).forEach((c, i) => console.log(`DEBUG: Checkbox ${i} val=${c.value} name=${c.name}`));
         
         const cbA = Array.from(checkboxes).find(c => c.value === '101');
         const cbB = Array.from(checkboxes).find(c => c.value === '102');
         const cbC = Array.from(checkboxes).find(c => c.value === '103');
         
         assert.ok(cbA && cbB && cbC, 'All product checkboxes found');
         
         // 1. Select A (100)
         cbA.checked = true;
         console.log('DEBUG: vbA.name =', cbA.name);
         try {
             session.handleInput({ target: cbA, type: 'input', bubbles: true }, form);
         } catch (e) {
             console.error('DEBUG: CRASH in handleInput:', e);
         }
         
         let ticket = session.state.tickets[0]; // Assuming index 0 is our ticket
         // Or find ticket by fields?
         console.log('DEBUG 1: Ticket 0 Fields:', JSON.stringify(ticket.fields, null, 2));
         
         let fieldEntry = ticket.fields.find(f => f._subFieldId === 'sub_prod');
         assert.ok(fieldEntry, 'Field entry should exist');
         assert.strictEqual(String(fieldEntry.product_type), '101', 'Value should be 101');
         assert.strictEqual(fieldEntry.price, 100, 'Price should be 100');
         
         // 2. Select B (50) -> Total 150
         cbB.checked = true;
         session.handleInput({ target: cbB, type: 'input', bubbles: true }, form);
         
         ticket = session.state.tickets[0];
         console.log('DEBUG 2: Ticket 0 Fields:', JSON.stringify(ticket.fields, null, 2));
         
         fieldEntry = ticket.fields.find(f => f._subFieldId === 'sub_prod');
         assert.strictEqual(fieldEntry.product_type, '101 | 102', 'Value should be pipe separated');
         assert.strictEqual(fieldEntry.price, 150, 'Price should be summed (100+50)');
         
         // 3. Select C (200) -> Total 350
         cbC.checked = true;
         session.handleInput({ target: cbC, type: 'input' }, form);
         
         ticket = session.state.tickets[0];
         console.log('DEBUG 3: Ticket 0 Fields:', JSON.stringify(ticket.fields, null, 2));
         
         fieldEntry = ticket.fields.find(f => f._subFieldId === 'sub_prod');
         assert.strictEqual(fieldEntry.price, 350, 'Price should be summed (100+50+200)');
         
         // 4. Uncheck B -> Total 300
         cbB.checked = false;
         session.handleInput({ target: cbB, type: 'input' }, form);
         
         ticket = session.state.tickets[0];
         console.log('DEBUG 4: Ticket 0 Fields:', JSON.stringify(ticket.fields, null, 2));

         const finalEntry = ticket.fields.find(f => f._subFieldId === 'sub_prod');
         assert.strictEqual(finalEntry.price, 300, 'Price should be summed (100+200)');
    });
});
