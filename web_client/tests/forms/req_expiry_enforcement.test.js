
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { JSDOM } from 'jsdom';

// Global DOM setup
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
    url: 'http://localhost'
});
global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;
global.FormData = dom.window.FormData;
global.NodeList = dom.window.NodeList;
dom.window.Event = global.Event;
dom.window.CustomEvent = global.CustomEvent;
global.Node = dom.window.Node;
dom.window.HTMLElement.prototype.scrollIntoView = () => {};

// Imports
import { FormSession } from '../../src/components/forms/form_session.js';
import { FormValidator } from '../../src/components/forms/form_validator.js';
import { IdDocumentFieldBuilder } from '../../src/components/forms/fields/id_document_field_builder.js';
import { IdDocumentConstants } from '../../src/components/forms/constants/id_document_constants.js';

describe('ID Document Expiry Requirement', () => {
    let session;
    let formModel;
    let formElement;
    let fieldDef;

    beforeEach(() => {
        document.body.innerHTML = '<div id="container"><form id="test-form"></form></div>';
        formElement = document.getElementById('test-form');

        // Mock Model: Required Field, Expiry Shown
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

        const fieldEl = IdDocumentFieldBuilder.create(fieldDef, formModel);
        formElement.appendChild(fieldEl);
        
        session = new FormSession(formModel);
        session.initialize(formElement);
    });

    it('should be invalid when ID is filled but Expiry is missing (if field is Required)', () => {
        // 1. Fill ID Number Only
        const inputId = formElement.querySelector(`input[name="583"]`);
        inputId.value = 'DOC123';
        session.handleInput({ target: inputId }, formElement);

        // 2. Validate
        // Expectation: Should be FALSE because Expiry is required implicitly when field is required + shown
        const isValid = FormValidator.validateAndShowErrors(formElement, formModel, session);
        
        assert.strictEqual(isValid, false, 'Validator should return FALSE when Expiry is missing on start');
        
        // 3. Verify Error
        const expiryInputName = `583${IdDocumentConstants.EXPIRY_SUFFIX}`;
        assert.ok(session.state.validationErrors[expiryInputName], 'Validation error should exist for expiry field');
    });
});
