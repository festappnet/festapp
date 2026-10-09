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
