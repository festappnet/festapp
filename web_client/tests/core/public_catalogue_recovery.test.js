import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { JSDOM } from 'jsdom';

test('unknown public paths render the catalogue without reloading', async t => {
    const dom = new JSDOM('<div id="app" style="display:none"><div id="events-grid"></div></div>', { url: 'https://tickets.invalid/unknown' });
    for (const key of ['window', 'document', 'HTMLElement', 'customElements', 'Event', 'CustomEvent', 'DOMParser']) {
        globalThis[key] = key === 'window' ? dom.window : dom.window[key];
    }
    globalThis.localStorage = dom.window.localStorage;
    t.after(() => dom.window.close());
    const [{ RouterService }, { AppConfig }, { UnitPage }, { DbOccasions }, { OccasionCard }] = await Promise.all([
        import('../../src/services/router_service.js'), import('../../src/app_config.js'),
        import('../../src/components/unit/unit_page.js'), import('../../src/components/occasion/db_occasions.js'),
        import('../../src/components/occasion/occasion_card.js'),
    ]);
    const supported = AppConfig.isAppSupported;
    AppConfig.isAppSupported = false;
    t.after(() => { AppConfig.isAppSupported = supported; });
    t.mock.method(RouterService, 'initPopStateListener', () => {});
    t.mock.method(DbOccasions, 'getPublicCatalogue', async () => ({ occasions: [{ title: 'QA catalogue', start_time: '2099-01-01', end_time: '2099-01-02' }] }));
    t.mock.method(OccasionCard, 'create', occasion => {
        const card = document.createElement('a');
        card.className = 'occasion-card';
        card.textContent = occasion.title;
        return card;
    });
    const source = readFileSync(new URL('../../src/main.js', import.meta.url), 'utf8')
        .replace(/^import .*;\r?\n/gm, '').replace(/\/\/ Start[\s\S]*$/, 'Main.init();');
    const noop = { init() {} };
    for (const path of ['/qa-unknown', '/unknown/deep/path', '/map-editor']) {
        window.history.replaceState(null, '', path);
        document.querySelector('#app').style.display = 'none';
        let ready = false;
        window.markFestappAppReady = () => { ready = true; };
        window.failFestappWebClientStartup = assert.fail;
        await runInNewContext(source, {
            window, document, console, UnitPage, RouterService, AppConfig,
            isEmbed: () => false, applyEmbedContext() {}, resolveScannerRoute: () => null,
            GoogleAuthService: { takeCallback: () => null },
            initializeCoreServices: async () => {}, handleOrganizerIntent: async () => null,
            LocalizationService: {}, SupabaseService: {}, RightsService: {},
            ThemeService: noop, ImageLoader: noop, FeedbackFab: noop,
        });
        assert.equal(window.location.pathname, '/', path);
        assert.equal(RouterService._lastPath, '/');
        assert.equal(document.querySelector('#app').style.display, 'flex');
        assert.equal(document.querySelector('.occasion-card').textContent, 'QA catalogue');
        assert.equal(ready, true);
    }
});
