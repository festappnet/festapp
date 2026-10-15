import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { classifyOccasions, extractPublicOccasions, groupPastOccasionsByYear } from '../../src/components/occasion/catalog.js';
let UnitPage, DbOccasions, OccasionCard, LocalizationService;
before(async () => {
    const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://vstupenky.online/' });
    for (const key of ['window', 'document', 'HTMLElement', 'customElements', 'Event', 'CustomEvent', 'DOMParser']) globalThis[key] = key === 'window' ? dom.window : dom.window[key];
    globalThis.localStorage = dom.window.localStorage;
    ({ UnitPage } = await import('../../src/components/unit/unit_page.js'));
    ({ DbOccasions } = await import('../../src/components/occasion/db_occasions.js'));
    ({ OccasionCard } = await import('../../src/components/occasion/occasion_card.js'));
    ({ LocalizationService } = await import('../../src/services/localization_service.js'));
});
function fixture() {
    document.body.innerHTML = '<input id="search"><button id="clear-search"></button><div id="catalog"><a href="/form/server">Server event</a></div>';
    const page = new UnitPage('catalog'); page.init('search'); return page;
}
test('shared classification keeps boundary times, null/invalid dates and copies visible', () => {
    const now = Date.parse('2026-10-15T12:00:00Z');
    const groups = classifyOccasions([
        { title: 'Current', start_time: new Date(now), end_time: new Date(now) },
        { title: 'Upcoming', start_time: '2026-11-01', end_time: '2026-11-02' },
        { title: 'Past (Copy)', start_time: '2020-01-01', end_time: '2020-01-02' },
        { title: 'Null', start_time: null, end_time: null }, { title: 'Invalid', start_time: 'invalid' },
    ], now);
    assert.equal(groups.present[0].title, 'Current');
    assert.equal(groups.upcoming[0].title, 'Upcoming');
    assert.equal(groups.past[0].title, 'Past (Copy)');
    assert.deepEqual(groups.undated.map(o => o.title), ['Null', 'Invalid']);
});
test('failed refresh preserves SSR links, safely renders error and retry updates catalogue', async t => {
    LocalizationService.currentLocale = 'cs';
    const page = fixture();
    let fail = true;
    t.mock.method(DbOccasions, 'getPublicOccasions', async () => { if (fail) throw new Error('<img src=x onerror=alert(1)>'); return []; });
    await page.loadOccasions(3);
    assert.ok(document.querySelector('a[href="/form/server"]'));
    assert.equal(document.querySelector('img'), null);
    assert.match(document.querySelector('[role=status]').textContent, /aktualizovat/);
    fail = false;
    document.querySelector('[data-catalog-status] button').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(document.querySelector('a[href="/form/server"]'), null);
    assert.match(document.querySelector('[role=status]').textContent, /žádné akce/);
});
test('past events stay visible before and after search, with distinct empty search states in both locales', async t => {
    t.mock.method(OccasionCard, 'create', occasion => { const a = document.createElement('a'); a.href = '/form/' + occasion.link; a.textContent = occasion.title; return a; });
    for (const locale of ['cs', 'en']) {
        LocalizationService.currentLocale = locale;
        const page = fixture();
        t.mock.method(DbOccasions, 'getPublicOccasions', async () => [{ title: 'Historická akce', link: 'past', start_time: '2020-01-01', end_time: '2020-01-02' }]);
        await page.loadOccasions(3);
        assert.equal(document.querySelector('details'), null);
        assert.ok(document.querySelector('section.catalog-archive a[href="/form/past"]'));
        page.filter('historicka');
        assert.equal(document.querySelector('details'), null);
        assert.ok(document.querySelector('section.catalog-archive a[href="/form/past"]'));
        page.filter('missing');
        assert.match(document.querySelector('[role=status]').textContent, locale === 'cs' ? /tento výraz/ : /match your search/);
        document.querySelector('[data-catalog-status] button').click();
        assert.equal(document.querySelector('details'), null);
        assert.ok(document.querySelector('section.catalog-archive a[href="/form/past"]'));
    }
});
test('disposed catalogue ignores a late response', async t => {
    const page = fixture(); let resolve;
    t.mock.method(DbOccasions, 'getPublicOccasions', () => new Promise(done => { resolve = done; }));
    const pending = page.loadOccasions(3); page.clear(); resolve([]); await pending;
    assert.equal(document.querySelector('#catalog').children.length, 0);
});


test('public catalogue response contract distinguishes an empty result from invalid payloads', () => {
    for (const valid of [[], { occasions: [] }, { data: { occasions: [] } }]) assert.deepEqual(extractPublicOccasions(valid), []);
    for (const invalid of [null, {}, { occasions: 'bad' }, { error: 'unavailable' }]) assert.throws(() => extractPublicOccasions(invalid));
});

function pastEvents(count, multiYear = true) {
    return Array.from({ length: count }, (_, i) => ({
        title: `Past event ${i}`, link: `past-${i}`,
        start_time: `${multiYear && i % 2 ? 2023 : 2024}-01-01T12:00:00Z`,
        end_time: `${multiYear && i % 2 ? 2023 : 2024}-01-02T12:00:00Z`,
    }));
}

test('archive years require nine events and multiple known start years, preserving every event', () => {
    assert.deepEqual(groupPastOccasionsByYear(pastEvents(8)), []);
    assert.deepEqual(groupPastOccasionsByYear(pastEvents(9, false)), []);
    const events = pastEvents(9);
    const groups = groupPastOccasionsByYear(events);
    assert.deepEqual(groups.map(group => group.year), [2024, 2023]);
    assert.deepEqual(groups[0].occasions, events.filter((_, i) => i % 2 === 0));
    assert.equal(groups.flatMap(group => group.occasions).length, 9);
    for (const invalid of [null, '', 'invalid']) {
        assert.deepEqual(groupPastOccasionsByYear([...events, { start_time: invalid }]), []);
    }
    assert.equal(groupPastOccasionsByYear([...events, { start_time: '2025-01-01T00:30:00+01:00' }])[0].year, 2024);
});

test('large multi-year archive shows year headings and every completed card without a disclosure', t => {
    const flags = [];
    t.mock.method(OccasionCard, 'create', (occasion, present, past) => {
        flags.push({ present, past });
        const a = document.createElement('a'); a.href = '/form/' + occasion.link; a.textContent = occasion.title; return a;
    });
    const page = fixture();
    page.render(pastEvents(9));
    assert.ok(!document.querySelector('.catalog-archive h2').textContent.includes('('));
    assert.deepEqual([...document.querySelectorAll('.catalog-archive h3')].map(h => h.textContent), ['2024', '2023']);
    assert.equal(document.querySelectorAll('.catalog-archive a').length, 9);
    assert.equal(document.querySelector('details'), null);
    assert.ok(flags.every(flag => flag.past && !flag.present));
    page.render(pastEvents(8));
    assert.equal(document.querySelector('.catalog-archive h3'), null);
    assert.equal(document.querySelectorAll('.catalog-archive a').length, 8);
    page.render(pastEvents(9, false));
    assert.equal(document.querySelector('.catalog-archive h3'), null);
    assert.equal(document.querySelectorAll('.catalog-archive a').length, 9);
});


test('unit catalogue passes its scope to the RPC and preserves it for retry', async t => {
    const page = fixture();
    const calls = [];
    t.mock.method(DbOccasions, 'getPublicOccasions', async (...args) => {
        calls.push(args);
        if (calls.length === 1) throw new Error('offline');
        return [];
    });
    await page.loadOccasions(1, 2);
    document.querySelector('[data-catalog-status] button').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(calls, [[1, 2], [1, 2]]);
});
