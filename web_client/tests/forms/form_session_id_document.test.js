
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { FormSession } from '../../src/components/forms/form_session.js';
import { JSDOM } from 'jsdom';

// Global DOM setup for FormSession
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;

describe('FormSession - ID Document Support', () => {
    let session;
    let mockFormModel;
    let formElement;

    beforeEach(() => {
        mockFormModel = {
            key: 'test_form',
            secret: 'test_secret',
            visibleFields: [
                { id: '583', type: 'id_document', title: 'ID Document' }
            ],
            relatedFields: [
                { id: '583', type: 'id_document' }
            ],
            isCardDesign: false
        };
        session = new FormSession(mockFormModel);
        
        document.body.innerHTML = '<form id="test-form"></form>';
        formElement = document.getElementById('test-form');
    });

    it('should initialize with empty state', () => {
        assert.strictEqual(session.state.fields.get('583'), undefined);
    });

    it('should handle ID Number input and create nested object', () => {
        const input = document.createElement('input');
        input.name = '583';
        input.value = '12345';
        
        session.handleInput({ target: input }, formElement);
        
        const val = session.state.fields.get('583');
        assert.deepStrictEqual(val, { id_document_number: '12345' });
    });

    it('should handle Expiry input and merge into existing object', () => {
        // 1. Set Number first
        const idInput = document.createElement('input');
        idInput.name = '583';
        idInput.value = '12345';
        session.handleInput({ target: idInput }, formElement);

        // 2. Set Expiry
        const expiryInput = document.createElement('input');
        expiryInput.name = '583_expiry';
        expiryInput.value = '2028-01-01'; // Raw value from date picker
        
        session.handleInput({ target: expiryInput }, formElement);
        
        const val = session.state.fields.get('583');
        assert.deepStrictEqual(val, { 
            id_document_number: '12345',
            id_document_expiry_date: '2028-01-01'
        });
    });

    it('should handle Expiry input even if ID Number is not yet set (Object Init)', () => {
        const expiryInput = document.createElement('input');
        expiryInput.name = '583_expiry';
        expiryInput.value = '2028-01-01';
        
        session.handleInput({ target: expiryInput }, formElement);
        
        const val = session.state.fields.get('583');
        // valid nested object with empty number
        assert.deepStrictEqual(val, { 
            id_document_number: '',
            id_document_expiry_date: '2028-01-01'
        });
    });

    it('should sync nested object to payload correctly', () => {
        // FormSession.payload.fields should contain the nested object directly
        // because _syncPayloadFromState logic for standard fields just pushes key: value.
        // However, we need to check if _syncPayloadFromState needs adjustment?
        
        // Let's check logic:
        // for (const [fieldId, value] of this.state.fields.entries()) { ... const entry = { [fieldId]: value }; ... }
        // Yes, if value is object, it pushes { '583': { ... } }
        
        const idInput = document.createElement('input');
        idInput.name = '583';
        idInput.value = '999';
        session.handleInput({ target: idInput }, formElement);
        
        const payloadFields = session.payload.fields;
        const entry = payloadFields.find(f => f['583']);
        
        assert.ok(entry);
        assert.deepStrictEqual(entry['583'], { id_document_number: '999' });
    });
});
