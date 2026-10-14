import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { WaitlistCommands, parseWaitlistFragment, waitlistRegistrationPayload } from '../../src/components/forms/waitlist_commands.js';
import { FormModel } from '../../src/components/forms/form_models.js';
import { FormSession } from '../../src/components/forms/form_session.js';
import { FormAvailabilityService } from '../../src/components/forms/form_availability_service.js';
import { prepareOfferSession, ticketLabel } from '../../src/components/forms/waitlist_form.js';

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
    assert.deepEqual(payload.tickets, [{ fields: [{ 2: 'Robin' }] }]);
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

test('admin offer fragment requires explicit marker and a single valid offer without a token', () => {
    const offerId = '12345678-1234-1234-abcd-123456789012';
    assert.deepEqual(parseWaitlistFragment(`#waitlist?offer_id=${offerId}&admin=1`), { token: null, offerId });
    for (const query of [
        `offer_id=${offerId}`, `offer_id=${offerId}&admin=0`, `offer_id=${offerId}&admin=true`,
        'order_id=12&admin=1', `offer_id=${offerId}&order_id=12&admin=1`,
        'offer_id=------------------------------------&admin=1', 'offer_id=bad&admin=1',
        `offer_id=${offerId}&admin=1&token=`, `offer_id=${offerId}&admin=1&token=bad`,
        `offer_id=${offerId}&offer_id=${offerId}&admin=1`, `offer_id=${offerId}&admin=1&admin=0`,
    ]) assert.throws(() => parseWaitlistFragment(`#waitlist?${query}`), /INVALID_CAPABILITY/, query);
    const token = 'b'.repeat(64);
    assert.deepEqual(parseWaitlistFragment(`#waitlist?offer_id=${offerId}&token=${token}`), { token, offerId });
    assert.deepEqual(parseWaitlistFragment(`#waitlist?order_id=12&token=${token}`), { token, orderId: 12 });
});

test('admin offer uses normal read and acceptance transports with real scope and no client privilege flag', async () => {
    const offerId = '12345678-1234-1234-abcd-123456789012';
    const scope = parseWaitlistFragment(`#waitlist?offer_id=${offerId}&admin=1`);
    const calls = [];
    const bundle = { code: 200, pendingCount: 1, tickets: [{ id: 101, lifecycle: 'offered' }] };
    const commands = new WaitlistCommands({
        rpc: async (name, args) => { calls.push({ name, args }); return { data: bundle }; },
        functions: { invoke: async (name, args) => { calls.push({ name, args }); return { data: { code: 200 } }; } },
    });
    assert.equal(await commands.read(scope), bundle);
    assert.deepEqual(calls[0], { name: 'get_waitlist_offer_form', args: { p_token: null, p_offer_id: offerId, p_order_id: null } });
    const details = { form: 'real-form-key', ticket: [{ fields: [{ 2: 'Alex' }] }] };
    await commands.accept(scope, [101], details);
    assert.equal(calls[1].name, 'send-ticket-order');
    assert.deepEqual(calls[1].args.body.waitlistAcceptance, { token: null, offerId, ticketIds: [101] });
    assert.equal(calls[1].args.body.orderDetails, details);
    assert.ok(calls[1].args.body.commandId);
});

test('admin marker cannot bypass server authentication or authorization rejection', async () => {
    const scope = parseWaitlistFragment('#waitlist?offer_id=12345678-1234-1234-abcd-123456789012&admin=1');
    for (const response of [{ error: new Error('unauthenticated') }, { data: { code: 403, errorCode: 'INVALID_CAPABILITY' } }]) {
        const commands = new WaitlistCommands({ rpc: async () => response, functions: { invoke: async () => response } });
        await assert.rejects(commands.read(scope), /INVALID_CAPABILITY/);
        await assert.rejects(commands.accept(scope, [101], {}), /INVALID_CAPABILITY|WAITLIST_COMMAND_FAILED/);
    }
});

test('uncertain command retries preserve identity and never persist token/payload', async () => {
    const calls = [];
    const commands = new WaitlistCommands({ functions: { invoke: async (endpoint, args) => {
        calls.push({ endpoint, ...args });
        if (calls.length === 1) throw new Error('network timeout');
        return { data: { status: 'applied', data: { code: 200, order: { id: 3 } } } };
    } } });
    const payload = { offerId: 'offer', token: 'secret', ticketIds: [101] };
    await assert.rejects(commands.command('decline', payload));
    await commands.command('decline', payload);
    assert.equal(calls[0].body.commandId, calls[1].body.commandId);
    assert.equal(calls[1].body.operation, 'decline');
    assert.equal(commands.pending.size, 0);
});

test('offer selects another person by stable identity and preserves partial draft', () => {
    const model = new FormModel({ registrationMode: 'offer', fields });
    model.offerBundle = { pendingCount: 1, slots: [{ ticketId: 101, outcome: 'pending' }], tickets: [
        { id: 101, answers: { fields: [{ 2: 'Alex' }] } }, { id: 102, answers: { fields: [{ 2: 'Robin' }] } },
    ], orderData: { fields: [{ 4: 'test@example.invalid' }] } };
    model.selectedTicketIds = [102];
    const form = session(model); prepareOfferSession(form, model);
    assert.equal(form.maxTickets, 1);
    assert.equal(form.payload.ticket[0].ticketId, 102);
    assert.equal(form.state.tickets[0].fields[0].name, 'Robin');
    assert.equal(form.state.fields.get('4'), 'test@example.invalid');
    assert.equal(model.offerBundle.slots[0].ticketId, 101);
});

test('offer DOM can deselect all then swap people without inventing a ticket or exposing add/remove', async () => {
    const { FormRenderer } = await import('../../src/components/forms/form_renderer.js');
    const { renderWaitlistControls } = await import('../../src/components/forms/waitlist_form.js');
    const dom = new JSDOM('<main></main>', { url: 'https://example.test/form/test' });
    globalThis.document = dom.window.document; globalThis.window = dom.window;
    const model = new FormModel({ registrationMode: 'offer', fields: fields.filter(f => f.id !== 3) });
    model.offerBundle = { pendingCount: 1, expiresAt: '2030-01-01T00:00:00Z', slots: [{ ticketId: 101, outcome: 'pending' }], tickets: [
        { id: 101, lifecycle: 'offered', answers: { fields: [{ 2: 'Alex' }] } },
        { id: 102, lifecycle: 'waiting', answers: { fields: [{ 2: 'Robin' }] } },
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
    assert.equal(page.currentSession.state.tickets[0].ticketId, 102);
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
    assert.deepEqual(waitlistRegistrationPayload(current).tickets, [
        { fields: [{ 2: 'Alex' }, { 5: 'One' }] }, { fields: [{ 2: 'Robin' }, { 5: 'Two' }] },
    ]);
    dom.window.close();
});

test('participant labels show canonical answers without legacy aliases or internal field IDs', () => {
    assert.equal(ticketLabel({id: 'p', answers: {fields: [{107: 'Waiting', name: 'Waiting', _subFieldId: 107}, {108: 'One', surname: 'One', _subFieldId: '108'}]}}), 'Waiting One');
    assert.equal(ticketLabel({id: 'p', answers: {fields: [{name: 'Legacy', _subFieldId: 107}]}}), 'Legacy');
});


test('two tickets keep independent same-type custom answers, notes and products through rebuilds', async () => {
    const { FormRenderer } = await import('../../src/components/forms/form_renderer.js');
    const dom = new JSDOM('<main></main>', { url: 'https://example.test/form/test' });
    globalThis.document = dom.window.document; globalThis.window = dom.window;
    const model = new FormModel({ registrationMode: 'regular', fields: [
        { id: 1, type: 'ticket', data: { max_tickets: 4 } },
        { id: 107, type: 'name', is_ticket_field: true },
        { id: 108, type: 'surname', is_ticket_field: true },
        { id: 109, type: 'text', title: 'Diet', is_ticket_field: true },
        { id: 110, type: 'text', title: 'Accessibility', is_ticket_field: true },
        { id: 111, type: 'note', is_ticket_field: true },
        { id: 112, type: 'product_type', is_ticket_field: true, product_type_data: { products: [
            { id: 201, title: 'Standard', price: 100, currency_code: 'CZK', is_available: true },
            { id: 202, title: 'Premium', price: 200, currency_code: 'CZK', is_available: true },
        ] } },
    ] });
    const current = session(model);
    const host = document.querySelector('main');
    FormRenderer.render(host, current, model, false, { onInput: (event, form) => current.handleInput(event, form) });
    const inputFor = (index, id) => host.querySelector(`input[data-index="${index}"][data-sub-id="${id}"]`);
    const fill = (index, id, value) => {
        const input = inputFor(index, id);
        assert.ok(input, `rendered ticket ${index} field ${id}`);
        input.value = value;
        input.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
    };
    const chooseProduct = (index, id) => {
        const input = host.querySelector(`input[data-index="${index}"][data-sub-id="112"][value="${id}"]`);
        assert.ok(input, `rendered product ${id} for ticket ${index}`);
        input.checked = true;
        input.dispatchEvent(new dom.window.Event('change', { bubbles: true }));
    };
    const firstAnswers = { 107: 'Alex', 108: 'One', 109: 'Vegan', 110: 'Step-free', 111: 'Arrive early' };
    for (const [id, value] of Object.entries(firstAnswers)) fill(0, id, value);
    chooseProduct(0, 201);
    const firstTicket = structuredClone(current.payload.ticket[0]);
    const NativeEvent = globalThis.Event;
    try {
        globalThis.Event = dom.window.Event;
        host.querySelector('.btn-add-ticket').click();
        await new Promise(resolve => setTimeout(resolve, 0));
    } finally { globalThis.Event = NativeEvent; }
    for (const [id, value] of Object.entries(firstAnswers)) assert.equal(inputFor(0, id).value, value);
    assert.equal(host.querySelector('input[data-index="0"][value="201"]').checked, true);
    for (const [id, value] of Object.entries({ 107: 'Robin', 108: 'Two', 109: 'No nuts', 110: 'Hearing loop', 111: 'Arrive late' })) fill(1, id, value);
    chooseProduct(1, 202);
    fill(1, 109, 'Gluten-free');
    assert.equal(current.payload.ticket.length, 2);
    assert.deepEqual(current.payload.ticket[0], firstTicket);
    const answers = ticket => Object.assign({}, ...ticket.fields.map(field => Object.fromEntries(Object.entries(field).filter(([key]) => /^\d+$/.test(key)))));
    assert.deepEqual(current.payload.ticket.map(answers), [firstAnswers,
        { 107: 'Robin', 108: 'Two', 109: 'Gluten-free', 110: 'Hearing loop', 111: 'Arrive late' },
    ]);
    assert.deepEqual(current.payload.ticket.map(ticket => ticket.fields.find(field => field.product_type !== undefined).product_type), ['201', '202']);
    assert.notEqual(current.payload.ticket[0].fields, current.payload.ticket[1].fields);
    for (const [id, value] of Object.entries(firstAnswers)) assert.equal(inputFor(0, id).value, value);
    dom.window.close();
});


test('offer checkout and resolution serialize canonical numeric ticket IDs across partial refresh', async () => {
    const calls = [];
    const commands = new WaitlistCommands({ functions: { invoke: async (endpoint, args) => {
        calls.push({ endpoint, body: args.body });
        return { data: { data: { code: 200 } } };
    } } });
    const bundle = { pendingCount: 2, slots: [{ ticketId: 701, outcome: 'pending' }, { ticketId: 702, outcome: 'pending' }], tickets: [
        { id: 701, lifecycle: 'offered', answers: { fields: [{ 2: 'Alex' }] } },
        { id: 702, lifecycle: 'offered', answers: { fields: [{ 2: 'Robin' }] } },
    ], orderData: { fields: [{ 4: 'test@example.invalid' }] } };
    const model = new FormModel({ registrationMode: 'offer', fields });
    model.offerBundle = bundle;
    model.selectedTicketIds = [702];
    const first = session(model);
    prepareOfferSession(first, model);
    await commands.accept({ offerId: 'offer', token: 'secret' }, model.selectedTicketIds, first.payload);
    assert.deepEqual(calls[0].body.waitlistAcceptance.ticketIds, [702]);
    assert.equal(calls[0].body.orderDetails.ticket[0].ticketId, 702);
    assert.equal(calls[0].body.orderDetails.ticket[0].fields[0]['2'], 'Robin');
    const refreshed = new FormModel({ registrationMode: 'offer', fields });
    refreshed.offerBundle = { ...bundle, pendingCount: 1, tickets: [bundle.tickets[0]], slots: [bundle.slots[0]] };
    const remaining = session(refreshed);
    prepareOfferSession(remaining, refreshed);
    assert.deepEqual(refreshed.selectedTicketIds, [701]);
    assert.equal(remaining.payload.ticket[0].ticketId, 701);
    assert.equal(remaining.payload.ticket[0].fields[0]['2'], 'Alex');
    await commands.accept({ offerId: 'offer' }, refreshed.selectedTicketIds, remaining.payload);
    await commands.command('withdraw', { orderId: 9, ticketIds: [701] });
    assert.deepEqual(calls[1].body.waitlistAcceptance.ticketIds, [701]);
    assert.deepEqual(calls[2].body.payload.ticketIds, [701]);
    for (const call of calls) {
        assert.equal(JSON.stringify(call).includes('participantId'), false);
        assert.equal(JSON.stringify(call).includes('personIds'), false);
    }
});


test('cleared single and multiple choices override defaults after adding another ticket', async () => {
    const { FormRenderer } = await import('../../src/components/forms/form_renderer.js');
    const { OptionBuilderHelper } = await import('../../src/components/forms/fields/option_builder_helper.js');
    const dom = new JSDOM('<main></main>', { url: 'https://example.test/form/test' });
    globalThis.document = dom.window.document; globalThis.window = dom.window;
    const definition = [
        { id: 1, type: 'ticket', data: { max_tickets: 4 } },
        { id: 2, type: 'select_many', is_ticket_field: true, data: { default_value: ['A', 'B'], options: [{ value: 'A' }, { value: 'B' }] } },
        { id: 3, type: 'product_type', is_ticket_field: true, data: { default_value: '9' }, product_type_data: { products: [{ id: 9, title: 'Admission', price: 100, currency_code: 'CZK' }] } },
    ];
    const model = new FormModel({ registrationMode: 'regular', fields: definition });
    const current = session(model);
    const host = document.querySelector('main');
    FormRenderer.render(host, current, model, false, { onInput: (event, form) => current.handleInput(event, form) });
    const checkboxes = [...host.querySelectorAll('input[type="checkbox"]')];
    assert.equal(checkboxes.every(input => input.checked), true);
    for (const checkbox of checkboxes) {
        checkbox.checked = false;
        checkbox.dispatchEvent(new dom.window.Event('change', { bubbles: true }));
    }
    const NativeEvent = globalThis.Event;
    try {
        globalThis.Event = dom.window.Event;
        host.querySelector('.btn-clear-selection').click();
        host.querySelector('.btn-add-ticket').click();
        await new Promise(resolve => setTimeout(resolve, 0));
    } finally { globalThis.Event = NativeEvent; }
    assert.equal(host.querySelectorAll('input[data-index="0"]:checked').length, 0);
    assert.equal(host.querySelectorAll('input[data-index="1"]:checked').length, 3);
    assert.equal(current.payload.ticket[1].fields.filter(field => field._subFieldId === 2).length, 1);
    assert.equal(current.payload.ticket[1].fields.find(field => field._subFieldId === 2)['2'], 'A | B');
    assert.equal(current.payload.ticket[0].fields.some(field => field.product_type !== undefined), false);
    assert.equal(current.payload.ticket[0].fields.find(field => field._subFieldId === 2)['2'], '');
    assert.equal(OptionBuilderHelper.shouldPreselect({ value: [], data: { default_value: ['A'] } }, { title: 'A' }, 'checkbox'), false);
    const waiting = session(new FormModel({ registrationMode: 'waitlist', fields: definition }));
    assert.equal(waiting._getTicketSubDefs().some(field => field.type === 'product_type'), false);
    dom.window.close();
});


test('saved empty standard choices survive full form rebuild instead of configured defaults', async () => {
    const { FormRenderer } = await import('../../src/components/forms/form_renderer.js');
    const dom = new JSDOM('<main></main>', { url: 'https://example.test/form/test' });
    globalThis.document = dom.window.document; globalThis.window = dom.window;
    const model = new FormModel({ fields: [
        { id: 21, type: 'select_many', data: { default_value: ['A'], options: [{ value: 'A' }] } },
        { id: 22, type: 'select_one', data: { default_value: 'B', options: [{ value: 'B' }] } },
    ] });
    const current = session(model);
    const host = document.querySelector('main');
    const render = () => FormRenderer.render(host, current, model, false, { onInput: (event, form) => current.handleInput(event, form) });
    render();
    const checkbox = host.querySelector('input[type="checkbox"]');
    assert.equal(checkbox.checked, true);
    checkbox.checked = false;
    checkbox.dispatchEvent(new dom.window.Event('change', { bubbles: true }));
    const NativeEvent = globalThis.Event;
    try { globalThis.Event = dom.window.Event; host.querySelector('.btn-clear-selection').click(); }
    finally { globalThis.Event = NativeEvent; }
    assert.deepEqual(current.state.fields.get('21'), []);
    assert.equal(current.state.fields.get('22'), '');
    render();
    assert.equal(host.querySelectorAll('input:checked').length, 0);
    assert.deepEqual(current.payload.fields, [{ 21: [] }, { 22: '' }]);
    dom.window.close();
});


test('initial DOM multiselect hydration retains separate stable IDs for same-type fields', async () => {
    const { FormDataReader } = await import('../../src/components/forms/form_data_reader.js');
    const dom = new JSDOM('<form><input name="1_0_2" value="A"><input name="1_0_2" value="B"><input name="1_0_5" value="C"><input name="1_0_5" value="D"><input name="1_0_6" value="E"></form>');
    const NativeFormData = globalThis.FormData;
    globalThis.FormData = dom.window.FormData;
    try {
        const model = new FormModel({ fields: [
            { id: 1, type: 'ticket' },
            { id: 2, type: 'select_many', is_ticket_field: true },
            { id: 5, type: 'select_many', is_ticket_field: true },
            { id: 6, type: 'select_many', is_ticket_field: true, data: { options: [{ id: 'E', value: 'E', price: 0 }] } },
        ] });
        const current = session(model);
        current.state.tickets = FormDataReader.getTicketDataFromDom(dom.window.document.querySelector('form'), model);
        current._syncPayloadFromState();
        assert.equal(current.payload.ticket.length, 1);
        assert.equal(current.payload.ticket[0].fields.some(field => 'product_type' in field), false);
        assert.deepEqual(current.payload.ticket[0].fields.map(field => ({id: field._subFieldId, value: field[field._subFieldId]})), [
            {id: 2, value: 'A | B'}, {id: 5, value: 'C | D'}, {id: 6, value: 'E'},
        ]);
    } finally { globalThis.FormData = NativeFormData; dom.window.close(); }
});


test('waitlist mode hides occupancy while regular mode includes active offer holds', async () => {
    const { renderWaitlistControls } = await import('../../src/components/forms/waitlist_form.js');
    const { LocalizationService } = await import('../../src/services/localization_service.js');
    const previous = LocalizationService.tr;
    LocalizationService.tr = (key) => key === 'Waitlist.occupancy' ? 'Occupied: {occupied} of {capacity}' : key;
    try {
        for (const registrationMode of ['regular', 'waitlist']) {
            const dom = new JSDOM('<main><form></form></main>');
            globalThis.document = dom.window.document; globalThis.window = dom.window;
            const model = new FormModel({ registrationMode, fields: [], capacity: { showRemaining: true, limit: 10, occupiedPeople: 9, offeredPlaces: 1, waitingPeople: 1, heldForWaiting: 0 } });
            renderWaitlistControls({host: document.querySelector('main'), currentSession: { addEventListener() {} }}, model);
            assert.equal(document.querySelector('.form-occupancy')?.textContent ?? null, registrationMode === 'regular' ? 'Occupied: 11 of 10' : null);
            dom.window.close();
        }
    } finally { LocalizationService.tr = previous; }
});
