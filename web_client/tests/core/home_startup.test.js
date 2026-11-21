import {publicCheckoutLocation} from '../../src/utils/public_form_location.js';
import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { JSDOM } from 'jsdom';

for (const failed of [false, true]) test(`Google continuation owns one dialog after URL recovery, failed=${failed}`, async t => {
    const dom = new JSDOM('<body><div id="app"><div id="events-grid"></div></div></body>', {url:'https://vstupenky.online/login?create=1'});
    t.after(() => dom.window.close());
    const views = [];
    class CallbackModal extends dom.window.HTMLElement {
        _setView(view) { views.push(view); }
        showGoogleResult(result) { views.push(result.status); }
    }
    dom.window.customElements.define('fixture-google-callback', CallbackModal);
    const source = readFileSync(new URL('../../src/main.js', import.meta.url), 'utf8')
        .replace(/^import .*;\r?\n/gm, '')
        .replace(/\/\/ Start[\s\S]*$/, 'Main.init();');
    const noop = {init() {}};
    dom.window.failFestappWebClientStartup = reason => assert.fail(reason);
    await runInNewContext(source, {
        window:dom.window, document:dom.window.document, console,
        publicCheckoutLocation, isEmbed:()=>false, applyEmbedContext() {}, resolveScannerRoute:()=>null,
        GoogleAuthService:{takeCallback:()=>({attempt:'fixture'}),complete:async()=>{
            if (failed) throw Error('provider_cancelled');
            return {status:'needs_profile'};
        }},
        LoginModal:CallbackModal,
        initializeCoreServices:async()=>{},
        handleHelpAction:async()=>assert.fail('callback owns its continuation'),
        handleOrganizerIntent:async()=>assert.fail('must not append a second registration dialog'),
        AppConfig:{organization:3}, LocalizationService:{}, SupabaseService:{}, RightsService:{},
        ThemeService:noop, ImageLoader:noop, FeedbackFab:noop,
        UnitPage:class {init() {} async loadOccasions() {}},
        RouterService:{normalizeUrl:url=>new URL(url).pathname,handleInitialLoad:async()=>false,initPopStateListener() {}},
    });
    assert.equal(dom.window.document.querySelectorAll('fixture-google-callback').length,1);
    assert.deepEqual(views,['google_completing',failed?'login':'needs_profile']);
});

test('catalogue stays hidden while cards load, then startup reveals cards', async t => {
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
    t.mock.method(DbOccasions, 'getPublicCatalogue', () => pending);
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
        publicCheckoutLocation, isEmbed: () => false, applyEmbedContext() {},
        resolveScannerRoute: () => null,
        GoogleAuthService: { takeCallback: () => null }, AuthService: { resumeVerification: async () => null },
        initializeCoreServices: async () => {},
        handleHelpAction: async () => false, handleOrganizerIntent: async () => false,
        LocalizationService: {}, SupabaseService: {}, RightsService: {},
        AppConfig: { organization: 3 },
        ThemeService: noop, ImageLoader: noop, FeedbackFab: noop,
        RouterService: { normalizeUrl: value => new URL(value).pathname, handleInitialLoad: async () => false, initPopStateListener() {} },
    });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(ready, false, 'loading cards does not prematurely mark application ready');
    assert.ok(document.querySelector('#events-grid ul'), 'server links remain in the DOM while loading');
    assert.equal(document.getElementById('app').style.display, 'none');
    deliver({ occasions: [{ title: 'Card event', start_time: '2099-01-01', end_time: '2099-01-02' }] });
    await startup;
    assert.equal(ready, true);
    assert.equal(document.getElementById('app').style.display, 'flex');
    assert.equal(document.querySelector('#events-grid ul'), null);
    assert.equal(document.querySelector('.occasion-card').textContent, 'Card event');
});


test('server catalogue stays behind startup and retains failure recovery', t => {
    const html = readFileSync(new URL('../../index.html', import.meta.url), 'utf8')
        .replace('<div id="events-grid"></div>', '<div id="events-grid" data-server-catalog="ready"><a href="/form/live">Public event</a></div>');
    const dom = new JSDOM(html, { url: 'https://vstupenky.online/', runScripts: 'dangerously' });
    t.after(() => dom.window.close());
    assert.equal(dom.window.document.querySelector('#app').style.display, 'none');
    assert.equal(dom.window.document.querySelector('#web-client-startup').style.position, 'fixed');
    assert.ok(dom.window.document.querySelector('#events-grid a'));
    dom.window.failFestappWebClientStartup('web-module-error');
    assert.equal(dom.window.document.querySelector('#app').style.display, 'none');
    assert.equal(dom.window.document.querySelector('#web-client-startup button').hidden, false);
});

for (const fails of [false, true]) test(`organizer startup preserves static content, core failure=${fails}`, async () => {
    const dom = new JSDOM('<body data-page="organizers"><main><h1>Organizers</h1></main></body>');
    const source = readFileSync(new URL('../../src/main.js', import.meta.url), 'utf8')
        .replace(/^import .*;\r?\n/gm, '')
        .replace(/\/\/ Start[\s\S]*$/, 'Main.init();');
    let initializations = 0;
    let themes = 0;
    let ready = 0;
    dom.window.markFestappAppReady = () => ready++;
    await runInNewContext(source, {
        window: dom.window, document: dom.window.document, console: { error() {} },
        publicCheckoutLocation, isEmbed: () => false, applyEmbedContext() {},
        resolveScannerRoute: () => null,
        GoogleAuthService: { takeCallback: () => null }, AuthService: { resumeVerification: async () => null },
        initializeCoreServices: async options => { assert.equal(options.isAppSupported, false); initializations++; if (fails) throw Error('offline'); },
        LocalizationService: {}, SupabaseService: {}, RightsService: {}, AppConfig: { isAppSupported: true },
        ThemeService: { init() { themes++; } }, ImageLoader: { init() {} },
        handleOrganizerIntent: () => assert.fail('no creation intent on content page'),
        RouterService: { normalizeUrl: value => new URL(value).pathname, handleInitialLoad() { assert.fail('no router fallback'); } },
        UnitPage: class { constructor() { assert.fail('no catalog'); } },
    });
    assert.equal(initializations, 1);
    assert.equal(themes, 1);
    assert.equal(ready, fails ? 0 : 1);
    assert.equal(dom.window.document.querySelector('h1').textContent, 'Organizers');
    dom.window.close();
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
        publicCheckoutLocation, isEmbed: () => false, applyEmbedContext() {},
        resolveScannerRoute: () => null,
        GoogleAuthService: { takeCallback: () => null }, AuthService: { resumeVerification: async () => null },
        initializeCoreServices: async () => { initialized++; },
        handleHelpAction: async () => false, handleOrganizerIntent: async () => null,
        AppConfig: {}, ThemeService: { init() {} }, ImageLoader: { init() {} },
        RouterService: { normalizeUrl: value => value, handleInitialLoad: async () => true, initPopStateListener() {} },
        LocalizationService: {}, SupabaseService: {}, RightsService: {},
    });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(initialized, 1, 'late module must initialize services without another DOMContentLoaded');
    assert.equal(ready, 1);
});

test('a restored first factor resumes verification at the current path before navigation', async t => {
    const dom = new JSDOM('<div id="app"></div>', { url: 'https://tickets.invalid/unit/14/edit' });
    t.after(() => dom.window.close());
    const pending = { factors: [{ id: 'registered-factor' }] };
    let shown = false;
    class VerificationModal extends dom.window.HTMLElement {
        _showVerification(challenge) {
            assert.equal(challenge, pending);
            shown = true;
        }
    }
    dom.window.customElements.define('fixture-verification', VerificationModal);
    const source = readFileSync(new URL('../../src/main.js', import.meta.url), 'utf8')
        .replace(/^import .*;\r?\n/gm, '').replace(/\/\/ Start[\s\S]*$/, 'Main.init();');
    const noop = { init() {} };
    dom.window.failFestappWebClientStartup = reason => assert.fail(reason);
    await runInNewContext(source, {
        window: dom.window, document: dom.window.document, console,
        publicCheckoutLocation, isEmbed: () => false, applyEmbedContext() {}, resolveScannerRoute: () => null,
        GoogleAuthService: { takeCallback: () => null },
        AuthService: { resumeVerification: async () => pending },
        LoginModal: VerificationModal, initializeCoreServices: async () => {},
        handleHelpAction: () => assert.fail('the pending session owns the sign-in flow'),
        handleOrganizerIntent: () => assert.fail('the pending session owns the sign-in flow'),
        RouterService: {
            normalizeUrl: url => new URL(url).pathname,
            handleInitialLoad: () => assert.fail('do not navigate before verifying the factor'),
            initPopStateListener() {},
        },
        AppConfig: {}, LocalizationService: {}, SupabaseService: {}, RightsService: {},
        ThemeService: noop, ImageLoader: noop, FeedbackFab: noop,
        UnitPage: class { init() {} async loadOccasions() {} },
    });
    assert.equal(shown, true);
    assert.equal(dom.window.location.pathname, '/unit/14/edit');
});

for (const [path, deferred] of [
    ['/form/example', true], ['/form/example?utm_source=organizer', true],
    ['/form/example?embed=1', true], ['/', false], ['/events', false],
    ['/form/example#order-preview', true], [`/form/example?checkout_origin=cHJvb2Y.${'a'.repeat(64)}`, true],
    ['/form/example?checkout_origin=invalid', false],
    ['/form/example?preview=true', false], ['/form/example?admin=1', false],
    ['/form/example?order_id=1&token=private', false],
    [`/order?order_id=1&token=${'a'.repeat(64)}`, true],
    [`/order?order_id=1&token=${'a'.repeat(64)}&token=${'b'.repeat(64)}`, false],
    ['/order?waitlist=1&offer_id=00000000-0000-4000-8000-000000000001&admin=1', false],
]) test(`document startup ${path} defers catalogue context=${deferred}`, async t => {
    const {initializeCoreServices} = await import('../../src/startup/initialize_core_services.js');
    const dom = new JSDOM('<div id="app"></div>', {url: 'https://tickets.invalid' + path});
    t.after(() => dom.window.close());
    const calls = [];
    const source = readFileSync(new URL('../../src/main.js', import.meta.url), 'utf8')
        .replace(/^import .*;\r?\n/gm, '').replace(/\/\/ Start[\s\S]*$/, 'Main.init();');
    const noop = {init() {}};
    await runInNewContext(source, {
        window: dom.window, document: dom.window.document, console,
        publicCheckoutLocation, isEmbed: () => new URLSearchParams(dom.window.location.search).get('embed') === '1',
        applyEmbedContext() {}, resolveScannerRoute: () => null,
        GoogleAuthService: {takeCallback: () => null}, AuthService: {resumeVerification: async () => {
            assert.ok(!deferred, 'public checkout must route without prompting for account verification');
            return null;
        }},
        initializeCoreServices,
        LocalizationService: {init: async () => calls.push('translations')},
        SupabaseService: {initialize: async () => calls.push('backend')},
        RightsService: {updateAppData: async () => calls.push('catalogue context')},
        earlyFormLoad: {start() {calls.push('prefetch');}}, DbForms: {},
        handleHelpAction: async () => false, handleOrganizerIntent: async () => null,
        AppConfig: {isAppSupported: false}, ThemeService: noop, ImageLoader: noop,
        RouterService: {
            normalizeUrl: url => new URL(url).pathname,
            preloadForm: async () => {},
            handleInitialLoad: async () => {calls.push('route'); return true;},
            initPopStateListener() {},
        },
    });
    assert.deepEqual(calls, ['translations', 'backend', 'prefetch',
        ...(deferred ? [] : ['catalogue context']), 'route']);
});
