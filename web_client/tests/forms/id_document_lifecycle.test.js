
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { JSDOM } from 'jsdom';

// Global DOM setup must happen before imports that use document/window
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
    url: 'http://localhost'
});
global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;
global.FormData = dom.window.FormData;
global.NodeList = dom.window.NodeList;
// Use Node's native Event/CustomEvent for compatibility with EventTarget
// But expose them to JSDOM window so libraries find them
dom.window.Event = global.Event;
dom.window.CustomEvent = global.CustomEvent;
global.Node = dom.window.Node; // Required for flatpickr
dom.window.HTMLElement.prototype.scrollIntoView = () => {}; // Mock for FormValidator

// Imports
import { FormSession } from '../../src/components/forms/form_session.js';
import { FormValidator } from '../../src/components/forms/form_validator.js';
import { IdDocumentFieldBuilder } from '../../src/components/forms/fields/id_document_field_builder.js';
import { FieldPreviewFactory } from '../../src/components/forms/previews/field_preview_factory.js';
import { IdDocumentConstants } from '../../src/components/forms/constants/id_document_constants.js';
import { FormStrings } from '../../src/components/forms/form_strings.js';

describe('ID Document Field - Full Lifecycle', () => {
    let session;
    let formModel;
    let formElement;
    let fieldDef;

    beforeEach(() => {
        // Clear DOM
        document.body.innerHTML = '<div id="container"><form id="test-form"></form></div>';
        formElement = document.getElementById('test-form');
        const container = document.getElementById('container');

        // Mock Model
        fieldDef = { 
            id: '583', 
            type: 'id_document', 
            title: 'Passport', 
            isRequired: true,
            showExpiryDate: true 
        };
        
        formModel = {
            key: 'test_form',
            secret: 'test_secret',
            visibleFields: [ fieldDef ],
            relatedFields: [ fieldDef ],
            isCardDesign: false
        };

        // 1. RENDER
        const fieldEl = IdDocumentFieldBuilder.create(fieldDef, formModel);
        formElement.appendChild(fieldEl);
        
        // Init Session
        session = new FormSession(formModel);
        session.initialize(formElement);
    });

    it('should validate, handle input, update state, and preview correctly', () => {
        // --- A. VALIDATION (Empty) ---
        // Native requires are set by Builder, so browser validity would catch it.
        // FormValidator checks native validity OR data-required.
        // JSDOM handles 'required' attribute presence but full checkValidity() logic might vary.
        
        const isValidEmpty = FormValidator.validateAndShowErrors(formElement, formModel, session);
        assert.strictEqual(isValidEmpty, false, 'Should be invalid when empty (Required)');
        
        // Verify Error Display
        const errorDiv = formElement.querySelector('.form-field-error');
        // Note: FormValidator might show error on first invalid field it finds?
        // or FormValidator.renderErrors handling?
        // validateAndShowErrors calculates errors and sets them in session, AND renders them via immediate DOM manip.
        
        // Check session errors
        assert.ok(session.state.validationErrors['583'] || session.state.validationErrors['583_expiry'], 'Error should be in session state');

        // --- B. INPUT HANDLING ---
        const inputId = formElement.querySelector(`input[name="583"]`);
        const inputExpiry = formElement.querySelector(`input[name="583${IdDocumentConstants.EXPIRY_SUFFIX}"]`);
        
        assert.ok(inputId, 'ID Input rendered');
        assert.ok(inputExpiry, 'Expiry Input rendered');

        // Simulate Typing ID
        inputId.value = 'AB123456';
        session.handleInput({ target: inputId }, formElement);

        // Check State (Intermediate)
        const state1 = session.state.fields.get('583');
        assert.deepStrictEqual(state1, { id_document_number: 'AB123456' }, 'State should have ID Number');
        
        // Validation Should still fail? 
        // Validation should fail. Currently IdDocumentFieldBuilder only sets required on ID INPUT. 
        // So checking Validator now might pass if ID is filled.
        
        const isValidPartial = FormValidator.validateAndShowErrors(formElement, formModel, session);
        // UPDATED REQUIREMENT: If ID is required + showExpiry, then Expiry is ALSO required.
        assert.strictEqual(isValidPartial, false, 'Should be INVALID if ID Number is filled but Expiry is missing (Strict Requirement)');
        assert.ok(session.state.validationErrors['583_expiry'], 'Should have expiry error');

        // Simulate Typing Expiry
        inputExpiry.value = '2030-01-01';
        session.handleInput({ target: inputExpiry }, formElement);

        // --- C. STATE CHECK ---
        const finalState = session.state.fields.get('583');
        assert.deepStrictEqual(finalState, { 
            id_document_number: 'AB123456',
            id_document_expiry_date: '2030-01-01'
        }, 'Final state should have both values nested');

        // --- D. PREVIEW CHECK ---
        const previewText = FieldPreviewFactory.format(fieldDef, finalState, {});
        // LocalizationService defaults to EN/CS, formatting depends on it. 
        // Expectation: "AB123456 (..."
        assert.ok(previewText.value.includes('AB123456'), `Preview must contain ID, got: ${previewText.value}`);
        assert.ok(previewText.value.includes('2030'), `Preview must contain Year, got: ${previewText.value}`);

        // --- E. PAYLOAD CHECK ---
        const payloadFields = session.payload.fields;
        const entry = payloadFields.find(f => f['583']);
        assert.deepStrictEqual(entry['583'], finalState, 'Payload should match state');
    });
});
