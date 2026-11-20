import fs from 'node:fs';
import {escape} from './html.mjs';

export const localizedAssets = '/_localized';

export function documentLocales(config, profiles = JSON.parse(fs.readFileSync(new URL('profiles.json', import.meta.url), 'utf8'))) {
  const supported = (config.WEB_SUPPORTED_LANGUAGES ?? '').split(',').map(locale => locale.trim());
  const primary = profiles[config.WEB_ORGANIZER_CONTENT_PROFILE];
  const alternatives = config.WEB_ORGANIZER_LANDING_ENABLED === 'true' ? primary?.translations ?? {} : {};
  return [supported[0] || 'cs', ...Object.entries(alternatives)
    .filter(([locale, profile]) => locale !== supported[0] && /^[a-z]{2}$/.test(locale)
      && supported.includes(locale) && profiles[profile]?.locale === locale)
    .map(([locale]) => locale)];
}

export function publicLanguageUrl(href, locale, defaultLocale) {
  const url = new URL(href, 'https://public.invalid');
  if (locale === defaultLocale) url.searchParams.delete('lang');
  else url.searchParams.set('lang', locale);
  return url.pathname + url.search + url.hash;
}

export function publicAlternates(origin, href, locales) {
  return locales.map(locale => {
    const url = new URL(publicLanguageUrl(href, locale, locales[0]), origin);
    return `<link rel="alternate" hreflang="${locale}" href="${escape(url.href)}">`;
  }).join('');
}

export function publicLanguageSwitch(href, current, locales) {
  const label = current === 'en' ? 'Page language' : 'Jazyk stránky';
  return `<nav class="public-language-switch wrap" aria-label="${label}">${locales.map(locale => {
    const nativeName = new Intl.DisplayNames([locale], {type:'language'}).of(locale);
    const name = nativeName.charAt(0).toLocaleUpperCase(locale) + nativeName.slice(1);
    const url = new URL(href, 'https://public.invalid');
    url.searchParams.set('lang', locale);
    return `<a href="${escape(url.pathname + url.search)}" lang="${locale}" hreflang="${locale}" data-public-language="${locale}"${locale === current ? ' aria-current="page"' : ''}>${escape(name)}</a>`;
  }).join(' ')}</nav>`;
}

export function publicDocumentLinks(html, locale, defaultLocale, helpRoot) {
  return html.replace(/(<a\b[^>]*\bhref=")(\/(?!\/)[^"]*)"/gi, (match, start, href) => {
    const url = new URL(href.replaceAll('&amp;', '&'), 'https://public.invalid');
    if (url.pathname !== '/' && url.pathname !== '/events' && url.pathname !== '/login'
        && !(url.pathname.startsWith(helpRoot) && !url.pathname.startsWith(helpRoot + 'assets/'))) return match;
    // Help actions are canonical application intents with an exact query shape.
    if (url.searchParams.has('lang') || (url.pathname === '/events' && url.searchParams.has('help'))) return match;
    return start + escape(publicLanguageUrl(url.pathname + url.search + url.hash, locale, defaultLocale)) + '"';
  });
}
