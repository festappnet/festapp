import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);
const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.com/' });
Object.assign(global, { window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements, Event: dom.window.Event, EventTarget: dom.window.EventTarget, CustomEvent: dom.window.CustomEvent });
dom.window.HTMLElement.prototype.scrollIntoView = () => {};
const { FormSession } = await import('../../src/components/forms/form_session.js');
const { FormRenderer } = await import('../../src/components/forms/form_renderer.js');
const { FormValidator } = await import('../../src/components/forms/form_validator.js');
const { FormPage } = await import('../../src/components/forms/form_page.js');
const { EmailSuffixConfirmation } = await import('../../src/components/forms/email_suffix_confirmation.js');
const { LocalizationService } = await import('../../src/services/localization_service.js');
LocalizationService.translations = { EmailDomainSuffix: { warning: 'Unknown .{suffix}', warningInformal: 'Check .{suffix}', confirm: 'Address is correct' } };
const type = (input, value) => { input.value = value; input.dispatchEvent(new dom.window.Event('input', { bubbles: true })); };
const warning = input => input.parentElement.querySelector('[data-email-suffix-warning]');

function fixture(fields = [{ id: 1, type: 'email', isRequired: true }]) {
    const model = { key: 'test', secret: 'test', visibleFields: fields, relatedFields: fields };
    const session = new FormSession(model);
    const host = document.createElement('div');
    document.body.replaceChildren(host);
    let requests = 0;
    const page = { host, currentSession: session, handlePreview: () => requests++ };
    const render = () => FormRenderer.render(host, session, model, false, {
        onSubmit: form => FormPage.prototype.validateAndSubmit.call(page, form, model),
        onInput: (e, form) => { FormValidator.handleInputValidation(e, form, session); session.handleInput(e, form); },
    });
    render();
    return { host, model, session, render, requests: () => requests, input: () => host.querySelector('input[type="email"]'), submit: () => host.querySelector('.btn-submit').click() };
}

test('blur, correction, explicit confirmation, rerender, edit and one ordinary submit', async () => {
    const f = fixture();
    type(f.input(), 'a@example.czz');
    assert.equal(warning(f.input()).hidden, true);
    f.input().dispatchEvent(new dom.window.Event('blur'));
    assert.equal(warning(f.input()).hidden, false);
    type(f.input(), 'a@example.cz');
    assert.equal(warning(f.input()).hidden, true);
    type(f.input(), 'a@example.czz');
    f.submit();
    assert.equal(f.requests(), 0);
    assert.equal(document.activeElement, warning(f.input()).querySelector('button'));
    assert.ok(f.input().getAttribute('aria-describedby').includes(warning(f.input()).id));
    warning(f.input()).querySelector('button').click();
    assert.equal(f.requests(), 0, 'confirmation never submits');
    f.render();
    assert.equal(f.input().value, 'a@example.czz');
    assert.equal(warning(f.input()).hidden, true);
    f.submit();
    assert.equal(f.requests(), 1, 'one click enters the existing submit path once');
    type(f.input(), 'b@example.czz');
    f.submit();
    assert.equal(f.requests(), 1);
    assert.equal(warning(f.input()).hidden, false);
    assert.deepEqual(f.session.state.validationErrors, {});
    assert.equal(JSON.stringify(f.session.payload).includes('confirmed'), false);
    const fresh = fixture();
    type(fresh.input(), 'a@example.czz'); fresh.submit();
    assert.equal(fresh.requests(), 0, 'new session does not inherit confirmation');
});

test('ordinary required/format errors precede suffix checks; optional empty passes', () => {
    const f = fixture();
    f.submit();
    assert.equal(f.requests(), 0);
    type(f.input(), 'broken'); f.submit();
    assert.equal(f.requests(), 0);
    type(f.input(), 'bujnmi@co'); f.submit();
    assert.equal(f.requests(), 0, 'native HTML validity accepts an unqualified host; checkout must reject it');
    assert.equal(warning(f.input()).hidden, true);
    type(f.input(), 'a@example.co'); f.submit();
    assert.equal(f.requests(), 1);
    const optional = fixture([{ id: 2, type: 'email' }]);
    optional.submit();
    assert.equal(optional.requests(), 1);
});

test('same address in two fields needs two confirmations; hidden/disabled/read-only excluded', () => {
    const f = fixture([{ id: 1, type: 'email' }, { id: 2, type: 'email' }]);
    const inputs = [...f.host.querySelectorAll('input')];
    inputs.forEach(input => type(input, 'a@example.comm'));
    f.submit(); warning(inputs[0]).querySelector('button').click(); f.submit();
    assert.equal(f.requests(), 0);
    assert.equal(warning(inputs[1]).hidden, false);
    warning(inputs[1]).querySelector('button').click(); f.submit();
    assert.equal(f.requests(), 1);
    for (const mode of ['hidden', 'disabled', 'readOnly']) {
        type(inputs[0], 'new@example.czz');
        if (mode === 'hidden') inputs[0].closest('.form-field-container').hidden = true;
        else inputs[0][mode] = true;
        assert.equal(EmailSuffixConfirmation.validate(f.host.querySelector('form'), f.session.emailSuffixConfirmations, f.session), true);
        inputs[0].closest('.form-field-container').hidden = false;
        inputs[0][mode] = false;
    }
});

test('ticket identity survives index changes and never inherits a removed ticket confirmation', async () => {
    const f = fixture([{ id: 99, type: 'ticket', subFields: [{ id: 7, type: 'email' }], data: { max_tickets: 2 } }]);
    f.session.addTicket();
    await Promise.resolve();
    const inputs = [...f.host.querySelectorAll('input[type="email"]')];
    assert.equal(inputs.length, 2);
    inputs.forEach(input => type(input, 'a@example.czz'));
    f.submit(); warning(inputs[0]).querySelector('button').click(); f.submit();
    assert.equal(f.requests(), 0);
    assert.equal(warning(inputs[1]).hidden, false);
    await f.session.removeTicket(0, true);
    await Promise.resolve();
    f.submit();
    assert.equal(f.requests(), 0, 'remaining ticket must not inherit index zero confirmation');
    warning(f.input()).querySelector('button').click(); f.submit();
    assert.equal(f.requests(), 1);
});

test('invalid contact syntax appears on blur and clears after correction', () => {
    const f = fixture();
    type(f.input(), 'bujnmi@co');
    assert.equal(f.input().classList.contains('invalid'), false);
    f.input().dispatchEvent(new dom.window.Event('blur'));
    assert.equal(f.input().classList.contains('invalid'), true);
    type(f.input(), 'customer@example.co');
    assert.equal(f.input().classList.contains('invalid'), false);
    f.submit();
    assert.equal(f.requests(), 1);
});
