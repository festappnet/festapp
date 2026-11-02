import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { JSDOM } from 'jsdom';

const html = await readFile(new URL('../../index.html', import.meta.url), 'utf8');

function boot({ blockedWorker = false } = {}) {
    const reports = [];
    const serviceWorker = new EventTarget();
    serviceWorker.controller = { postMessage: (message) => reports.push(message) };
    serviceWorker.ready = Promise.resolve();
    const dom = new JSDOM(html, {
        url: 'https://app.test/',
        runScripts: 'dangerously',
        beforeParse(window) {
            Object.defineProperty(window.navigator, 'serviceWorker', blockedWorker
                ? { get() { throw new window.DOMException('Blocked', 'SecurityError'); } }
                : { value: serviceWorker });
        },
    });
    return { dom, reports, serviceWorker };
}

test('cached HTML reports its generation before any module is available', (t) => {
    const { dom, reports, serviceWorker } = boot();
    t.after(() => dom.window.close());
    assert.equal(reports.length, 1);
    assert.equal(reports[0].type, 'FESTAPP_CLIENT_VERSION');
    assert.equal(reports[0].version, dom.window.__FESTAPP_BUILD_VERSION__);
    serviceWorker.dispatchEvent(new Event('controllerchange'));
    assert.equal(reports.length, 2);
});

test('failed entry module leaves a visible recovery action, not a blank page', (t) => {
    const { dom } = boot();
    t.after(() => dom.window.close());
    const { document, Event } = dom.window;
    const entry = document.querySelector('script[type="module"][src]');
    entry.dispatchEvent(new Event('error'));
    const fallback = document.getElementById('web-client-startup');
    assert.ok(fallback, 'the HTML must remain usable without application JavaScript');
    assert.match(fallback.textContent, /nepodařilo|could not/);
    assert.equal(fallback.querySelector('button').hidden, false);
});

test('usable application removes the startup surface and reports readiness', (t) => {
    const { dom } = boot();
    t.after(() => dom.window.close());
    let ready = 0;
    dom.window.addEventListener('festapp-app-ready', () => ready++);
    dom.window.markFestappAppReady();
    assert.equal(dom.window.__FESTAPP_APP_READY__, true);
    assert.equal(dom.window.document.getElementById('web-client-startup'), null);
    assert.equal(ready, 1);
    dom.window.markFestappAppReady();
    assert.equal(ready, 1);
});


test('an optional analytics module cannot reload a Google continuation', (t) => {
    const { dom } = boot();
    t.after(() => dom.window.close());
    const { document, Event } = dom.window;
    let recoveries = 0;
    dom.window.recoverFestappStartup = async () => { recoveries++; };
    const analytics = document.createElement('script');
    analytics.type = 'module';
    analytics.src = 'https://static.cloudflareinsights.com/beacon.min.js';
    document.head.appendChild(analytics);
    analytics.dispatchEvent(new Event('error'));
    assert.equal(recoveries, 0);
    assert.equal(dom.window.__FESTAPP_WEB_STARTUP_FAILURE__, undefined);
    const entry = [...document.querySelectorAll('script[type="module"][src]')].find(script => new URL(script.src).origin === dom.window.location.origin);
    entry.dispatchEvent(new Event('error'));
    assert.equal(recoveries, 1, 'the actual entry module must retain bounded recovery');
});


test('a restricted service-worker getter cannot disable startup recovery', (t) => {
    const { dom } = boot({ blockedWorker: true });
    t.after(() => dom.window.close());
    assert.equal(typeof dom.window.failFestappWebClientStartup, 'function');
    dom.window.failFestappWebClientStartup('restricted-webview');
    assert.equal(dom.window.document.querySelector('#web-client-startup button').hidden, false);
    dom.window.markFestappAppReady();
    assert.equal(dom.window.document.getElementById('web-client-startup'), null);
});

test('retry repairs the native entry-script cache before preparing a reload', async (t) => {
    const { dom } = boot({ blockedWorker: true });
    t.after(() => dom.window.close());
    const calls = [];
    dom.window.fetch = async (url, options) => {
        calls.push({ url, cache: options.cache });
        return { ok: true, headers: new Headers({ 'content-type': 'application/javascript' }), arrayBuffer: async () => { calls.push('body-read'); return new ArrayBuffer(0); } };
    };
    dom.window.prepareFestappNetworkReload = async () => {
        calls.push('reload-prepared');
        throw new Error('stop before JSDOM navigation');
    };
    await dom.window.retryFestappWebClient();
    assert.equal(calls[0]?.cache, 'reload', 'a cached 404 must be replaced in the browser cache');
    assert.match(calls[0].url, /src\/main\.js$/);
    assert.deepEqual(calls.slice(1), ['body-read', 'reload-prepared'], 'consume the response before reloading so the native cache is repaired');
});

test('retry keeps recovery usable if the entry script is still missing', async (t) => {
    const { dom } = boot();
    t.after(() => dom.window.close());
    let reloads = 0;
    dom.window.fetch = async () => ({ ok: false });
    dom.window.prepareFestappNetworkReload = async () => { reloads++; };
    await dom.window.retryFestappWebClient();
    assert.equal(reloads, 0, 'a failed entry fetch must not reload into another cached error');
    assert.equal(dom.window.document.querySelector('#web-client-startup button').disabled, false);
});


test('retry rejects an HTML fallback instead of reloading into a broken module', async (t) => {
    const { dom } = boot({ blockedWorker: true });
    t.after(() => dom.window.close());
    let reloads = 0;
    dom.window.fetch = async () => ({ ok: true, headers: new Headers({ 'content-type': 'text/html' }) });
    dom.window.prepareFestappNetworkReload = async () => { reloads++; };
    await dom.window.retryFestappWebClient();
    assert.equal(reloads, 0);
    assert.equal(dom.window.document.querySelector('#web-client-startup button').disabled, false);
});


test('startup has an accessible spinner without visible loading text', t => {
    const { dom } = boot();
    t.after(() => dom.window.close());
    const fallback = dom.window.document.getElementById('web-client-startup');
    assert.ok(fallback.getAttribute('aria-label'));
    assert.equal(fallback.querySelector('p').hidden, true);
    assert.ok(fallback.querySelector('.startup-spinner'));
});

test('Flutter startup browser chrome matches the visible loading background', async (t) => {
    const flutterHtml = await readFile(new URL('../../../web/index.html', import.meta.url), 'utf8');
    const dom = new JSDOM(flutterHtml, { url: 'https://app.test/', runScripts: 'outside-only' });
    dom.window.localStorage.setItem('theme', 'dark');
    dom.window.eval(dom.window.document.getElementById('festapp-startup-theme').textContent);
    t.after(() => dom.window.close());
    const { document } = dom.window;
    const loaderBackground = dom.window.getComputedStyle(document.getElementById('loader-content')).backgroundColor;
    const themeProbe = document.createElement('div');
    themeProbe.style.backgroundColor = document.querySelector('meta[name="theme-color"]').content;
    document.body.appendChild(themeProbe);
    assert.equal(dom.window.getComputedStyle(themeProbe).backgroundColor, loaderBackground);
    assert.equal(dom.window.getComputedStyle(document.body).backgroundColor, loaderBackground);
    assert.equal(document.querySelector('meta[name="color-scheme"]').content, 'dark');
});

// Exercise the production bootstrap without starting Flutter or third-party SDKs.
for (const [mode, systemDark, expected] of [
    ['light', true, 'light'], ['dark', false, 'dark'],
    ['auto', true, 'dark'], ['auto', false, 'light'],
    [null, true, 'dark'], ['invalid', false, 'light'],
]) {
    test(`Flutter loader: saved ${mode}, system dark=${systemDark}`, async t => {
        const source = await readFile(new URL('../../../web/index.html', import.meta.url), 'utf8');
        const dom = new JSDOM(source, { url: 'https://app.test/', runScripts: 'outside-only' });
        t.after(() => dom.window.close());
        const { window } = dom;
        if (mode) window.localStorage.setItem('theme', mode);
        let onSystemChange;
        const media = { matches: systemDark, addEventListener: (_, listener) => { onSystemChange = listener; } };
        window.matchMedia = () => media;
        window.eval(window.document.getElementById('festapp-startup-theme').textContent);
        const root = window.document.documentElement;
        const loader = window.document.getElementById('loader-content');
        assert.equal(root.dataset.startupTheme, expected);
        assert.equal(root.style.colorScheme, expected);
        assert.equal(window.document.querySelector('meta[name="color-scheme"]').content, expected);
        assert.equal(window.getComputedStyle(loader).backgroundColor, expected === 'light' ? 'rgb(255, 255, 255)' : 'rgb(25, 36, 59)');
        assert.equal(loader.querySelector('img').getAttribute('src'), expected === 'light' ? 'loading-animation-light.svg' : 'loading-animation.svg');
        media.matches = !systemDark;
        onSystemChange();
        assert.equal(root.dataset.startupTheme, ['light', 'dark'].includes(mode) ? mode : (media.matches ? 'dark' : 'light'));
        window.localStorage.setItem('theme', 'light');
        window.dispatchEvent(new window.StorageEvent('storage', { key: 'theme' }));
        assert.equal(root.dataset.startupTheme, 'light');
        window.__FESTAPP_APP_READY__ = true;
        window.localStorage.setItem('theme', 'dark');
        window.applyFestappStartupTheme();
        assert.equal(root.dataset.startupTheme, 'light', 'Flutter owns theme after startup');
    });
}

test('Flutter loader migrates legacy theme and tolerates blocked storage', async t => {
    const source = await readFile(new URL('../../../web/index.html', import.meta.url), 'utf8');
    const dom = new JSDOM(source, { url: 'https://app.test/', runScripts: 'outside-only' });
    t.after(() => dom.window.close());
    const { window } = dom;
    window.matchMedia = () => ({ matches: true, addEventListener() {} });
    window.localStorage.setItem('flutter.adaptive_theme_preferences', JSON.stringify(JSON.stringify({theme_mode: 0})));
    window.eval(window.document.getElementById('festapp-startup-theme').textContent);
    assert.equal(window.document.documentElement.dataset.startupTheme, 'light');
    assert.equal(window.localStorage.getItem('theme'), 'light');
    Object.defineProperty(window, 'localStorage', { get() { throw new Error('blocked'); } });
    window.applyFestappStartupTheme();
    assert.equal(window.document.documentElement.dataset.startupTheme, 'dark');
});
