import { browserStorage } from './browser_storage.js';
import { AppConfig } from '../app_config.js';

// EasyLocalization/SharedPreferences encodes its browser value as JSON.
const sharedLocaleKey = 'flutter.locale';
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

export class LocalizationService {
    static currentLocale = AppConfig.defaultLanguage; // Default
    static translations = {};
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
            if (!AppConfig.supportedLanguages.includes(locale)) throw new Error('Unsupported document locale');
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
        if (!AppConfig.supportedLanguages.includes(locale)) throw new Error('Unsupported locale');
        try {
            const res = await fetch(`/assets/translations/${locale}.json`);
            if (!res.ok) throw new Error('Translation not found');
            LocalizationService.translations = await res.json();
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
        // 0. Try direct lookup first (for keys with dots like "Some sentence.")
        let value = LocalizationService.translations[key];

        if (!value) {
            // 1. Traverse hierarchy if direct lookup failed
            const keys = key.split('.');
            value = LocalizationService.translations;
            
            for (const k of keys) {
                if (value && value[k]) {
                    value = value[k];
                } else {
                    return fallback; // Key not found
                }
            }
        }

        // Some legacy translation payloads contain the internal key as their
        // value. Treat that as untranslated so callers with a user-facing
        // fallback never render implementation identifiers.
        if (value === key) return fallback;

        
        // Simple interpolation for named arguments: {name}
        if (typeof value === 'string') {
            for (const [argKey, argValue] of Object.entries(args)) {
                value = value.replace(`{${argKey}}`, argValue);
            }
        }
        
        return value;
    }

    static async setLocale(locale) {
        await LocalizationService.loadTranslations(locale);
        // Reload page to re-render everything with new strings
        window.location.reload();
    }
}
