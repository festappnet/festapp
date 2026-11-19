import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

let OccasionCard, OccasionDetailDialog, AppConfig, RouterService, renderOccasionCardPreview, mountOccasionCardPreview, OccasionModel, createOccasionCardView;
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
    ({ renderOccasionCardPreview, mountOccasionCardPreview } = await import('../../src/components/occasion/occasion_card_preview.js'));
    ({ OccasionModel } = await import('../../src/components/occasion/occasion_model.js'));
    ({ createOccasionCardView } = await import('../../src/components/occasion/occasion_card_view.js'));
});

const occasion = {
    title: 'Camp registration', link: 'camp', description: '<p>Details</p>',
    start_time: '2026-11-01', end_time: '2026-11-03', form: { link: 'registration' },
    features: [{ code: 'form', is_enabled: true }],
};

test('settings render the public card with canonical feature parsing, safe draft updates and no reservation actions', () => {
    const container = document.createElement('div');
    for (const [locale, title] of [['cs', 'Skautský ples'], ['en', '<img src=x onerror=alert(1)>']]) {
        const raw = { ...occasion, title, data: { image: 'https://img.festapp.net/images/ball.webp' },
            features: [{ code: 'form', is_enabled: true, external_price: '350 Kč' }] };
        renderOccasionCardPreview(container, { occasion: raw, locale });
        const publicCard = createOccasionCardView(OccasionModel.fromJson(raw), { locale });
        const preview = container.firstElementChild;
        assert.equal(preview.inert, true);
        assert.equal(preview.tabIndex, -1);
        assert.equal(preview.onclick, null);
        assert.equal(preview.innerHTML, publicCard.innerHTML);
        assert.equal(preview.querySelector('.oc-title').textContent, title);
        assert.equal(preview.querySelectorAll('img').length, 1);
        assert.equal(container.children.length, 1);
    }
});

test('preview accepts drafts only from its same-origin parent and reports content height', () => {
    const dom = new JSDOM('<main id="preview"></main>', { url: 'https://tickets.invalid/occasion-card-preview.html' });
    const host = dom.window;
    const reports = [];
    host.postMessage = (data, origin) => reports.push({ data, origin });
    host.ResizeObserver = class { observe() {} };
    mountOccasionCardPreview(host);
    assert.equal(reports[0].data.type, 'festapp-occasion-card-ready');
    const data = { type: 'festapp-occasion-card-draft', occasion, locale: 'cs', dark: false };
    const send = (source, origin, payload = data) => host.dispatchEvent(new host.MessageEvent('message', { data: payload, source, origin }));
    send(host, 'https://other.invalid');
    send(window, host.location.origin);
    assert.equal(host.document.querySelector('.oc-card'), null);
    send(host, host.location.origin);
    assert.equal(host.document.querySelector('.oc-title').textContent, occasion.title);
    assert.equal(host.document.documentElement.lang, 'cs');
    assert.equal(host.document.body.classList.contains('dark-mode'), false);
    send(host, host.location.origin, { ...data, locale: 'en', dark: true });
    assert.equal(host.document.body.classList.contains('dark-mode'), true);
    assert.equal(reports.at(-1).data.type, 'festapp-occasion-card-height');
    assert.ok(reports.every(report => report.origin === host.location.origin));
    host.close();
});

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


test('public cards with missing or invalid dates remain usable without invented dates', () => {
    for (const dates of [{}, { start_time: null, end_time: null }, { start_time: 'invalid', end_time: 'invalid' }]) {
        const card = OccasionCard.create({ ...occasion, start_time: undefined, end_time: undefined, ...dates });
        assert.equal(card.getAttribute('href'), '/form/registration');
        assert.equal(card.querySelector('.oc-date'), null);
        assert.ok(card.textContent.includes(occasion.title));
    }
});
