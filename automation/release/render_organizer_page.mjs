import { renderLandingContent } from './organizers/render_content.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const configArg = process.argv.indexOf('--config');
const configPath = path.resolve(configArg < 0 ? 'automation/project.conf' : process.argv[configArg + 1]);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const config = fs.readFileSync(configPath, 'utf8');
const value = key => (config.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1] || '').trim().replace(/^(['"])(.*)\1$/, '$2');
const enabled = value('DOMAIN') === 'vstupenky.online';
const contentData = enabled ? JSON.parse(fs.readFileSync(path.join(root, 'automation/release/organizers/content.json'), 'utf8')) : null;
const seo = contentData?.publicProjection?.seo;
const jsonScript = value => JSON.stringify(value).replace(/</g, '\\u003c');
const outputArg = process.argv.indexOf('--output');
const target = outputArg < 0 ? path.join(root, 'web/organizers-page') : path.resolve(process.argv[outputArg + 1]);
const index = path.join(root, 'web_client/index.html');
if (fs.existsSync(index)) {
  const canonical = new URL(enabled ? '/events' : '/', value('WEB_LINK')).href;
  const html = fs.readFileSync(index, 'utf8')
    .replace(/(<link[^>]*rel="canonical"[^>]*href=")[^"]*/i, (_, prefix) => prefix + canonical)
    .replace(/(<meta[^>]*property="(?:og:url|twitter:url)"[^>]*content=")[^"]*/gi, (_, prefix) => prefix + canonical);
  const nav = enabled ? '\n            <nav class="catalog-navigation" aria-label="Hlavní navigace"><a href="/">Pro pořadatele</a></nav>\n            ' : '\n            ';
  let catalog = html.replace(/(<!-- ORGANIZERS_NAV_START -->)[\s\S]*?(<!-- ORGANIZERS_NAV_END -->)/, (_, start, end) => start + nav + end);
  if (enabled && seo) {
    const esc = text => String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    catalog = catalog.replace(/<title>.*?<\/title>/s, () => `<title>${esc(seo.catalogTitle)}</title>`)
      .replace(/(<meta[^>]*(?:name="description"|property="(?:og:description|twitter:description)")[^>]*content=")[^"]*/g, (_, prefix) => prefix + esc(seo.catalogDescription))
      .replace(/(<meta[^>]*property="(?:og:title|twitter:title)"[^>]*content=")[^"]*/g, (_, prefix) => prefix + esc(seo.catalogTitle))
      .replace(/<script type="application\/ld\+json">[\s\S]*?<\/script>/, () => `<script type="application/ld+json">${jsonScript({
        '@context':'https://schema.org', '@type':'WebSite', name:seo.siteName, url:new URL('/', value('WEB_LINK')).href,
      })}</script>`);
  }
  fs.writeFileSync(index, catalog);
}
if (!enabled) {
  fs.rmSync(target, { force: true });
  console.log('Organizer page disabled for this tenant.');
  process.exit(0);
}
const origin = new URL(value('WEB_LINK'));
if (origin.href !== 'https://vstupenky.online/') throw new Error('Organizer page requires the vstupenky.online HTTPS apex');
const escape = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
const tokens = {
  APP_NAME: value('APP_NAME'), CONTACT_EMAIL: 'info@festapp.net', PROVIDER_NAME: 'Michael Bujnovský',
  CTA_HREF: '/login', CTA_LABEL: 'Založit akci',
  CTA_NOTE: 'K založení akce potřebujete účet. Pokračujte přihlášením do administrace.',
};
tokens.CONTACT_EMAIL = contentData.publicProjection?.contact || tokens.CONTACT_EMAIL;
const clipsData = JSON.parse(fs.readFileSync(path.join(root, 'automation/release/organizers/clips.json'), 'utf8'));
const richTokens = renderLandingContent(contentData, clipsData);
const content = fs.readFileSync(path.join(root, 'automation/release/organizers/page.html'), 'utf8').replace(/{{([A-Z_]+)}}/g, (_, key) => {
  if (key in richTokens) return richTokens[key];
  if (!(key in tokens)) throw new Error(`Unknown organizer token ${key}`);
  return escape(tokens[key]);
});
const css = fs.readFileSync(path.join(root, 'automation/release/organizers/page.css'), 'utf8');
const primary = /^#[0-9a-f]{6}$/i.test(value('THEME_SEED_3')) ? value('THEME_SEED_3') : '#4465a6';
const title = seo.title;
const description = seo.description;
const canonical = origin.origin + '/';
const socialImage = new URL(seo.image, canonical).href;
const structured = {
  '@context': 'https://schema.org',
  '@graph': [
    {'@type':'WebSite', '@id':canonical+'#website', url:canonical, name:seo.siteName,
      alternateName:'Vstupenky online', inLanguage:'cs-CZ', publisher:{'@id':canonical+'#provider'}},
    {'@type':'WebPage', '@id':canonical+'#webpage', url:canonical, name:title, description,
      inLanguage:'cs-CZ', isPartOf:{'@id':canonical+'#website'}, mainEntity:{'@id':canonical+'#service'}},
    {'@type':'Service', '@id':canonical+'#service', url:canonical, name:'Prodej vstupenek na akce',
      serviceType:'Prodej vstupenek a správa akcí', description, provider:{'@id':canonical+'#provider'}},
    {'@type':'Person', '@id':canonical+'#provider', name:tokens.PROVIDER_NAME,
      url:canonical, email:tokens.CONTACT_EMAIL, identifier:{'@type':'PropertyValue', propertyID:'IČO', value:'06455361'}},
  ],
};
const builtIndexArg = process.argv.indexOf('--built-index');
let themeLinks = '';
let entryScript = '';
if (builtIndexArg >= 0) {
  const manifestPath = path.join(path.dirname(path.resolve(process.argv[builtIndexArg + 1])), '.vite/manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const entry = manifest['src/marketing/landing.js'];
  if (!entry?.file) throw new Error('Built organizer page needs the Vite landing entry');
  entryScript = `<script type="module" src="/${escape(entry.file)}"></script>`;
  const builtIndex = fs.readFileSync(path.resolve(process.argv[builtIndexArg + 1]), 'utf8');
  themeLinks = (builtIndex.match(/<link[^>]*rel="stylesheet"[^>]*>/g) || [])
    .filter(tag => /href="\/web-assets\/[^"]+\.css"/.test(tag)).join('');
  if (!themeLinks) throw new Error('Built organizer page needs the existing Vite theme stylesheet');
}
const html = `<!doctype html><html lang="cs"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><meta name="color-scheme" content="light">
<title>${escape(title)}</title><meta name="description" content="${escape(description)}">
<meta name="robots" content="index,follow,max-image-preview:large"><link rel="canonical" href="${canonical}">
<meta property="og:type" content="website"><meta property="og:locale" content="cs_CZ"><meta property="og:site_name" content="${escape(seo.siteName)}">
<meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(description)}"><meta property="og:url" content="${canonical}">
<meta property="og:image" content="${socialImage}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="${escape(seo.imageAlt)}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${escape(title)}"><meta name="twitter:description" content="${escape(description)}"><meta name="twitter:image" content="${socialImage}"><meta name="twitter:image:alt" content="${escape(seo.imageAlt)}">
<script type="application/ld+json">${jsonScript(structured)}</script>
<link rel="icon" href="/favicon.ico">${themeLinks}<style>:root{--primary-color:${primary}}${css}</style></head><body>${content}${entryScript}</body></html>\n`;

fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, html);
console.log('Rendered organizer page for vstupenky.online.');
