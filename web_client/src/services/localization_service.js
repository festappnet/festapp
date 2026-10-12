import { browserStorage } from './browser_storage.js';
import { AppConfig } from '../app_config.js';

export class LocalizationService {
    static currentLocale = AppConfig.defaultLanguage; // Default
    static translations = {};
    static _initialization = null;

    static init() {
        if (!LocalizationService._initialization) {
            LocalizationService._initialization = LocalizationService._initialize();
        }
        return LocalizationService._initialization;
    }

    static async _initialize() {
        // 1. Load preference
        const saved = browserStorage.getItem(AppConfig.Keys.locale);
        if (saved && AppConfig.supportedLanguages.includes(saved)) {
            LocalizationService.currentLocale = saved;
        } else {
            // Auto-detect? For now default to CS as primary
            // Or prioritize browser lang if supported
             const browserLang = navigator.language.split('-')[0];
             if (AppConfig.supportedLanguages.includes(browserLang)) {
                 LocalizationService.currentLocale = browserLang;
             }
        }

        await LocalizationService.loadTranslations(LocalizationService.currentLocale);
    }

    static async loadTranslations(locale) {
        try {
            const res = await fetch(`/assets/translations/${locale}.json`);
            if (!res.ok) throw new Error('Translation not found');
            LocalizationService.translations = await res.json();
            LocalizationService.currentLocale = locale;
            browserStorage.setItem(AppConfig.Keys.locale, locale);
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
