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
