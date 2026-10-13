import '../helpers/style_imports.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { JSDOM } from 'jsdom';

test('home stays covered until the SEO text list has been replaced with cards', async t => {
    const dom = new JSDOM('<div id="web-client-startup"></div><div id="app" style="display:none"><div id="events-grid"><ul><li>SEO event</li></ul></div></div>', { url: 'https://tickets.invalid/' });
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
        LocalizationService: {}, SupabaseService: {}, RightsService: {},
        AppConfig: { organization: 3 },
        ThemeService: noop, ImageLoader: noop, FeedbackFab: noop,
        RouterService: { handleInitialLoad: async () => false, initPopStateListener() {} },
    });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(ready, false, 'startup overlay must remain while events are loading');
    assert.equal(document.getElementById('app').style.display, 'none');
    deliver([{ title: 'Card event', start_time: '2099-01-01', end_time: '2099-01-02' }]);
    await startup;
    assert.equal(ready, true);
    assert.equal(document.getElementById('app').style.display, 'flex');
    assert.equal(document.querySelector('#events-grid ul'), null);
    assert.equal(document.querySelector('.occasion-card').textContent, 'Card event');
});
