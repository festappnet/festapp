import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('', { url: 'https://forms.example/' });
Object.assign(globalThis, {
    window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement,
    Node: dom.window.Node, Event: dom.window.Event,
});
after(() => dom.window.close());
const { OptionBuilderHelper } = await import('../../src/components/forms/fields/option_builder_helper.js');
const { CheckBoxFieldBuilder } = await import('../../src/components/forms/fields/check_box_field_builder.js');
const { DateFieldBuilder } = await import('../../src/components/forms/fields/date_field_builder.js');
const { IdDocumentFieldBuilder } = await import('../../src/components/forms/fields/id_document_field_builder.js');
const { TicketFieldBuilder } = await import('../../src/components/forms/fields/ticket_field_builder.js');
const { FormRenderer } = await import('../../src/components/forms/form_renderer.js');
const { LocalizationService } = await import('../../src/services/localization_service.js');
LocalizationService.currentLocale = 'cs';

const attackTitle = '<img src=x onerror="window.__xss=1"> & Title';
const description = '<p style="color: red"><strong>Useful details</strong> <a href="https://example.com/info">Info</a></p><img src="/safe.jpg" onerror="window.__xss=1"><a href="java&#x09;script:window.__xss=1">Bad</a>';
const field = { id: 101, title: attackTitle, description, isRequired: true, data: {} };
function assertSafeDescription(root) {
    assert.equal(root.querySelector('[onerror], [onclick], script, iframe'), null);
    assert.ok(root.querySelector('strong'));
    assert.equal(root.querySelector('p').style.color, 'red');
    assert.equal(root.querySelector('a').href, 'https://example.com/info');
    assert.equal(root.querySelectorAll('a')[1].hasAttribute('href'), false);
    assert.equal(root.querySelector('img').getAttribute('src'), '/safe.jpg');
}

test('field titles are text and required stars remain visible', () => {
    const label = OptionBuilderHelper.buildFieldLabel(field);
    assert.equal(label.textContent, `${attackTitle}*`);
    assert.equal(label.querySelector('img'), null);
    assert.equal(label.querySelector('.required-star').textContent, '*');
});

test('option title, rich description, prices, deposit and checkbox label behavior survive', () => {
    const opt = { id: 7, title: attackTitle, description, price: 1000, currency: 'CZK', data: { deposit: { amount: 200 } } };
    const model = { occasionFeatures: [{ code: 'deposit', is_enabled: true, deposit_deadline: 'on_site' }] };
    const wrapper = OptionBuilderHelper.buildOptionWrapper(field, opt, model, 'checkbox', true);
    document.body.append(wrapper);
    assert.equal(wrapper.querySelector('.form-check-label span').textContent, attackTitle);
    assert.equal(wrapper.querySelector('.form-check-label img'), null);
    assert.match(wrapper.querySelector('.option-price').textContent, /1\s*000\s*Kč/);
    assert.match(wrapper.querySelector('.deposit-info').textContent, /200\s*Kč/);
    assertSafeDescription(wrapper.querySelector('.option-description'));
    const input = wrapper.querySelector('input');
    assert.equal(wrapper.querySelector('label').htmlFor, input.id);
    wrapper.querySelector('label').click();
    assert.equal(input.checked, true);
    wrapper.querySelector('.option-description').click();
    assert.equal(input.checked, false);
    wrapper.remove();
});

test('meta surcharge description is displayed as text without executable markup', () => {
    const model = { occasionFeatures: [{ code: 'deposit', is_enabled: true, deposit_mode: 'virtual', meta_surcharge_description: attackTitle }] };
    const wrapper = OptionBuilderHelper.buildOptionWrapper(field,
        { id: 7, title: 'Entry', currency: 'EUR', data: { meta_surcharge: { amount: 50 } } }, model, 'radio', false);
    const surcharge = wrapper.querySelector('.meta-surcharge');
    assert.ok(surcharge.textContent.includes(attackTitle));
    assert.equal(surcharge.querySelector('img'), null);
    assert.ok(surcharge.textContent.includes('50'));
});

for (const [name, create] of [
    ['checkbox', () => CheckBoxFieldBuilder.create(field, {})],
    ['date', () => DateFieldBuilder.create(field, {})],
    ['ID document', () => IdDocumentFieldBuilder.create(field, {})],
    ['ticket', () => TicketFieldBuilder.create({ ...field, subFields: [{ id: 102, type: 'text', title: 'Name' }] }, {},
        { maxTickets: 2, state: { tickets: [] }, addTicket() { this.state.tickets.push({ fields: [] }); }, addEventListener() {}, removeEventListener() {} })],
]) {
    test(`${name} builder sanitizes descriptions and preserves required inputs`, () => {
        const node = create();
        const descriptions = node.querySelectorAll('.form-field-description');
        assert.ok(descriptions.length > 0);
        for (const desc of descriptions) assertSafeDescription(desc);
        assert.equal(node.querySelector('[onerror]'), null);
        if (name !== 'ticket') assert.ok(node.querySelector('input[required]'));
        for (const input of node.querySelectorAll('input')) input._flatpickr?.destroy();
        node.destroy?.();
    });
}

test('single checkbox keeps literal title, star and working label association', () => {
    const node = CheckBoxFieldBuilder.create(field, {});
    document.body.append(node);
    const label = node.querySelector('.single-checkbox label');
    assert.equal(label.textContent, `${attackTitle} *`);
    assert.equal(label.querySelector('img'), null);
    label.click();
    assert.equal(node.querySelector('.single-checkbox input').checked, true);
    node.remove();
});

test('ticket seat name stays literal and its price remains visible', () => {
    const node = TicketFieldBuilder.create({ ...field, subFields: [{ id: 102, type: 'spot', title: 'Seat' }] },
        { blueprint: {} }, { maxTickets: 2, state: { tickets: [{ spot: 3, spotName: attackTitle, spotPrice: 100 }] },
            addEventListener() {}, removeEventListener() {} });
    assert.equal(node.querySelector('.form-control span').textContent, attackTitle);
    assert.equal(node.querySelector('.form-control img'), null);
    assert.ok(node.querySelector('.option-price').textContent.includes('100'));
    node.destroy();
});

test('existing form header and description callers sanitize without losing LCP image priority', () => {
    const node = document.createElement('div');
    FormRenderer.render(node, null, { header: description, description, visibleFields: [] }, false, {});
    assertSafeDescription(node.querySelector('.form-header'));
    assertSafeDescription(node.querySelector('.form-description'));
    assert.equal(node.querySelector('.form-header img').getAttribute('fetchpriority'), 'high');
});
