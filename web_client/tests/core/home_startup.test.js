import '../helpers/style_imports.js';
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
        .replace("document.addEventListener('DOMContentLoaded', Main.init);", 'Main.init();');
    const noop = { init() {} };
    const startup = runInNewContext(source, {
        window, document, console, UnitPage,
        GoogleAuthService: { takeCallback: () => null },
        initializeCoreServices: async () => {},
        handleOrganizerIntent: async () => false,
        LocalizationService: {}, SupabaseService: {}, RightsService: {},
        AppConfig: { organization: 3 },
        ThemeService: noop, ImageLoader: noop, FeedbackFab: noop,
        RouterService: { handleInitialLoad: async () => false, initPopStateListener() {} },
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


test('actual server catalogue shell reveals links while startup is pending and retains failure recovery', () => {
    const html = readFileSync(new URL('../../index.html', import.meta.url), 'utf8')
        .replace('<div id="events-grid"></div>', '<div id="events-grid" data-server-catalog="ready"><a href="/form/live">Public event</a></div>');
    const dom = new JSDOM(html, { url: 'https://vstupenky.online/', runScripts: 'outside-only' });
    const reveal = [...dom.window.document.scripts].find(script => script.textContent.includes("document.querySelector('#events-grid[data-server-catalog]')"));
    dom.window.eval(reveal.textContent);
    assert.equal(dom.window.document.querySelector('#app').style.display, 'flex');
    assert.equal(dom.window.document.querySelector('#web-client-startup').style.position, 'relative');
    assert.equal(dom.window.document.querySelector('#site-introduction').hidden, true);
    assert.ok(dom.window.document.querySelector('a[href="/form/live"]'));
    dom.window.close();
});
