import { test, describe, it, before, beforeEach } from 'node:test';
import assert from 'node:assert';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', { url: 'http://localhost/' });
global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;

const { RadioFieldBuilder } = await import('../../src/components/forms/fields/radio_field_builder.js');
const { CheckBoxFieldBuilder } = await import('../../src/components/forms/fields/check_box_field_builder.js');
const { OptionBuilderHelper } = await import('../../src/components/forms/fields/option_builder_helper.js');

const formModel = {
    relatedFields: [],
    occasionFeatures: [],
    occasionStartTime: null,
};

const makeOption = (title) => ({ title, id: null, price: 0, description: null });

describe('Default values — shouldPreselect', () => {
    it('radio: returns true when default_value matches option title', () => {
        const field = { data: { default_value: 'Option A' } };
        assert.strictEqual(
            OptionBuilderHelper.shouldPreselect(field, makeOption('Option A'), 'radio'),
            true
        );
    });

    it('radio: returns false when default_value does not match option title', () => {
        const field = { data: { default_value: 'Option A' } };
        assert.strictEqual(
            OptionBuilderHelper.shouldPreselect(field, makeOption('Option B'), 'radio'),
            false
        );
    });

    it('radio: returns false when default_value is missing', () => {
        const field = { data: {} };
        assert.strictEqual(
            OptionBuilderHelper.shouldPreselect(field, makeOption('Option A'), 'radio'),
            false
        );
    });

    it('radio: field.value takes precedence over default — returns false', () => {
        const field = { data: { default_value: 'Option A' }, value: 'Option B' };
        assert.strictEqual(
            OptionBuilderHelper.shouldPreselect(field, makeOption('Option A'), 'radio'),
            false
        );
    });

    it('checkbox: returns true when default_value array contains option title', () => {
        const field = { data: { default_value: ['Option A', 'Option C'] } };
        assert.strictEqual(
            OptionBuilderHelper.shouldPreselect(field, makeOption('Option A'), 'checkbox'),
            true
        );
        assert.strictEqual(
            OptionBuilderHelper.shouldPreselect(field, makeOption('Option C'), 'checkbox'),
            true
        );
    });

    it('checkbox: returns false when option title is not in default_value array', () => {
        const field = { data: { default_value: ['Option A'] } };
        assert.strictEqual(
            OptionBuilderHelper.shouldPreselect(field, makeOption('Option B'), 'checkbox'),
            false
        );
    });

    it('checkbox: returns false when default_value is a non-array (radio default applied to checkbox field)', () => {
        const field = { data: { default_value: 'Option A' } };
        assert.strictEqual(
            OptionBuilderHelper.shouldPreselect(field, makeOption('Option A'), 'checkbox'),
            false
        );
    });
});

describe('Default values — RadioFieldBuilder.create', () => {
    it('pre-selects radio matching default_value', () => {
        const field = {
            id: 'fld1',
            type: 'select_one',
            title: 'Choose',
            options: [makeOption('Yes'), makeOption('No'), makeOption('Maybe')],
            data: { default_value: 'No' },
        };
        const el = RadioFieldBuilder.create(field, formModel);
        const inputs = el.querySelectorAll('input[type=radio]');
        const checked = Array.from(inputs).filter(i => i.checked).map(i => i.value);
        assert.deepStrictEqual(checked, ['No']);
    });

    it('does not pre-select anything when default points to deleted option', () => {
        const field = {
            id: 'fld2',
            type: 'select_one',
            title: 'Choose',
            options: [makeOption('Yes'), makeOption('No')],
            data: { default_value: 'Deleted Option' },
        };
        const el = RadioFieldBuilder.create(field, formModel);
        const checkedCount = el.querySelectorAll('input[type=radio]:checked').length;
        assert.strictEqual(checkedCount, 0);
    });

    it('does not pre-select anything when no default is set', () => {
        const field = {
            id: 'fld3',
            type: 'select_one',
            title: 'Choose',
            options: [makeOption('Yes'), makeOption('No')],
            data: {},
        };
        const el = RadioFieldBuilder.create(field, formModel);
        const checkedCount = el.querySelectorAll('input[type=radio]:checked').length;
        assert.strictEqual(checkedCount, 0);
    });

    it('field.value (existing answer) overrides default', () => {
        const field = {
            id: 'fld4',
            type: 'select_one',
            title: 'Choose',
            options: [makeOption('Yes'), makeOption('No')],
            data: { default_value: 'Yes' },
            value: 'No',
        };
        const el = RadioFieldBuilder.create(field, formModel);
        const checked = Array.from(el.querySelectorAll('input[type=radio]'))
            .filter(i => i.checked).map(i => i.value);
        assert.deepStrictEqual(checked, ['No']);
    });
});

describe('Default values — CheckBoxFieldBuilder.create', () => {
    it('pre-checks all options matching default_value array', () => {
        const field = {
            id: 'fld5',
            type: 'select_many',
            title: 'Pick many',
            options: [makeOption('A'), makeOption('B'), makeOption('C')],
            data: { default_value: ['A', 'C'] },
        };
        const el = CheckBoxFieldBuilder.create(field, formModel);
        const checked = Array.from(el.querySelectorAll('input[type=checkbox]'))
            .filter(i => i.checked).map(i => i.value);
        assert.deepStrictEqual(checked.sort(), ['A', 'C']);
    });

    it('ignores defaults that refer to deleted options', () => {
        const field = {
            id: 'fld6',
            type: 'select_many',
            title: 'Pick many',
            options: [makeOption('A'), makeOption('B')],
            data: { default_value: ['A', 'Deleted'] },
        };
        const el = CheckBoxFieldBuilder.create(field, formModel);
        const checked = Array.from(el.querySelectorAll('input[type=checkbox]'))
            .filter(i => i.checked).map(i => i.value);
        assert.deepStrictEqual(checked, ['A']);
    });

    it('pre-checks nothing when no default is set', () => {
        const field = {
            id: 'fld7',
            type: 'select_many',
            title: 'Pick many',
            options: [makeOption('A'), makeOption('B')],
            data: {},
        };
        const el = CheckBoxFieldBuilder.create(field, formModel);
        const checkedCount = el.querySelectorAll('input[type=checkbox]:checked').length;
        assert.strictEqual(checkedCount, 0);
    });
});
