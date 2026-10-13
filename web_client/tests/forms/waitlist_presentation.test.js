import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { FormModel } from '../../src/components/forms/form_models.js';
import { FormSession } from '../../src/components/forms/form_session.js';
import { FormRenderer } from '../../src/components/forms/form_renderer.js';
import { renderWaitlistControls, ticketLabel } from '../../src/components/forms/waitlist_form.js';
import { waitlistRegistrationPayload } from '../../src/components/forms/waitlist_commands.js';
import { OrderResult } from '../../src/components/forms/order_result.js';
import { LocalizationService } from '../../src/services/localization_service.js';
register('../css_loader.mjs', import.meta.url);
LocalizationService.translations = JSON.parse(readFileSync(new URL('../../public/assets/translations/cs.json', import.meta.url)));
LocalizationService.currentLocale = 'cs';
if (!globalThis.CustomEvent) globalThis.CustomEvent = class extends Event { constructor(type, options) { super(type); this.detail = options?.detail; } };
const fields = [
    { id: 1, type: 'ticket', data: { max_tickets: 3 } },
    { id: 2, type: 'name', title: 'Jméno', is_ticket_field: true, is_required: true },
    { id: 3, type: 'product_type', title: 'Ubytování', is_ticket_field: true, is_required: true, data: { default_value: '9' }, product_type_data: { products: [{ id: 9, title: 'Pokoj', price: 200, currency_code: 'CZK' }] } },
    { id: 4, type: 'email', title: 'E-mail', is_required: true },
];
function dom() {
    const d = new JSDOM('<main id="host"></main>', { url: 'https://example.test/form/test', pretendToBeVisual: true });
    globalThis.document = d.window.document; globalThis.window = d.window; globalThis.HTMLElement = d.window.HTMLElement;
    window.scrollTo = () => {};
    globalThis.requestAnimationFrame = d.window.requestAnimationFrame.bind(d.window);
    return d;
}
const initialDom = dom();
const { OrderPreview } = await import('../../src/components/forms/order_preview.js');
initialDom.window.close();

test('occupancy uses admitted count even when waiting priority reduces public availability', () => {
    const d = dom();
    for (const registrationMode of ['regular', 'waitlist']) {
        const model = new FormModel({ registrationMode, fields, capacity: { showRemaining: true, limit: 12, occupiedPeople: 11, offeredPlaces: 0, waitingPeople: 3, remainingPublic: registrationMode === 'regular' ? 1 : 0 } });
        const current = new FormSession(model);
        const host = document.querySelector('main');
        FormRenderer.render(host, current, model, false, {});
        renderWaitlistControls({ host, currentSession: current }, model);
        assert.equal(host.querySelector('.form-occupancy').textContent, 'Obsazenost: 11 z 12');
        assert.equal(host.querySelector('form').firstElementChild.className, 'form-registration-status');
        if (registrationMode === 'waitlist') assert.match(host.querySelector('.waitlist-intro').textContent, /e-mailem nabídku/);
    }
    d.window.close();
});
test('waiting products keep labeled disabled choices, no default, no required validation or payload', () => {
    const d = dom();
    const model = new FormModel({ registrationMode: 'waitlist', fields });
    const current = new FormSession(model);
    const host = document.querySelector('main');
    FormRenderer.render(host, current, model, false, {});
    const product = host.querySelector('.waitlist-product-options');
    assert.ok(product); assert.match(product.textContent, /Ubytování/); assert.match(product.textContent, /Pokoj/);
    assert.match(product.textContent, /a zaplatíte až/);
    const input = product.querySelector('input');
    assert.ok(input.disabled); assert.equal(input.checked, false); assert.equal(input.required, false);
    assert.equal(product.disabled, true);
    assert.equal(product.querySelector('.btn-clear-selection'), null);
    current.state.tickets = [{ fields: [{ name: 'Alex', _subFieldId: 2 }] }, { fields: [{ name: 'Robin', _subFieldId: 2 }] }];
    current._syncPayloadFromState();
    const payload = waitlistRegistrationPayload(current);
    assert.deepEqual(payload.tickets, [{ fields: [{ 2: 'Alex' }] }, { fields: [{ 2: 'Robin' }] }]);
    assert.equal(payload.payment_type, undefined); assert.equal(payload.currency_code, undefined);
    const prepared = OrderPreview._prepareData(null, model, current.state, current.payload);
    host.innerHTML = OrderPreview._render(prepared);
    assert.match(host.textContent, /Alex/); assert.match(host.textContent, /Robin/);
    assert.equal(host.querySelector('.preview-total-price'), null);
    assert.equal(host.querySelector('input[name="payment_type"]'), null);
    assert.equal(host.querySelector('.btn-submit-order').textContent.trim(), 'Přihlásit mezi náhradníky');
    assert.doesNotMatch(host.textContent, /Pokoj/);
    d.window.close();
});
test('classic preview and result retain finance while waitlist shares result with accurate wording', () => {
    const d = dom(); const host = document.querySelector('main');
    const model = new FormModel({ registrationMode: 'regular', fields });
    const current = new FormSession(model);
    host.innerHTML = OrderPreview._render(OrderPreview._prepareData(null, model, { totalPrice: 200, currency: 'CZK' }, current.payload));
    assert.ok(host.querySelector('.preview-total-price'));
    const result = { ticketOrder: { order: { order_symbol: 'ABC123', data: { email: 'test@example.invalid' } } }, payment_qr: { amount: 200, currency_code: 'CZK', account_number: '123' } };
    OrderResult.render(host, true, result, model, () => {});
    assert.ok(host.querySelector('.result-payment-card'));
    model.registrationMode = 'waitlist';
    OrderResult.render(host, true, result, model, () => {});
    assert.equal(host.querySelector('.result-title').textContent, 'Jste v pořadníku náhradníků');
    assert.match(host.querySelector('.result-subtitle').textContent, /e-mailem nabídku/);
    assert.match(host.querySelector('.result-order-symbol').textContent, /ABC123/);
    assert.equal(host.querySelector('.result-payment-card'), null);
    OrderResult.render(host, false, { errorCode: 'WAITLIST_NOT_AVAILABLE' }, model, () => {});
    assert.match(host.querySelector('.result-subtitle').textContent, /nyní není dostupné/);
    d.window.close();
});
test('single management entry needs no checkbox, multi-entry selects IDs and never displays internal IDs', async () => {
    const d = dom(); const { FormPage } = await import('../../src/components/forms/form_page.js');
    const page = new FormPage('host'); page.waitlistScope = { orderId: 20, token: 'secret' };
    const calls = []; page.resolveWaitlist = (...args) => calls.push(args);
    const first = { id: 8837, lifecycle: 'waiting', answers: { fields: [] } };
    page.renderWaitlistManagement({ tickets: [first] });
    assert.equal(page.host.querySelector('input'), null);
    assert.doesNotMatch(page.host.textContent, /8837/);
    assert.match(page.host.textContent, /Osoba 1/);
    page.host.querySelector('button').click();
    assert.deepEqual(calls.pop(), ['withdraw', [8837]]);
    page.renderWaitlistManagement({ tickets: [first, { id: 9000, lifecycle: 'waiting', answers: { fields: [{2: 'Robin'}] } }] });
    assert.ok(page.host.querySelector('button').disabled);
    assert.match(page.host.textContent, /Vyberte osoby/);
    page.host.querySelectorAll('input')[1].click(); page.host.querySelector('button').click();
    assert.deepEqual(calls.pop(), ['withdraw', [9000]]);
    page.renderWaitlistManagement({ tickets: [{ ...first, lifecycle: 'withdrawn' }] });
    assert.equal(page.host.querySelector('button'), null);
    assert.equal(ticketLabel({ id: 7777 }), 'Osoba 1');
    d.window.close();
});
test('withdraw and decline use shared preview and only execute after its confirmation', async () => {
    const d = dom(); const { FormPage } = await import('../../src/components/forms/form_page.js');
    const page = new FormPage('host'); page.waitlistScope = { orderId: 20, token: 'secret' };
    page.waitlistBundle = { tickets: [{ id: 8837, lifecycle: 'waiting', answers: { fields: [{2: '<Alex>'}] } }] };
    page.init = async () => {};
    const calls = []; page.waitlistCommands = { command: async (...args) => calls.push(args) };
    const show = OrderPreview.show;
    let confirm;
    try {
        OrderPreview.show = (form, model, prices, callback, close, payload, presentation) => {
            confirm = callback;
            assert.equal(model.registrationMode, 'waitlist');
            assert.deepEqual(presentation.people, ['<Alex>']);
            assert.ok(presentation.explanation);
        };
        for (const operation of ['withdraw', 'decline']) {
            const before = calls.length;
            await page.resolveWaitlist(operation, [8837]);
            assert.equal(calls.length, before);
            const overlay = document.createElement('div'); overlay.innerHTML = '<button class="btn-submit-order"></button>';
            await confirm(overlay);
            assert.deepEqual(calls.at(-1), [operation, { ...page.waitlistScope, ticketIds: [8837] }]);
        }
    } finally { OrderPreview.show = show; d.window.close(); }
});

test('waitlist validates into the classic preview and submits personal payload through the shared result lifecycle', async () => {
    const d = dom();
    const [{ FormPage }, { RouterService }, { FormValidator }, { FormNetwork }] = await Promise.all([
        import('../../src/components/forms/form_page.js'), import('../../src/services/router_service.js'),
        import('../../src/components/forms/form_validator.js'), import('../../src/components/forms/form_network.js'),
    ]);
    const model = new FormModel({ key: 'test-key', registrationMode: 'waitlist', fields });
    const current = new FormSession(model);
    current.state.fields.set('4', 'alex@example.invalid');
    current.state.tickets = [{ fields: [{name: 'Alex', _subFieldId: 2}] }]; current._syncPayloadFromState();
    const page = new FormPage('host'); page.currentSession = current;
    page.cleanup = () => {}; page.renderForm = () => {};
    const original = { show: OrderPreview.show, valid: FormValidator.validateAndShowErrors, back: RouterService.goBackProgrammatically, push: RouterService.pushOverlayState, network: FormNetwork.submitOrder };
    let registered = 0; let confirmation;
    try {
        FormValidator.validateAndShowErrors = () => true;
        window.confirm = () => { throw new Error('Native confirmation is forbidden'); };
        FormNetwork.submitOrder = () => { throw new Error('Waitlist must not create a payable order'); };
        RouterService.pushOverlayState = () => {};
        RouterService.goBackProgrammatically = () => setTimeout(() => window.dispatchEvent(new window.PopStateEvent('popstate')), 0);
        page.waitlistCommands = { command: async (operation, payload) => {
            registered++; assert.equal(operation, 'register');
            assert.deepEqual(payload.tickets, [{ fields: [{ 2: 'Alex' }] }]);
            assert.equal(payload.email, 'alex@example.invalid');
            assert.equal(payload.ticket, undefined);
            return { code: 200, order: { order_symbol: 'ABC123' } };
        } };
        OrderPreview.show = (form, passedModel, price, callback) => { assert.equal(passedModel, model); confirmation = callback; };
        page._previewModulePromise = Promise.resolve({ OrderPreview });
        const form = document.createElement('form');
        page.validateAndSubmit(form, model);
        await new Promise(resolve => setTimeout(resolve, 0));
        assert.equal(registered, 0); assert.equal(typeof confirmation, 'function');
        const overlay = document.createElement('div'); overlay.id = 'order-preview-overlay'; document.body.appendChild(overlay);
        confirmation(overlay);
        await new Promise(resolve => setTimeout(resolve, 25));
        assert.equal(registered, 1);
        assert.equal(document.querySelector('.fullscreen-result-overlay .result-title').textContent, 'Jste v pořadníku náhradníků');
        assert.equal(document.querySelector('.result-payment-card'), null);
        assert.equal(document.querySelector('.fullscreen-loader-overlay'), null);
    } finally {
        OrderPreview.show = original.show; FormValidator.validateAndShowErrors = original.valid;
        RouterService.goBackProgrammatically = original.back; RouterService.pushOverlayState = original.push;
        FormNetwork.submitOrder = original.network; d.window.close();
    }
});
