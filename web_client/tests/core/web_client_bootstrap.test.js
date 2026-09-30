import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { JSDOM } from 'jsdom';

const html = await readFile(new URL('../../index.html', import.meta.url), 'utf8');

function boot() {
    const reports = [];
    const serviceWorker = new EventTarget();
    serviceWorker.controller = { postMessage: (message) => reports.push(message) };
    serviceWorker.ready = Promise.resolve();
    const dom = new JSDOM(html, {
        url: 'https://app.test/',
        runScripts: 'dangerously',
        beforeParse(window) {
            Object.defineProperty(window.navigator, 'serviceWorker', { value: serviceWorker });
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
