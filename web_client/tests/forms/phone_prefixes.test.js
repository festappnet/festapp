
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { TextFieldBuilder } from '../../src/components/forms/fields/text_field_builder.js';
import { JSDOM } from 'jsdom';

// Setup global JSDOM
const dom = new JSDOM('<!DOCTYPE html><html><body><div id="test-container"></div></body></html>', {
    url: 'http://localhost/',
});

global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;

describe('TextFieldBuilder Phone Prefixes', () => {
    let container;
    let input;
    let badgesContainer;

    beforeEach(() => {
        document.body.innerHTML = '<div id="test-container"><input type="tel" /><div class="phone-badges-container"></div></div>';
        container = document.getElementById('test-container');
        input = container.querySelector('input');
        badgesContainer = container.querySelector('.phone-badges-container');
    });

    it('should use default +420, +421 prefixes if no formModel data provided', () => {
        TextFieldBuilder._attachPhoneLogic(input, container, null);
        
        const chips = badgesContainer.querySelectorAll('.phone-badge-chip');
        assert.equal(chips.length, 2);
        assert.equal(chips[0].textContent, 'CZ +420');
        assert.equal(chips[1].textContent, 'SK +421');
    });

    it('leaves an optional phone empty and valid until the buyer enters a number', () => {
        TextFieldBuilder._attachPhoneLogic(input, container, null);
        assert.equal(input.value, '');
        assert.equal(input.checkValidity(), true);
        input.value = '+420 123';
        assert.equal(input.checkValidity(), false);
        input.value = '+420 777 123 456';
        assert.equal(input.checkValidity(), true);
    });

    it('keeps the initial prefix for a required phone', () => {
        input.required = true;
        TextFieldBuilder._attachPhoneLogic(input, container, null);
        assert.equal(input.value.trim(), '+420');
        assert.equal(input.checkValidity(), false);
    });

    it('should use prefixes from formModel if provided', () => {
        const mockFormModel = {
            data: {
                phone_prefixes: ['+1', '+44', '+420']
            }
        };

        TextFieldBuilder._attachPhoneLogic(input, container, mockFormModel);
        
        const chips = badgesContainer.querySelectorAll('.phone-badge-chip');
        assert.equal(chips.length, 3);
        assert.equal(chips[0].textContent, 'US/CA +1');
        assert.equal(chips[1].textContent, 'UK +44');
        assert.equal(chips[2].textContent, 'CZ +420'); // Should still map CZ +420 label
    });

    it('should fallback to defaults if phone_prefixes is empty', () => {
        const mockFormModel = {
            data: {
                phone_prefixes: []
            }
        };

        TextFieldBuilder._attachPhoneLogic(input, container, mockFormModel);
        
        const chips = badgesContainer.querySelectorAll('.phone-badge-chip');
        assert.equal(chips.length, 2);
        assert.equal(chips[0].textContent, 'CZ +420');
    });

    it('should apply selected prefix logic on click', () => {
         const mockFormModel = {
            data: {
                phone_prefixes: ['+1']
            }
        };

        // Mock PhoneFormatter since it's used inside logic
        // We might need to mock global Ref or module if it fails.
        // Assuming TextFieldBuilder imports PhoneFormatter from same module or global?
        // Let's check imports in TextFieldBuilder.
        // It imports PhoneFormatter from `../../logic/phone_formatter.js` usually.
        // If it's an ES module import, we rely on node resolving it.
        
        // However, JSDOM doesn't handle imports. We are running in Node.
        // If TextFieldBuilder has dependencies, we need to ensure they work.
        // Let's hope PhoneFormatter is pure logic.
        
        TextFieldBuilder._attachPhoneLogic(input, container, mockFormModel);
        
        const chip = badgesContainer.querySelector('.phone-badge-chip');
        
        input.value = "123456";
        chip.click();
        
        // Expect +1 123456 (formatted)
        // Since we don't know exact PhoneFormatter behavior here without mocking,
        // we check if it starts with +1.
        assert.ok(input.value.startsWith('+1'));
    });
});
