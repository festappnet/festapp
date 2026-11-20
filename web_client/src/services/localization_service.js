import { browserStorage } from './browser_storage.js';
import { AppConfig } from '../app_config.js';

// EasyLocalization/SharedPreferences encodes its browser value as JSON.
const sharedLocaleKey = 'flutter.locale';
const explicitLocaleKey = 'flutter.locale.manuallySelected';
const languageCode = value => typeof value === 'string' ? value.toLowerCase().split(/[-_]/)[0] : null;
const supportedLanguage = locale => AppConfig.supportedLanguages.includes(locale);

function browserLocale() {
    const preferences = globalThis.navigator?.languages;
    const candidates = preferences?.length ? preferences : [globalThis.navigator?.language];
    return candidates.map(languageCode).find(supportedLanguage) ?? AppConfig.defaultLanguage;
}

function saveLocale(locale) {
    browserStorage.setItem(sharedLocaleKey, JSON.stringify(locale));
    browserStorage.removeItem(AppConfig.Keys.locale);
}
// Public documents are published in these languages independently of the
// tenant's application language selector. They never persist a preference.
const publicDocumentLocales = ['cs', 'en'];
const supportsLocale = (locale, persist) => AppConfig.supportedLanguages.includes(locale)
    || (persist === false && publicDocumentLocales.includes(locale));
function savedLocale() {
    let shared;
    try { shared = JSON.parse(browserStorage.getItem(sharedLocaleKey)); } catch { /* Ignore corrupt preferences. */ }
    const manuallySelected = browserStorage.getItem(explicitLocaleKey) === 'true';
    for (const candidate of [shared, browserStorage.getItem(AppConfig.Keys.locale)]) {
        const locale = languageCode(candidate);
        if (supportedLanguage(locale) && (manuallySelected || locale !== AppConfig.legacyAutoLanguage)) return locale;
    }
    return null;
}

async function loadCatalog(locale) {
    const res = await fetch(`/assets/translations/${locale}.json`);
    if (!res.ok) throw new Error('Translation not found');
    return res.json();
}

function lookup(catalog, key) {
    let value = Object.hasOwn(catalog, key) ? catalog[key] : undefined;
    if (!value) {
        value = catalog;
        for (const part of key.split('.')) {
            if (!value || !Object.hasOwn(value, part)) return undefined;
            value = value[part];
        }
    }
    return value && value !== key ? value : undefined;
}

export class LocalizationService {
    static currentLocale = AppConfig.defaultLanguage; // Default
    static translations = {};
    static fallbackTranslations = {};
    static _initialization = null;

    static init({locale, persist = true} = {}) {
        if (!LocalizationService._initialization) {
            LocalizationService._initialization = LocalizationService._initialize({locale, persist});
        }
        return LocalizationService._initialization;
    }

    static async _initialize({locale, persist = true} = {}) {
        const saved = savedLocale();
        if (locale !== undefined && !supportsLocale(locale, persist)) throw new Error('Unsupported document locale');
        const selected = locale ?? saved ?? browserLocale();
        await LocalizationService.loadTranslations(selected, {persist, save: persist && locale === undefined && saved !== null});
        if (persist) LocalizationService._startPreferenceSync();
    }

    static _startPreferenceSync() {
        if (LocalizationService._stopPreferenceSync || !globalThis.window?.addEventListener) return;
        const sync = () => {
            const locale = savedLocale();
            if (locale && locale !== LocalizationService.currentLocale) window.location.reload();
        };
        const storage = event => {
            if ([sharedLocaleKey, explicitLocaleKey, AppConfig.Keys.locale, null].includes(event.key)) sync();
        };
        window.addEventListener('storage', storage);
        window.addEventListener('focus', sync);
        window.addEventListener('pageshow', sync);
        LocalizationService._stopPreferenceSync = () => {
            window.removeEventListener('storage', storage);
            window.removeEventListener('focus', sync);
            window.removeEventListener('pageshow', sync);
            LocalizationService._stopPreferenceSync = null;
        };
    }

    static async loadTranslations(locale, {persist = true, save = persist} = {}) {
        if (!supportsLocale(locale, persist)) throw new Error('Unsupported locale');
        const defaultLocale = AppConfig.defaultLanguage;
        const fallback = persist && locale !== defaultLocale ? loadCatalog(defaultLocale) : null;
        const [primary, secondary] = await Promise.allSettled([loadCatalog(locale), fallback]);
        const defaultCatalog = secondary.status === 'fulfilled' ? secondary.value : null;
        if (primary.status === 'rejected' && defaultCatalog === null) {
            console.error('Failed to load translations', primary.reason);
            return false;
        }
        const selected = primary.status === 'fulfilled';
        LocalizationService.translations = selected ? primary.value : defaultCatalog;
        LocalizationService.fallbackTranslations = selected ? defaultCatalog ?? {} : {};
        LocalizationService.currentLocale = selected ? locale : defaultLocale;
        if (save && selected) saveLocale(locale);
        document.documentElement.lang = LocalizationService.currentLocale;
        return selected;
    }

    static tr(key, args = {}, fallback = key) {
        const preferred = lookup(LocalizationService.translations, key);
        // Explicit fallbacks also let callers probe for a locale-specific wording variant.
        const defaultText = preferred === undefined && fallback === key
            ? lookup(LocalizationService.fallbackTranslations, key)
            : undefined;
        const value = preferred ?? defaultText;
        if (value === undefined) return fallback;

        // Simple interpolation for named arguments: {name}
        if (typeof value === 'string') {
            let text = value;
            for (const [argKey, argValue] of Object.entries(args)) {
                text = text.replace(`{${argKey}}`, argValue);
            }
            return text;
        }
        
        return value;
    }

    static async setLocale(locale) {
        if (await LocalizationService.loadTranslations(locale, {save: false})) {
            browserStorage.setItem(explicitLocaleKey, 'true');
            saveLocale(locale);
            window.location.reload();
        }
    }
}
