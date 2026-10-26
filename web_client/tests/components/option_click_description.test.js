import { describe, it } from 'node:test';
import assert from 'node:assert';
import { JSDOM } from 'jsdom';
import { FormStrings } from '../../src/components/forms/form_strings.js';

const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
global.document = dom.window.document;
global.window = dom.window;
global.HTMLElement = dom.window.HTMLElement;
global.Event = dom.window.Event;

// Mock FormStrings
try {
    Object.defineProperty(FormStrings, 'clearSelection', {
        get: () => 'Clear',
        configurable: true
    });
    Object.defineProperty(FormStrings, 'surchargeOnSite', {
        get: () => 'doplatek',
        configurable: true
    });
} catch(e) {
    console.error('Failed to mock FormStrings', e);
}

// Import builders after DOM is set up
const { RadioFieldBuilder } = await import('../../src/components/forms/fields/radio_field_builder.js');
const { CheckBoxFieldBuilder } = await import('../../src/components/forms/fields/check_box_field_builder.js');

function makeField(id, options) {
    return {
        id,
        type: 'select',
        title: 'Test',
        isRequired: false,
        options,
    };
}

const basicOptions = [
    { id: 'a', title: 'Option A', description: 'Desc A' },
    { id: 'b', title: 'Option B', description: 'Desc B' },
];

describe('Option description click selects input', () => {
    it('Radio basic mode — click .option-description checks input', () => {
        const field = makeField('r1', basicOptions);
        const container = RadioFieldBuilder.create(field, {});
        document.body.appendChild(container);

        const desc = container.querySelector('.option-description');
        const input = container.querySelector('input[type="radio"]');

        assert.ok(desc, '.option-description should exist');
        assert.ok(!input.checked, 'input should start unchecked');

        desc.click();

        assert.ok(input.checked, 'input should be checked after clicking description');
        document.body.removeChild(container);
    });

    it('Checkbox basic mode — click .option-description checks input', () => {
        const field = makeField('c1', basicOptions);
        const container = CheckBoxFieldBuilder.create(field, {});
        document.body.appendChild(container);

        const desc = container.querySelector('.option-description');
        const input = container.querySelector('input[type="checkbox"]');

        assert.ok(desc, '.option-description should exist');
        assert.ok(!input.checked, 'input should start unchecked');

        desc.click();

        assert.ok(input.checked, 'input should be checked after clicking description');
        document.body.removeChild(container);
    });

    it('Radio card mode — click .option-description checks input', () => {
        const field = makeField('r2', basicOptions);
        const container = RadioFieldBuilder.create(field, { isCardDesign: true });
        document.body.appendChild(container);

        const wrapper = container.querySelector('.form-check');
        assert.ok(wrapper.classList.contains('option-card'), 'should have option-card class');

        const desc = container.querySelector('.option-description');
        const input = container.querySelector('input[type="radio"]');

        desc.click();

        assert.ok(input.checked, 'input should be checked after clicking description in card mode');
        document.body.removeChild(container);
    });

    it('Checkbox card mode — click .option-description checks input', () => {
        const field = makeField('c2', basicOptions);
        const container = CheckBoxFieldBuilder.create(field, { isCardDesign: true });
        document.body.appendChild(container);

        const wrapper = container.querySelector('.form-check');
        assert.ok(wrapper.classList.contains('option-card'), 'should have option-card class');

        const desc = container.querySelector('.option-description');
        const input = container.querySelector('input[type="checkbox"]');

        desc.click();

        assert.ok(input.checked, 'input should be checked after clicking description in card mode');
        document.body.removeChild(container);
    });
});
