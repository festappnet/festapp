import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { AppConfig } from '../../src/app_config.js';
import { LocalizationService } from '../../src/services/localization_service.js';

function fixture(t, catalogs = {}, navigator = {language: 'cs-CZ'}) {
    const dom = new JSDOM('<!doctype html><html lang="cs"><body></body></html>', {url: 'https://fixture.invalid'});
    const previous = Object.fromEntries(['window', 'document', 'navigator', 'localStorage'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
    let reloads = 0;
    const window = {
        addEventListener: dom.window.addEventListener.bind(dom.window),
        removeEventListener: dom.window.removeEventListener.bind(dom.window),
        location: {reload: () => reloads++},
    };
    for (const [key, value] of Object.entries({window, document: dom.window.document, navigator, localStorage: dom.window.localStorage})) {
        Object.defineProperty(globalThis, key, {configurable: true, value});
    }
    LocalizationService._initialization = null;
    LocalizationService.currentLocale = 'cs';
    t.mock.method(globalThis, 'fetch', async url =>
        catalogs[url] === null ? new Response(null, {status: 404}) : Response.json(catalogs[url] ?? {label: 'translated'}));
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

test('a partial catalog uses the default without overriding available text or optional variants', async t => {
    const base = AppConfig.defaultLanguage;
    const selected = AppConfig.supportedLanguages.find(locale => locale !== base);
    fixture(t, {
        [`/assets/translations/${base}.json`]: {Form: {label: 'Default', help: 'Hello {name}', optional: 'Default variant'}},
        [`/assets/translations/${selected}.json`]: {Form: {label: 'Localized'}},
    });
    await LocalizationService.init({locale: selected});
    assert.equal(document.documentElement.lang, selected);
    assert.equal(LocalizationService.tr('Form.label'), 'Localized');
    assert.equal(LocalizationService.tr('Form.help', {name: 'Alex'}), 'Hello Alex');
    assert.equal(LocalizationService.tr('Form.optional', {}, null), null);
});

function slovakPortal(t) {
    const previous = {languages: AppConfig.supportedLanguages, fallback: AppConfig.defaultLanguage, legacy: AppConfig.legacyAutoLanguage};
    AppConfig.supportedLanguages = ['cs', 'sk'];
    AppConfig.defaultLanguage = 'cs';
    AppConfig.legacyAutoLanguage = 'cs';
    t.after(() => {
        AppConfig.supportedLanguages = previous.languages;
        AppConfig.defaultLanguage = previous.fallback;
        AppConfig.legacyAutoLanguage = previous.legacy;
    });
}

test('regional portal uses the first supported browser language without persisting auto detection', async t => {
    slovakPortal(t);
    fixture(t, {}, {language: 'en-US', languages: ['en-US', 'sk-SK', 'cs-CZ']});
    localStorage.setItem('flutter.locale', '"cs"');
    await LocalizationService.init();
    assert.equal(document.documentElement.lang, 'sk');
    localStorage.clear();
    LocalizationService._initialization = null;
    await LocalizationService.init();
    assert.equal(localStorage.getItem('flutter.locale'), null);
});

test('regional portal honors manual Czech on a Slovak browser', async t => {
    slovakPortal(t);
    const f = fixture(t, {}, {language: 'sk-SK', languages: ['sk-SK', 'cs-CZ']});
    await LocalizationService.init();
    await LocalizationService.setLocale('cs');
    assert.equal(f.reloads(), 1);
    assert.equal(localStorage.getItem('flutter.locale.manuallySelected'), 'true');
    LocalizationService._initialization = null;
    await LocalizationService.init();
    assert.equal(document.documentElement.lang, 'cs');
});

test('regional portal falls back to Czech for unsupported browsers or an unavailable Slovak catalog', async t => {
    slovakPortal(t);
    const preferences = {language: 'fr-FR', languages: ['fr-FR', 'en-US']};
    fixture(t, {'/assets/translations/sk.json': null}, preferences);
    await LocalizationService.init();
    assert.equal(document.documentElement.lang, 'cs');
    preferences.languages = ['sk-SK'];
    LocalizationService._initialization = null;
    await LocalizationService.init();
    assert.equal(document.documentElement.lang, 'cs');
    assert.equal(localStorage.getItem('flutter.locale'), null);
});
