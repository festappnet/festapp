import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { WaitlistCommands, parseWaitlistFragment, waitlistRegistrationPayload } from '../../src/components/forms/waitlist_commands.js';
import { FormModel } from '../../src/components/forms/form_models.js';
import { FormSession } from '../../src/components/forms/form_session.js';
import { FormAvailabilityService } from '../../src/components/forms/form_availability_service.js';
import { prepareOfferSession, participantLabel } from '../../src/components/forms/waitlist_form.js';

const fields = [
    { id: 1, type: 'ticket', data: { max_tickets: 4 } },
    { id: 2, type: 'name', is_ticket_field: true, is_required: true },
    { id: 3, type: 'product_type', is_ticket_field: true, is_required: true },
    { id: 4, type: 'email', is_required: true },
];
function session(model) {
    if (!globalThis.CustomEvent) globalThis.CustomEvent = class extends Event { constructor(type, options) { super(type); this.detail = options?.detail; } };
    return new FormSession(model);
}

test('regular uses server public places; waitlist hides products while keeping stable personal IDs', () => {
    const regular = session(new FormModel({ registrationMode: 'regular', capacity: { remainingPublic: 2 }, fields }));
    assert.equal(regular.maxTickets, 2);
    regular.state.tickets = [{ fields: [{ _subFieldId: 2, name: 'Regular' }, { _subFieldId: 3, product_type: 9 }] }];
    regular._syncPayloadFromState();
    assert.equal(regular.payload.ticket[0].fields[0]['2'], 'Regular');
    assert.equal(regular.payload.ticket[0].fields[0].name, 'Regular');
    assert.equal(regular.payload.ticket[0].fields[1]['3'], undefined);
    const waiting = session(new FormModel({ key: 'form-key', registrationMode: 'waitlist', capacity: { remainingPublic: 0 }, fields }));
    assert.equal(waiting.maxTickets, 4);
    assert.deepEqual(waiting._getTicketSubDefs().map(f => f.id), [2]);
    waiting.state.fields.set('4', 'test@example.invalid');
    waiting.state.tickets = [{ fields: [{ _subFieldId: 2, name: 'Robin' }] }];
    waiting._syncPayloadFromState();
    const payload = waitlistRegistrationPayload(waiting);
    assert.deepEqual(payload.people, [{ fields: [{ 2: 'Robin' }] }]);
    assert.equal(payload.email, 'test@example.invalid');
    assert.equal(payload.ticket, undefined);
});

test('closed public registration never closes an authorized offer; full has no submit', () => {
    assert.equal(FormAvailabilityService.getStatus({ registrationMode: 'offer', isOpen: false }).status, 'OPEN');
    const dom = new JSDOM('<main></main>'); globalThis.document = dom.window.document;
    const host = document.querySelector('main');
    assert.equal(FormAvailabilityService.renderStatus(host, {}, { status: 'FULL' }), true);
    assert.equal(host.querySelector('button'), null);
    dom.window.close();
});

test('personal fragment is scoped and cannot be replaced by an order symbol', () => {
    const token = 'a'.repeat(64);
    assert.deepEqual(parseWaitlistFragment(`#waitlist?order_id=12&token=${token}`), { token, orderId: 12 });
    assert.equal(parseWaitlistFragment('#order-preview'), null);
    assert.throws(() => parseWaitlistFragment('#waitlist?order_id=12&token=short'), /INVALID_CAPABILITY/);
});

test('uncertain command retries preserve identity and never persist token/payload', async () => {
    const calls = [];
    const commands = new WaitlistCommands({ functions: { invoke: async (endpoint, args) => {
        calls.push({ endpoint, ...args });
        if (calls.length === 1) throw new Error('network timeout');
        return { data: { status: 'applied', data: { code: 200, order: { id: 3 } } } };
    } } });
    const payload = { offerId: 'offer', token: 'secret', personIds: ['person'] };
    await assert.rejects(commands.command('decline', payload));
    await commands.command('decline', payload);
    assert.equal(calls[0].body.commandId, calls[1].body.commandId);
    assert.equal(calls[1].body.operation, 'decline');
    assert.equal(commands.pending.size, 0);
});

test('offer selects another person by stable identity and preserves partial draft', () => {
    const model = new FormModel({ registrationMode: 'offer', fields });
    model.offerBundle = { pendingCount: 1, slots: [{ participantId: 'a', outcome: 'pending' }], participants: [
        { id: 'a', answers: { fields: [{ 2: 'Alex' }] } }, { id: 'b', answers: { fields: [{ 2: 'Robin' }] } },
    ], orderData: { fields: [{ 4: 'test@example.invalid' }] } };
    model.selectedPeople = ['b'];
    const form = session(model); prepareOfferSession(form, model);
    assert.equal(form.maxTickets, 1);
    assert.equal(form.payload.ticket[0].participantId, 'b');
    assert.equal(form.state.tickets[0].fields[0].name, 'Robin');
    assert.equal(form.state.fields.get('4'), 'test@example.invalid');
    assert.equal(model.offerBundle.slots[0].participantId, 'a');
});

test('offer DOM can deselect all then swap people without inventing a ticket or exposing add/remove', async () => {
    const { FormRenderer } = await import('../../src/components/forms/form_renderer.js');
    const { renderWaitlistControls } = await import('../../src/components/forms/waitlist_form.js');
    const dom = new JSDOM('<main></main>', { url: 'https://example.test/form/test' });
    globalThis.document = dom.window.document; globalThis.window = dom.window;
    const model = new FormModel({ registrationMode: 'offer', fields: fields.filter(f => f.id !== 3) });
    model.offerBundle = { pendingCount: 1, expiresAt: '2030-01-01T00:00:00Z', slots: [{ participantId: 'a', outcome: 'pending' }], participants: [
        { id: 'a', lifecycle: 'offered', answers: { fields: [{ 2: 'Alex' }] } },
        { id: 'b', lifecycle: 'waiting', answers: { fields: [{ 2: 'Robin' }] } },
    ], orderData: { fields: [{ 4: 'test@example.invalid' }] } };
    const page = { host: document.querySelector('main'), resolveWaitlist() {}, renderForm(m) {
        this.currentSession = session(m); prepareOfferSession(this.currentSession, m);
        FormRenderer.render(this.host, this.currentSession, m, false, {});
        renderWaitlistControls(this, m);
    } };
    page.renderForm(model);
    assert.equal(page.currentSession.state.tickets.length, 1);
    assert.equal(page.host.querySelector('.btn-add-ticket'), null);
    assert.equal(page.host.querySelector('.btn-remove-ticket'), null);
    page.host.querySelector('fieldset input').click();
    assert.equal(page.currentSession.state.tickets.length, 0);
    page.host.querySelectorAll('fieldset input')[1].click();
    assert.equal(page.currentSession.state.tickets[0].participantId, 'b');
    assert.equal(page.currentSession.state.tickets[0].fields[0].name, 'Robin');
    dom.window.close();
});

test('current product availability is retained in the model and disabled in existing option builder', async () => {
    const { OptionBuilderHelper } = await import('../../src/components/forms/fields/option_builder_helper.js');
    const dom = new JSDOM('<main></main>'); globalThis.document = dom.window.document;
    const model = new FormModel({ fields: [{ id: 3, type: 'product_type', data: { default_value: '9' }, product_type_data: {
        products: [{ id: 9, title: 'Room', price: 200, maximum: 1, ordered_count: 1, is_dynamically_available: false }],
    } }] });
    const field = model.visibleFields[0];
    assert.equal(field.options[0].isAvailable, false);
    const choice = OptionBuilderHelper.buildOptionWrapper(field, field.options[0], model, 'radio', false);
    assert.equal(choice.querySelector('input').disabled, true);
    assert.equal(choice.querySelector('input').checked, false);
    dom.window.close();
});

test('waitlist people retain typed personal answers after another input and adding a person', async () => {
    const { FormRenderer } = await import('../../src/components/forms/form_renderer.js');
    const dom = new JSDOM('<main></main>', { url: 'https://example.test/form/test' });
    globalThis.document = dom.window.document; globalThis.window = dom.window;
    const model = new FormModel({ registrationMode: 'waitlist', fields: [...fields,
        { id: 5, type: 'surname', is_ticket_field: true, is_required: true },
    ] });
    const current = session(model);
    const host = document.querySelector('main');
    FormRenderer.render(host, current, model, false, { onInput: (event, form) => current.handleInput(event, form) });
    function fill(index, id, value) {
        const input = host.querySelector(`input[data-index="${index}"][data-sub-id="${id}"]`);
        input.value = value;
        input.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
    }
    fill(0, 2, 'Alex');
    fill(0, 5, 'One');
    const NativeEvent = globalThis.Event;
    globalThis.Event = dom.window.Event;
    host.querySelector('.btn-add-ticket').click();
    await new Promise(resolve => setTimeout(resolve, 0));
    globalThis.Event = NativeEvent;
    assert.equal(host.querySelector('input[data-index="0"][data-sub-id="2"]').value, 'Alex');
    assert.equal(host.querySelector('input[data-index="0"][data-sub-id="5"]').value, 'One');
    fill(1, 2, 'Robin');
    fill(1, 5, 'Two');
    assert.deepEqual([...host.querySelectorAll('input[data-sub-id="2"]')].map(i => i.value), ['Alex', 'Robin']);
    assert.deepEqual([...host.querySelectorAll('input[data-sub-id="5"]')].map(i => i.value), ['One', 'Two']);
    assert.deepEqual(waitlistRegistrationPayload(current).people, [
        { fields: [{ 2: 'Alex' }, { 5: 'One' }] }, { fields: [{ 2: 'Robin' }, { 5: 'Two' }] },
    ]);
    dom.window.close();
});

test('participant labels show canonical answers without legacy aliases or internal field IDs', () => {
    assert.equal(participantLabel({id: 'p', answers: {fields: [{107: 'Waiting', name: 'Waiting', _subFieldId: 107}, {108: 'One', surname: 'One', _subFieldId: '108'}]}}), 'Waiting · One');
    assert.equal(participantLabel({id: 'p', answers: {fields: [{name: 'Legacy', _subFieldId: 107}]}}), 'Legacy');
});
