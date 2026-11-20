import { browserStorage } from '../services/browser_storage.js';
import { explicitLocaleKey, legacyLocaleKey, sharedLocaleKey, storedLocale } from '../runtime/locale_preference.js';

export function initPublicLanguage(win = window, storage = browserStorage) {
    const {document} = win;
    const choices = [...document.querySelectorAll('a[data-public-language]')].map(link => link.dataset.publicLanguage);
    if (!choices.length) return false;

    const current = new URL(win.location.href);
    if (!current.searchParams.has('lang') && storage.getItem(explicitLocaleKey) === 'true') {
        const preferred = storedLocale(choices, null, storage.getItem);
        if (preferred && preferred !== document.documentElement.lang) {
            current.searchParams.set('lang', preferred);
            win.location.replace(current.href);
            return true;
        }
    }

    document.addEventListener('click', event => {
        const link = event.target.closest?.('a[data-public-language]');
        if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        const locale = link.dataset.publicLanguage;
        const current = new URL(win.location.href);
        if (current.pathname === new URL(link.href).pathname) {
            current.searchParams.set('lang', locale);
            link.href = current.href;
        }
        storage.setItem(sharedLocaleKey, JSON.stringify(locale));
        storage.setItem(explicitLocaleKey, 'true');
        storage.removeItem(legacyLocaleKey);
    });
    return false;
}
