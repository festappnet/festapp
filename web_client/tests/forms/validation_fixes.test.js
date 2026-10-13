
import { test, describe, it, before, beforeEach } from 'node:test';
import assert from 'node:assert';
import { FormSession } from '../../src/components/forms/form_session.js';
import { FormValidator } from '../../src/components/forms/form_validator.js';
import { JSDOM } from 'jsdom';

// Setup global JSDOM for form emulation
const dom = new JSDOM('<!DOCTYPE html><html><body><form id="test-form"></form></body></html>', {
    url: 'http://localhost/',
});
global.window = dom.window;
global.document = dom.window.document;
global.FormData = dom.window.FormData;
global.HTMLElement = dom.window.HTMLElement;

describe('Fixes Validation', () => {
    let session;
    let mockFormModel;

    beforeEach(() => {
        document.body.innerHTML = '<form id="test-form"></form>';
        
        mockFormModel = {
            key: 'test_form',
            secret: 'test_secret',
            visibleFields: [
                { 
                    id: '99', 
                    type: 'ticket', 
                    subFields: [
                        { id: 'sub_text', type: 'text' },
                        { id: 'sub_check', type: 'checkbox', options: [{id: 'A'}, {id: 'B'}], maxOptions: 2 }
                    ]
                }
            ],
            relatedFields: []
        };

        session = new FormSession(mockFormModel);
        session.addTicket(); // Ensure ticket 0 exists
    });

    it('SHOULD NOT split text input containing pipes (Pipe Vulnerability Fix)', () => {
        const form = document.getElementById('test-form');
        
        // 1. Simulate Text Input with Pipe
        const input = document.createElement('input');
        input.name = '99_0_sub_text'; // ticketId_index_subId
        input.value = 'Malicious | Value';
        input.type = 'text';
        input.dataset.subId = 'sub_text';
        input.dataset.ticketId = '99';
        input.dataset.index = '0';
        form.appendChild(input);

        // Simulate Event
        const event = { target: input, type: 'input' };
        session.handleInput(event, form);

        // Verify Payload
        const tObj = session.payload.ticket[0];
        // Should have exactly 1 field entry for this text
        const textEntries = tObj.fields.filter(f => f.text !== undefined);
        assert.strictEqual(textEntries.length, 1, 'Should have exactly 1 text entry');
        assert.strictEqual(textEntries[0].text, 'Malicious | Value', 'Should preserve pipe in text');
    });

    it('SHOULD split checkbox input containing pipes (Normal Behavior)', () => {
        const form = document.getElementById('test-form');

        // 1. Simulate Checkbox Input (simulating aggregated value or sequential input?)
        // FormSession.handleInput for checkbox usually takes single value and toggles it in state?
        // Let's check FormSession.handleInput implementation effectively.
        // If handleInput manages the pipe logic for checkbox, we rely on that.
        // Actually, FormSession.handleInput logic for checkbox appends/removes values and joins with ' | '.
        // So internal state WILL have 'A | B'.
        // SyncPayloadFromState should SPLIT it.

        // Let's modify state directly to simulate "A | B" being stored (which is valid for checkbox)
        const ticket = session.state.tickets[0];
        ticket.fields = [{ _subFieldId: 'sub_check', checkbox: 'A | B' }];
        
        // Force Sync
        session._syncPayloadFromState();

        // Verify Payload
        const tObj = session.payload.ticket[0];
        const checkEntries = tObj.fields.filter(f => f.checkbox !== undefined); // OR check expanded
        // SyncPayloadFromState expands 'A | B' into two entries {checkbox: 'A'}, {checkbox: 'B'}
        
        assert.strictEqual(checkEntries.length, 2, 'Should expand multi-select values');
        const values = checkEntries.map(e => e.checkbox).sort();
        assert.deepStrictEqual(values, ['A', 'B']);
    });

    it('SHOULD validate Max Options for checkbox', () => {
        // Setup Session Payload with violation (3 options selected, max is 2)
        const ticket = session.state.tickets[0];
        ticket.fields = [{ _subFieldId: 'sub_check', checkbox: 'A | B | C' }];
        session._syncPayloadFromState();

        const form = document.getElementById('test-form');
        // Validate
        const isValid = FormValidator.validateAndShowErrors(form, mockFormModel, session);
        
        assert.strictEqual(isValid, false, 'Should be invalid due to max options');
        
        const errors = session.state.validationErrors;
        // Error key format: 99_0_sub_check
        const errKey = '99_0_sub_check';
        assert.ok(errors[errKey], 'Should have error for the field');
        assert.match(errors[errKey], /Maximum options: 2/, 'Error message should mention limit');
    });
    
    it('SHOULD pass Max Options validation when within limit', () => {
        // Setup Session Payload with valid (2 options)
        const ticket = session.state.tickets[0];
        ticket.fields = [{ _subFieldId: 'sub_check', checkbox: 'A | B' }];
        session._syncPayloadFromState();

        const form = document.getElementById('test-form');
        const isValid = FormValidator.validateAndShowErrors(form, mockFormModel, session);
        
        assert.strictEqual(isValid, true, 'Should be valid');
        const errors = session.state.validationErrors;
        assert.strictEqual(Object.keys(errors).length, 0);
    });
});


test('multi-choice validation counts a stable answer once and isolates same-type field IDs', () => {
    const ticket = {fields: [
        {107: 'A | B', select_many: 'A | B', _subFieldId: 107},
        {108: ['C', 'D'], select_many: ['C', 'D'], _subFieldId: 108},
    ]};
    assert.deepStrictEqual(FormValidator.getTicketFieldValues(ticket, {id: 107, type: 'select_many'}), ['A', 'B']);
    assert.deepStrictEqual(FormValidator.getTicketFieldValues(ticket, {id: 108, type: 'select_many'}), ['C', 'D']);
    assert.deepStrictEqual(FormValidator.getTicketFieldValues({fields: [{107: []}]}, {id: 107, type: 'select_many'}), []);
});
