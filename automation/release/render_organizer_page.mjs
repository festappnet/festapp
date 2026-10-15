import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const configArg = process.argv.indexOf('--config');
const configPath = path.resolve(configArg < 0 ? 'automation/project.conf' : process.argv[configArg + 1]);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const config = fs.readFileSync(configPath, 'utf8');
const value = key => (config.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1] || '').trim().replace(/^(['"])(.*)\1$/, '$2');
const enabled = value('DOMAIN') === 'vstupenky.online';
const outputArg = process.argv.indexOf('--output');
const target = outputArg < 0 ? path.join(root, 'web/organizers-page') : path.resolve(process.argv[outputArg + 1]);
const index = path.join(root, 'web_client/index.html');
if (fs.existsSync(index)) {
  const html = fs.readFileSync(index, 'utf8');
  const nav = enabled ? '\n            <nav class="catalog-navigation" aria-label="Pro pořadatele"><a href="/pro-poradatele">Pro pořadatele</a></nav>\n            ' : '\n            ';
  fs.writeFileSync(index, html.replace(/(<!-- ORGANIZERS_NAV_START -->)[\s\S]*?(<!-- ORGANIZERS_NAV_END -->)/, (_, start, end) => start + nav + end));
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
  CTA_HREF: '/?create=1', CTA_LABEL: 'Založit akci',
  CTA_NOTE: 'Začněte vytvořením účtu, nebo pokračujte do správy svých akcí.',
};
const content = fs.readFileSync(path.join(root, 'automation/release/organizers/page.html'), 'utf8').replace(/{{([A-Z_]+)}}/g, (_, key) => {
  if (!(key in tokens)) throw new Error(`Unknown organizer token ${key}`);
  return escape(tokens[key]);
});
const css = fs.readFileSync(path.join(root, 'automation/release/organizers/page.css'), 'utf8');
const title = 'Prodej vstupenek a registrace na akce | ' + tokens.APP_NAME;
const description = 'Informace pro pořadatele: založení akce, správa objednávek, vstupenky a odbavení. Jak začít se službou vstupenky.online a kde zjistit cenu.';
const builtIndexArg = process.argv.indexOf('--built-index');
let themeLinks = '';
let bootstrap = '';
let moduleEntry = '';
if (builtIndexArg >= 0) {
  const builtIndex = fs.readFileSync(path.resolve(process.argv[builtIndexArg + 1]), 'utf8');
  themeLinks = (builtIndex.match(/<link[^>]*rel="stylesheet"[^>]*>/g) || [])
    .filter(tag => /href="\/web-assets\/[^"]+\.css"/.test(tag)).join('');
  if (!themeLinks) throw new Error('Built organizer page needs the existing Vite theme stylesheet');
  moduleEntry = (builtIndex.match(/<script\b[^>]*type="module"[^>]*src="\/web-assets\/[^"]+"[^>]*><\/script>/g) || []).join('');
  bootstrap = (builtIndex.match(/<script>[^]*?<\/script>/g) || []).find(script => script.includes('function reportFestappClientVersion()')) || '';
  themeLinks += (builtIndex.match(/<link[^>]+>/g) || []).filter(tag => tag.includes('fonts.googleapis.com')).join('');
  if (!moduleEntry || !bootstrap) throw new Error('Built organizer page needs the shared Vite entry and startup handshake');
}
const html = `<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>${escape(title)}</title><meta name="description" content="${escape(description)}"><link rel="canonical" href="${origin.origin}/pro-poradatele"><meta property="og:type" content="website"><meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(description)}"><meta property="og:url" content="${origin.origin}/pro-poradatele"><meta property="og:image" content="${origin.origin}/android-chrome-512x512.png"><meta property="twitter:card" content="summary_large_image"><meta property="twitter:title" content="${escape(title)}"><meta property="twitter:description" content="${escape(description)}"><meta property="twitter:url" content="${origin.origin}/pro-poradatele"><meta property="twitter:image" content="${origin.origin}/android-chrome-512x512.png"><link rel="icon" href="/favicon.ico">${themeLinks}${bootstrap}${moduleEntry}<style>${css}</style></head><body data-page="organizers">${content}</body></html>\n`;
fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, html);
console.log('Rendered organizer page for vstupenky.online.');
