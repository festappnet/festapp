import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { JSDOM } from 'jsdom';

const source = readFileSync(new URL('../../src/marketing/landing.js', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '');

test('marketing waits for shared account initialization before mounting the account header', async () => {
    const dom = new JSDOM('<header class="site-header auth-pending"></header>', { url: 'https://vstupenky.online/' });
    try {
        let complete;
        let themeInitialized = false;
        const rights = { context: null, updateAppData: async () => { throw Error('unexpected second fetch'); } };
        const context = vm.createContext({
            window: dom.window, document: dom.window.document, URL, console,
            ThemeService: { init() { themeInitialized = true; } },
            LocalizationService: {}, SupabaseService: {}, RightsService: rights,
            AppConfig: { isAppSupported: false },
            initializeCoreServices: () => new Promise(resolve => { complete = resolve; }),
            initDemoPlayers() {}, initMotion() {}, initReferenceCarousels() {},
        });
        vm.runInContext(source, context);
        assert.equal(themeInitialized, true);
        assert.ok(dom.window.document.querySelector('.auth-pending'));
        assert.equal(dom.window.document.querySelector('user-header'), null);
        rights.context = { user_info: { id: 'existing-user', name: 'Eva' } };
        complete();
        await new Promise(resolve => setImmediate(resolve));
        assert.ok(dom.window.document.querySelector('user-header[data-marketing]'));
        assert.equal(dom.window.document.querySelector('.site-header'), null);
    } finally { dom.window.close(); }
});

test('theme preference persists between marketing and application and follows system in auto mode', async () => {
    const dom = new JSDOM('<body></body>', { url: 'https://vstupenky.online/' });
    const previous = { window: globalThis.window, document: globalThis.document, localStorage: globalThis.localStorage };
    Object.assign(globalThis, { window: dom.window, document: dom.window.document, localStorage: dom.window.localStorage });
    dom.window.matchMedia = () => ({ matches: true, addEventListener() {} });
    try {
        const { ThemeService } = await import('../../src/services/theme_service.js');
        ThemeService.init();
        assert.equal(document.body.classList.contains('dark-mode'), true);
        ThemeService.setMode('light');
        assert.equal(localStorage.getItem('theme'), 'light');
        ThemeService.init();
        assert.equal(document.body.classList.contains('dark-mode'), false);
        ThemeService.setMode('dark');
        ThemeService.init();
        assert.equal(document.body.classList.contains('dark-mode'), true);
        ThemeService.setMode('auto');
        assert.equal(localStorage.getItem('theme'), null);
        assert.equal(ThemeService.currentMode, 'auto');
    } finally { Object.assign(globalThis, previous); dom.window.close(); }
});
