import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { FormModel } from '../../src/components/forms/form_models.js';
import { FormAvailabilityService as Availability } from '../../src/components/forms/form_availability_service.js';
import { CountdownWidget } from '../../src/components/forms/widgets/countdown_widget.js';

test('scheduled closed bundle shows countdown instead of the old closed message', () => {
    const dom = new JSDOM('<main></main>');
    globalThis.document = dom.window.document;
    const model = new FormModel({
        is_open: true, registrationMode: 'closed', header_off: 'Old closed message',
        data: { schedule: { start_time: '2099-01-01T12:00:00Z', enable_countdown: true } },
    });
    try {
        const status = Availability.getStatus(model);
        assert.equal(status.status, 'BEFORE_START');
        const host = document.querySelector('main');
        assert.equal(Availability.renderStatus(host, model, status), true);
        assert.ok(host.querySelector('.countdown-widget'));
        assert.equal(host.querySelector('.not-available-widget'), null);
        assert.ok(Number(host.querySelector('#cd-days').textContent) > 0);
    } finally { CountdownWidget.stop(); dom.window.close(); }
});

test('opening instant respects authoritative closure; authorized offers stay open', () => {
    const future = new Date('2099-01-01');
    const past = new Date('2000-01-01');
    assert.equal(Availability.getStatus({ registrationMode: 'closed', isOpen: false, startTime: future }).status, 'CLOSED');
    assert.equal(Availability.getStatus({ registrationMode: 'closed', isOpen: true, startTime: past }).status, 'CLOSED');
    assert.equal(Availability.getStatus({ registrationMode: 'full', isOpen: true, startTime: past }).status, 'FULL');
    assert.equal(Availability.getStatus({ registrationMode: 'offer', isOpen: false, startTime: future }).status, 'OPEN');
    assert.equal(Availability.getStatus({ registrationMode: 'regular', isOpen: true, startTime: past }).status, 'OPEN');
});

for (const enabled of [false, true]) {
    test(`pre-start information is opt-in (${enabled}) and cannot render registration controls`, () => {
        const dom = new JSDOM('<main></main>');
        globalThis.document = dom.window.document;
        const model = new FormModel({
            is_open: true,
            header_off: '<p>Closed message</p>',
            data: { schedule: {
                start_time: '2099-01-01T12:00:00Z', enable_countdown: true,
                show_before_start_message: enabled,
                before_start_message: '<h2>Hall plan</h2><img src="https://example.test/hall.png" onerror="alert(1)"><script>alert(1)</script><input name="email"><button>Register</button>',
            } },
        });
        try {
            const host = document.querySelector('main');
            assert.equal(Availability.renderStatus(host, model, Availability.getStatus(model)), true);
            assert.ok(host.querySelector('.countdown-widget'));
            const info = host.querySelector('.form-before-start-message');
            assert.equal(!!info, enabled);
            if (enabled) {
                assert.equal(info.querySelector('h2').textContent, 'Hall plan');
                assert.equal(info.querySelector('img').src, 'https://example.test/hall.png');
                assert.equal(info.querySelector('img').hasAttribute('onerror'), false);
                assert.equal(info.querySelector('input, button, script'), null);
            }
            assert.doesNotMatch(host.textContent, /Closed message/);
        } finally { CountdownWidget.stop(); dom.window.close(); }
    });
}

test('pre-start information stays hidden outside public countdown mode', () => {
    const dom = new JSDOM('<main></main>');
    globalThis.document = dom.window.document;
    const model = new FormModel({
        is_open: true, header_off: 'Closed message',
        data: { schedule: {
            start_time: '2099-01-01T12:00:00Z', enable_countdown: true,
            show_before_start_message: true, before_start_message: '<h2>Hall plan</h2>',
        } },
    });
    try {
        const host = document.querySelector('main');
        assert.equal(Availability.renderStatus(host, model, Availability.getStatus(model), { showPreview: true }), false);
        assert.equal(host.children.length, 0);
        for (const schedule of [
            { ...model.data.schedule, enable_countdown: false },
            { ...model.data.schedule, start_time: '2000-01-01' },
        ]) {
            host.replaceChildren();
            const other = new FormModel({ is_open: true, data: { schedule } });
            Availability.renderStatus(host, other, Availability.getStatus(other));
            assert.equal(host.querySelector('.form-before-start-message'), null);
        }
        model.isOpen = false;
        Availability.renderStatus(host, model, Availability.getStatus(model));
        assert.equal(host.querySelector('.form-before-start-message'), null);
    } finally { CountdownWidget.stop(); dom.window.close(); }
});

test('expired countdown calls reload once and stops its timer', () => {
    const dom = new JSDOM('<main></main>');
    globalThis.document = dom.window.document;
    let reloads = 0;
    try {
        CountdownWidget.render(document.querySelector('main'), {
            startTime: new Date('2000-01-01'), countdownTitle: '<b>Start</b><script>alert(1)</script>',
        }, () => reloads++);
        assert.equal(reloads, 1);
        assert.equal(CountdownWidget.timer, null);
        assert.equal(document.querySelector('script'), null);
        assert.equal(document.querySelector('.countdown-title b').textContent, 'Start');
    } finally { CountdownWidget.stop(); dom.window.close(); }
});
