import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { JSDOM } from 'jsdom';

test('server catalogue remains visible while cards load, then startup completes', async t => {
    const dom = new JSDOM('<div id="web-client-startup"></div><div id="app" style="display:flex"><div id="events-grid"><ul><li>SEO event</li></ul></div></div>', { url: 'https://tickets.invalid/' });
    for (const key of ['window', 'document', 'HTMLElement', 'customElements', 'Event', 'CustomEvent', 'DOMParser']) {
        globalThis[key] = key === 'window' ? dom.window : dom.window[key];
    }
    globalThis.localStorage = dom.window.localStorage;
    t.after(() => dom.window.close());
    const { UnitPage } = await import('../../src/components/unit/unit_page.js');
    const { DbOccasions } = await import('../../src/components/occasion/db_occasions.js');
    const { OccasionCard } = await import('../../src/components/occasion/occasion_card.js');
    let deliver;
    const pending = new Promise(resolve => { deliver = resolve; });
    t.mock.method(DbOccasions, 'getPublicOccasions', () => pending);
    t.mock.method(OccasionCard, 'create', occasion => {
        const card = document.createElement('a');
        card.className = 'occasion-card';
        card.textContent = occasion.title;
        return card;
    });
    let ready = false;
    window.markFestappAppReady = () => {
        ready = true;
        document.getElementById('web-client-startup').remove();
    };
    window.failFestappWebClientStartup = reason => assert.fail(reason);
    const source = readFileSync(new URL('../../src/main.js', import.meta.url), 'utf8')
        .replace(/^import .*;\r?\n/gm, '')
        .replace(/\/\/ Start[\s\S]*$/, 'Main.init();');
    const noop = { init() {} };
    const startup = runInNewContext(source, {
        window, document, console, UnitPage,
        isEmbed: () => false, applyEmbedContext() {},
        resolveScannerRoute: () => null,
        GoogleAuthService: { takeCallback: () => null },
        initializeCoreServices: async () => {},
        handleOrganizerIntent: async () => false,
        LocalizationService: {}, SupabaseService: {}, RightsService: {},
        AppConfig: { organization: 3 },
        ThemeService: noop, ImageLoader: noop, FeedbackFab: noop,
        RouterService: { normalizeUrl: value => new URL(value).pathname, handleInitialLoad: async () => false, initPopStateListener() {} },
    });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(ready, false, 'loading cards does not prematurely mark application ready');
    assert.ok(document.querySelector('#events-grid ul'), 'server links remain usable while loading');
    assert.equal(document.getElementById('app').style.display, 'flex');
    deliver([{ title: 'Card event', start_time: '2099-01-01', end_time: '2099-01-02' }]);
    await startup;
    assert.equal(ready, true);
    assert.equal(document.getElementById('app').style.display, 'flex');
    assert.equal(document.querySelector('#events-grid ul'), null);
    assert.equal(document.querySelector('.occasion-card').textContent, 'Card event');
});


test('actual catalogue shell preserves server links and startup failure recovery', async t => {
    const html = readFileSync(new URL('../../index.html', import.meta.url), 'utf8')
        .replace('<div id="events-grid"></div>', '<div id="events-grid" data-server-catalog="ready"><a href="/form/live">Public event</a></div>');
    const dom = new JSDOM(html, { url: 'https://vstupenky.online/', runScripts: 'outside-only' });
    t.after(() => dom.window.close());
    const { window } = dom;
    const { document } = window;
    const bootstrap = [...document.scripts].find(script => script.textContent.includes('window.markFestappAppReady = function'));
    assert.ok(bootstrap, 'the real startup bootstrap is present');
    window.eval(bootstrap.textContent);
    const fallback = document.getElementById('web-client-startup');
    const links = document.querySelector('a[href="/form/live"]');
    assert.ok(links, 'server-rendered links survive pending startup');
    assert.equal(document.getElementById('app').style.display, 'none', 'styled application controls its reveal');
    assert.equal(fallback.querySelector('button').hidden, true);
    assert.match(document.querySelector('noscript').textContent, /#app\s*\{display:flex!important\}/);
    const recovered = [];
    window.recoverFestappStartup = async reason => { recovered.push(reason); };
    window.failFestappWebClientStartup('web-module-error');
    await Promise.resolve();
    assert.equal(window.__FESTAPP_WEB_STARTUP_FAILURE__, 'web-module-error');
    assert.equal(fallback.querySelector('button').hidden, false);
    assert.notEqual(fallback.querySelector('p').textContent, 'Loading…');
    assert.deepEqual(recovered, ['web-module-error']);
    assert.equal(links.isConnected, true);
    let readyEvents = 0;
    window.addEventListener('festapp-app-ready', () => { readyEvents++; });
    window.markFestappAppReady();
    window.markFestappAppReady();
    window.failFestappWebClientStartup('late-error');
    assert.equal(document.getElementById('web-client-startup'), null);
    assert.equal(readyEvents, 1, 'ready notification is idempotent');
    assert.deepEqual(recovered, ['web-module-error'], 'late failures cannot restart a ready application');
    assert.equal(links.isConnected, true);
});

test('startup runs when the module arrives after DOMContentLoaded', async t => {
    const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://vstupenky.online/' });
    t.after(() => dom.window.close());
    await new Promise(resolve => dom.window.addEventListener('load', resolve, { once: true }));
    assert.equal(dom.window.document.readyState, 'complete');
    let initialized = 0;
    let ready = 0;
    const source = readFileSync(new URL('../../src/main.js', import.meta.url), 'utf8')
        .replace(/^import .*;\r?\n/gm, '');
    runInNewContext(source, {
        window: { ...dom.window, markFestappAppReady() { ready++; }, failFestappWebClientStartup: assert.fail },
        document: dom.window.document, console,
        isEmbed: () => false, applyEmbedContext() {},
        resolveScannerRoute: () => null,
        GoogleAuthService: { takeCallback: () => null },
        initializeCoreServices: async () => { initialized++; },
        handleOrganizerIntent: async () => null,
        AppConfig: {}, ThemeService: { init() {} }, ImageLoader: { init() {} },
        RouterService: { normalizeUrl: value => value, handleInitialLoad: async () => true, initPopStateListener() {} },
        LocalizationService: {}, SupabaseService: {}, RightsService: {},
    });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(initialized, 1, 'late module must initialize services without another DOMContentLoaded');
    assert.equal(ready, 1);
});
