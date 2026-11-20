export const sharedLocaleKey = 'flutter.locale';
export const explicitLocaleKey = 'flutter.locale.manuallySelected';
export const legacyLocaleKey = 'locale';

const languageCode = value => typeof value === 'string' ? value.toLowerCase().split(/[-_]/)[0] : null;

export function preferredBrowserLocale(languages, fallback, navigator) {
    const preferences = navigator?.languages;
    const candidates = preferences?.length ? preferences : [navigator?.language];
    return candidates.map(languageCode).find(locale => languages.includes(locale)) ?? fallback;
}

export function storedLocale(languages, legacyAutoLanguage, read) {
    let shared;
    try { shared = JSON.parse(read(sharedLocaleKey)); } catch { /* Ignore corrupt preferences. */ }
    const manuallySelected = read(explicitLocaleKey) === 'true';
    for (const candidate of [shared, read(legacyLocaleKey)]) {
        const locale = languageCode(candidate);
        if (languages.includes(locale) && (manuallySelected || locale !== legacyAutoLanguage)) return locale;
    }
    return null;
}

export function applyStartupLocale(window) {
    const {document} = window;
    const languages = document.querySelector('meta[name="festapp-supported-languages"]')?.content.split(',') ?? [];
    const legacy = document.querySelector('meta[name="festapp-legacy-auto-language"]')?.content || null;
    const fallback = languages[0] ?? document.documentElement.lang ?? 'en';
    const read = key => {
        try { return window.localStorage.getItem(key); } catch { return null; }
    };
    document.documentElement.dataset.startupLocale = storedLocale(languages, legacy, read)
        ?? preferredBrowserLocale(languages, fallback, window.navigator);
}
