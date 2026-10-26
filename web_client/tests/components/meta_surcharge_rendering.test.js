import { describe, it } from 'node:test';
import assert from 'node:assert';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', { url: 'http://localhost/' });
global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;

const { OptionBuilderHelper } = await import('../../src/components/forms/fields/option_builder_helper.js');
const { RadioFieldBuilder } = await import('../../src/components/forms/fields/radio_field_builder.js');
const { CheckBoxFieldBuilder } = await import('../../src/components/forms/fields/check_box_field_builder.js');

const depositEnabledFeatures = [{ code: 'deposit', is_enabled: true, deposit_mode: 'virtual', data: {}, meta_surcharge_description: null }];
const depositDisabledFeatures = [{ code: 'deposit', is_enabled: false }];

const makeFormModel = (features, depositDesc) => {
    const f = features.map(x => ({ ...x }));
    if (depositDesc !== undefined && f.length > 0) f[0].meta_surcharge_description = depositDesc;
    return {
        relatedFields: [],
        occasionFeatures: f,
        occasionStartTime: null,
    };
};

const productOption = (overrides = {}) => ({
    title: 'Ticket A',
    id: 1,
    price: 1000,
    currencyCode: 'CZK',
    description: null,
    data: { meta_surcharge: { amount: 200, currency: 'EUR' } },
    ...overrides,
});

describe('buildMetaSurchargeHtml', () => {
    it('returns empty when DepositFeature is OFF (even if amount + description exist)', () => {
        const formModel = makeFormModel(depositDisabledFeatures, 'should be hidden');
        const html = OptionBuilderHelper.buildMetaSurchargeHtml(productOption(), formModel);
        assert.strictEqual(html, '');
    });

    it('renders amount + description when both exist', () => {
        const formModel = makeFormModel(depositEnabledFeatures, 'na místě');
        const html = OptionBuilderHelper.buildMetaSurchargeHtml(productOption(), formModel);
        assert.match(html, /meta-surcharge/);
        assert.match(html, /200/);
        assert.match(html, /na místě/);
        assert.match(html, /—/);
    });

    it('renders only amount when description is empty', () => {
        const formModel = makeFormModel(depositEnabledFeatures, null);
        const html = OptionBuilderHelper.buildMetaSurchargeHtml(productOption(), formModel);
        assert.match(html, /meta-surcharge/);
        assert.match(html, /200/);
        assert.doesNotMatch(html, /—/);
    });

    it('renders nothing when amount is missing, even with a global description', () => {
        // Description without amount does NOT render (user-requested rule).
        const formModel = makeFormModel(depositEnabledFeatures, 'doplatek 50 EUR na místě');
        const html = OptionBuilderHelper.buildMetaSurchargeHtml(
            productOption({ data: {} }), formModel);
        assert.strictEqual(html, '');
    });

    it('returns empty when neither amount nor description set', () => {
        const formModel = makeFormModel(depositEnabledFeatures, null);
        const html = OptionBuilderHelper.buildMetaSurchargeHtml(
            productOption({ data: {} }), formModel);
        assert.strictEqual(html, '');
    });

    it('returns empty when amount is 0', () => {
        const formModel = makeFormModel(depositEnabledFeatures, null);
        const html = OptionBuilderHelper.buildMetaSurchargeHtml(
            productOption({ data: { meta_surcharge: { amount: 0, currency: 'EUR' } } }), formModel);
        assert.strictEqual(html, '');
    });

    it('renders negative amount with "−" sign (sleva / discount)', () => {
        const formModel = makeFormModel(depositEnabledFeatures, null);
        const html = OptionBuilderHelper.buildMetaSurchargeHtml(
            productOption({ data: { meta_surcharge: { amount: -200, currency: 'EUR' } } }), formModel);
        assert.match(html, /meta-surcharge/);
        assert.match(html, /−\s/);
        assert.match(html, /200/);
        assert.doesNotMatch(html, /\+\s200/);
    });

    it('renders negative amount with description', () => {
        const formModel = makeFormModel(depositEnabledFeatures, 'sleva za včasnou rezervaci');
        const html = OptionBuilderHelper.buildMetaSurchargeHtml(
            productOption({ data: { meta_surcharge: { amount: -50, currency: 'CZK' } } }), formModel);
        assert.match(html, /−/);
        assert.match(html, /sleva za včasnou rezervaci/);
        assert.match(html, /—/);
    });
});

describe('RadioFieldBuilder + meta surcharge rendering', () => {
    it('shows meta-surcharge only on product options that have an amount set', () => {
        // A has amount+desc → renders. B has no amount → renders nothing
        // (description-only is no longer enough to render — user-requested rule).
        const formModel = makeFormModel(depositEnabledFeatures, 'doplatek na místě');
        const field = {
            id: 'p1',
            type: 'select_one',
            title: 'Pick',
            options: [productOption({ id: 'A' }), productOption({ id: 'B', title: 'Ticket B', data: {} })],
            data: {},
        };
        const el = RadioFieldBuilder.create(field, formModel);
        const metaSpans = el.querySelectorAll('.meta-surcharge');
        assert.strictEqual(metaSpans.length, 1);
        assert.match(metaSpans[0].textContent, /200/);
        assert.match(metaSpans[0].textContent, /doplatek na místě/);
    });

    it('hides meta-surcharge for all options when feature off', () => {
        const formModel = makeFormModel(depositDisabledFeatures, 'should be hidden');
        const field = {
            id: 'p2',
            type: 'select_one',
            title: 'Pick',
            options: [productOption()],
            data: {},
        };
        const el = RadioFieldBuilder.create(field, formModel);
        const metaSpans = el.querySelectorAll('.meta-surcharge');
        assert.strictEqual(metaSpans.length, 0);
    });
});

describe('CheckBoxFieldBuilder + meta surcharge rendering', () => {
    it('shows meta-surcharge under each checkbox option when applicable', () => {
        const formModel = makeFormModel(depositEnabledFeatures, null);
        const field = {
            id: 'p3',
            type: 'select_many',
            title: 'Pick many',
            options: [productOption({ id: 'A' }), productOption({ id: 'B', title: 'Plain', data: {} })],
            data: {},
        };
        const el = CheckBoxFieldBuilder.create(field, formModel);
        const metaSpans = el.querySelectorAll('.meta-surcharge');
        // Only A has amount (no description) → 1 visible meta surcharge
        assert.strictEqual(metaSpans.length, 1);
        assert.match(metaSpans[0].textContent, /200/);
    });
});
