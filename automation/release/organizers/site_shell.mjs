import fs from 'node:fs';
import {publicUrl} from './html.mjs';

const read = name => fs.readFileSync(new URL(name, import.meta.url), 'utf8').trim();
const escape = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

export const renderTopicLinks = pages => (pages ?? []).filter(page => page.id !== 'home').map(page => `<a href="${publicUrl(page.path)}">${escape(page.linkLabel ?? page.heading)}</a>`).join('');

// Both public surfaces consume these exact fragments and the organizer CSS.
export function expandSiteShell(template) {
  return template.replace('{{SITE_HEADER}}', read('site-header.html'))
    .replace('{{SITE_FOOTER}}', read('site-footer.html'));
}

export function renderSiteShell({locale, brand, contact, helpPath, helpLabel, accountHeader = false, platformUpdatesPath = null}) {
  const content = JSON.parse(read(locale === 'cs' ? 'content.json' : `content.${locale}.json`)).publicProjection;
  const tokens = {APP_NAME: brand, CONTACT_EMAIL: contact, PROVIDER_NAME: content.provider?.name ?? 'Michael Bujnovský',
    CTA_HREF: content.cta.href, EVENT_DIRECTORY_HREF: locale === 'cs' ? 'https://plesy.vstupenky.online' : '/events'};
  const render = template => template.replace(/{{([A-Z0-9_]+)}}/g, (_, key) => {
    if (key === 'PLATFORM_UPDATES_LINK') return platformUpdatesPath ? `<a href="${escape(platformUpdatesPath)}">${locale==='cs'?'Co je nového':'What&#39;s new'}</a>` : '';
    if (key === 'TOPIC_LINKS') return renderTopicLinks(content.pages);
    if (key === 'HELP_LINK') return `<a class="header-help" href="${escape(helpPath)}">${escape(helpLabel)}</a>`;
    if (key in tokens) return escape(tokens[key]);
    if (!(key in content.page)) throw new Error(`Unknown public shell token: ${key}`);
    return escape(content.page[key].replace(/{{([A-Z0-9_]+)}}/g, (_, nested) => {
      if (!(nested in tokens)) throw new Error(`Unknown public shell value: ${nested}`);
      return tokens[nested];
    }));
  });
  const header = render(read('site-header.html'));
  return {header: accountHeader ? header : header.replace(' auth-pending', ''), footer: render(read('site-footer.html'))};
}

// Resolve the shared preference before stylesheets or page content can paint.
// Storage can be unavailable in restricted browsers; auto still follows the OS.
export const publicThemeHead = `<script>(()=>{let mode;try{mode=localStorage.getItem('theme')}catch{}document.documentElement.style.colorScheme=mode==='light'||mode==='dark'?mode:matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'})()</script>`;
export const publicThemeBody = `<script>document.body.classList.toggle('dark-mode',document.documentElement.style.colorScheme==='dark');document.body.dataset.publicTheme='initialized';document.body.style.colorScheme=document.documentElement.style.colorScheme;</script>`;
