import { browserStorage } from './browser_storage.js';
import { AppConfig } from '../app_config.js';

// EasyLocalization/SharedPreferences encodes its browser value as JSON.
const sharedLocaleKey = 'flutter.locale';
// Public documents are published in these languages independently of the
// tenant's application language selector. They never persist a preference.
const publicDocumentLocales = ['cs', 'en'];
const supportsLocale = (locale, persist) => AppConfig.supportedLanguages.includes(locale)
    || (persist === false && publicDocumentLocales.includes(locale));
function savedLocale() {
    let shared;
    try { shared = JSON.parse(browserStorage.getItem(sharedLocaleKey)); } catch { /* Ignore corrupt preferences. */ }
    const normalize = value => typeof value === 'string' ? value.toLowerCase().split(/[-_]/)[0] : null;
    for (const candidate of [shared, browserStorage.getItem(AppConfig.Keys.locale)]) {
        const locale = normalize(candidate);
        if (AppConfig.supportedLanguages.includes(locale)) return locale;
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
        // 1. Load preference
        const saved = savedLocale();
        if (locale !== undefined) {
            if (!supportsLocale(locale, persist)) throw new Error('Unsupported document locale');
            LocalizationService.currentLocale = locale;
        } else if (saved && AppConfig.supportedLanguages.includes(saved)) {
            LocalizationService.currentLocale = saved;
        } else {
            // Auto-detect? For now default to CS as primary
            // Or prioritize browser lang if supported
             const browserLang = navigator.language.split('-')[0];
             if (AppConfig.supportedLanguages.includes(browserLang)) {
                 LocalizationService.currentLocale = browserLang;
             }
        }

        await LocalizationService.loadTranslations(LocalizationService.currentLocale, {persist});
        if (persist) LocalizationService._startPreferenceSync();
    }

    static _startPreferenceSync() {
        if (LocalizationService._stopPreferenceSync || !globalThis.window?.addEventListener) return;
        const sync = () => {
            const locale = savedLocale();
            if (locale && locale !== LocalizationService.currentLocale) window.location.reload();
        };
        const storage = event => {
            if (event.key === sharedLocaleKey || event.key === AppConfig.Keys.locale || event.key === null) sync();
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

    static async loadTranslations(locale, {persist = true} = {}) {
        if (!supportsLocale(locale, persist)) throw new Error('Unsupported locale');
        try {
            const fallback = persist && locale !== AppConfig.defaultLanguage
                ? loadCatalog(AppConfig.defaultLanguage).catch(() => ({}))
                : {};
            const [translations, fallbackTranslations] = await Promise.all([loadCatalog(locale), fallback]);
            LocalizationService.translations = translations;
            LocalizationService.fallbackTranslations = fallbackTranslations;
            LocalizationService.currentLocale = locale;
            if (persist) {
                browserStorage.setItem(sharedLocaleKey, JSON.stringify(locale));
                browserStorage.removeItem(AppConfig.Keys.locale);
            }
            document.documentElement.lang = locale;
        } catch (e) {
            console.error("Failed to load translations", e);
        }
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
        await LocalizationService.loadTranslations(locale);
        // Reload page to re-render everything with new strings
        window.location.reload();
    }
}
