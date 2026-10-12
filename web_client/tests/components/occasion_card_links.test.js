import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

let OccasionCard, OccasionDetailDialog, AppConfig, RouterService;
before(async () => {
    const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://tickets.invalid/' });
    for (const key of ['window', 'document', 'HTMLElement', 'customElements', 'Event', 'CustomEvent', 'DOMParser']) {
        globalThis[key] = key === 'window' ? dom.window : dom.window[key];
    }
    globalThis.localStorage = dom.window.localStorage;
    ({ OccasionCard } = await import('../../src/components/occasion/occasion_card.js'));
    ({ OccasionDetailDialog } = await import('../../src/components/occasion/occasion_detail_dialog.js'));
    ({ AppConfig } = await import('../../src/app_config.js'));
    ({ RouterService } = await import('../../src/services/router_service.js'));
});

const occasion = {
    title: 'Camp registration', link: 'camp', description: '<p>Details</p>',
    start_time: '2026-11-01', end_time: '2026-11-03', form: { link: 'registration' },
    features: [{ code: 'form', is_enabled: true }],
};

test('cards expose real links, retain plain-click dialogs and allow modified clicks to follow the native destination', async t => {
    AppConfig.isAppSupported = true;
    const show = t.mock.method(OccasionDetailDialog, 'show', () => {});
    const card = OccasionCard.create(occasion);
    assert.equal(card.tagName, 'A');
    assert.equal(card.getAttribute('href'), '/form/registration');
    assert.ok(card.textContent.includes('Camp registration'));
    const click = new window.MouseEvent('click', { button: 0, cancelable: true });
    await card.onclick(click);
    assert.equal(click.defaultPrevented, true);
    assert.equal(show.mock.callCount(), 1);
    for (const options of [{ ctrlKey: true }, { metaKey: true }, { shiftKey: true }, { button: 1 }]) {
        const modified = new window.MouseEvent('click', { button: 0, cancelable: true, ...options });
        await card.onclick(modified);
        assert.equal(modified.defaultPrevented, false);
    }
    assert.equal(show.mock.callCount(), 1);
});

test('ticket-only clicks use the same form link as the anchor; events without forms link to their program', async t => {
    AppConfig.isAppSupported = false;
    const navigate = t.mock.method(RouterService, 'navigateToForm', async () => {});
    const card = OccasionCard.create(occasion);
    await card.onclick(new window.MouseEvent('click', { cancelable: true }));
    assert.deepEqual(navigate.mock.calls[0].arguments, ['registration']);
    const program = OccasionCard.create({ ...occasion, features: [] });
    assert.equal(program.getAttribute('href'), '/camp/event');
});

test('invalid external schemes fall back to internal links, and valid external links remain usable', async () => {
    const feature = external_form_link => [{ code: 'form', is_enabled: true, data: { use_external_form: true, external_form_link } }];
    assert.equal(OccasionCard.create({ ...occasion, features: feature('javascript:alert(1)') }).getAttribute('href'), '/form/registration');
    assert.equal(OccasionCard.create({ ...occasion, features: feature('https://organizer.invalid/register') }).href, 'https://organizer.invalid/register');
});
