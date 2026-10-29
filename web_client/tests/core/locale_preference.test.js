import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { LocalizationService } from '../../src/services/localization_service.js';

function fixture(t) {
    const dom = new JSDOM('<!doctype html><html lang="cs"><body></body></html>', {url: 'https://fixture.invalid'});
    const previous = Object.fromEntries(['window', 'document', 'navigator', 'localStorage'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
    let reloads = 0;
    const window = {
        addEventListener: dom.window.addEventListener.bind(dom.window),
        removeEventListener: dom.window.removeEventListener.bind(dom.window),
        location: {reload: () => reloads++},
    };
    for (const [key, value] of Object.entries({window, document: dom.window.document, navigator: {language: 'cs-CZ'}, localStorage: dom.window.localStorage})) {
        Object.defineProperty(globalThis, key, {configurable: true, value});
    }
    LocalizationService._initialization = null;
    LocalizationService.currentLocale = 'cs';
    t.mock.method(globalThis, 'fetch', async () => Response.json({label: 'translated'}));
    t.after(() => {
        LocalizationService._stopPreferenceSync?.();
        LocalizationService._initialization = null;
        dom.window.close();
        for (const [key, descriptor] of Object.entries(previous)) {
            if (descriptor) Object.defineProperty(globalThis, key, descriptor);
            else delete globalThis[key];
        }
    });
    return {dom, reloads: () => reloads};
}

test('public client inherits the actual Flutter locale encoding over an older public choice', async t => {
    fixture(t);
    localStorage.setItem('locale', 'cs');
    localStorage.setItem('flutter.locale', JSON.stringify('en'));
    await LocalizationService.init();
    assert.equal(LocalizationService.currentLocale, 'en');
    assert.equal(document.documentElement.lang, 'en');
});

test('public locale selection writes the value Flutter reads at startup', async t => {
    const f = fixture(t);
    await LocalizationService.init();
    await LocalizationService.setLocale('en');
    assert.equal(JSON.parse(localStorage.getItem('flutter.locale')), 'en');
    assert.equal(f.reloads(), 1);
});

test('already open public tabs adopt Flutter locale changes on storage and resume', async t => {
    const f = fixture(t);
    localStorage.setItem('flutter.locale', JSON.stringify('cs'));
    await LocalizationService.init();
    localStorage.setItem('flutter.locale', JSON.stringify('en'));
    f.dom.window.dispatchEvent(new f.dom.window.StorageEvent('storage', {key: 'flutter.locale'}));
    assert.equal(f.reloads(), 1);
    LocalizationService.currentLocale = 'en';
    f.dom.window.dispatchEvent(new f.dom.window.Event('focus'));
    assert.equal(f.reloads(), 1, 'unchanged settings must not reload');
    localStorage.setItem('flutter.locale', JSON.stringify('cs'));
    f.dom.window.dispatchEvent(new f.dom.window.PageTransitionEvent('pageshow', {persisted: true}));
    assert.equal(f.reloads(), 2);
});

test('legacy public choice migrates and malformed shared data does not block startup', async t => {
    fixture(t);
    localStorage.setItem('flutter.locale', '{broken');
    localStorage.setItem('locale', 'en');
    await LocalizationService.init();
    assert.equal(LocalizationService.currentLocale, 'en');
    assert.equal(JSON.parse(localStorage.getItem('flutter.locale')), 'en');
});

test('explicit marketing document locale does not replace the shared choice or reload', async t => {
    const f = fixture(t);
    localStorage.setItem('flutter.locale', JSON.stringify('en'));
    await LocalizationService.init({locale: 'cs', persist: false});
    assert.equal(LocalizationService.currentLocale, 'cs');
    assert.equal(JSON.parse(localStorage.getItem('flutter.locale')), 'en');
    localStorage.setItem('flutter.locale', JSON.stringify('sk'));
    f.dom.window.dispatchEvent(new f.dom.window.StorageEvent('storage', {key: 'flutter.locale'}));
    assert.equal(f.reloads(), 0);
});
