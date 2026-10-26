import { renderUpdate } from './platform_updates/render.mjs';
import {updatePaths} from './platform_updates/context.mjs';
import { expandSiteShell } from './organizers/site_shell.mjs';
import { renderLandingContent } from './organizers/render_content.mjs';
import { readConfig, resolveContext, publicManifest, marketingMedia } from './organizers/context.mjs';
import { pageDefinitions, retiredPageAssets } from './organizers/page_definitions.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const configArg = process.argv.indexOf('--config');
const configPath = path.resolve(configArg < 0 ? 'automation/project.conf' : process.argv[configArg + 1]);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const config = readConfig(configPath);
const value = key => config[key] ?? '';
const escape = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
const context = resolveContext(config, {preview:process.argv.includes("--preview")});
const { enabled, projection: projection = {}, clips: clipsData } = context;
const contentData = { publicProjection: projection };
const seo = projection.seo;
const jsonScript = value => JSON.stringify(value).replace(/</g, '\\u003c');
const outputArg = process.argv.indexOf('--output');
const target = outputArg < 0 ? path.join(root, 'web/organizers-page') : path.resolve(process.argv[outputArg + 1]);
const index = path.join(root, 'web_client/index.html');
let catalogOutput;
if (fs.existsSync(index)) {
  const canonical = new URL(enabled ? '/events' : '/', value('WEB_LINK')).href;
const html = fs.readFileSync(index, 'utf8')
    .replace(/(<link[^>]*rel="canonical"[^>]*href=")[^"]*/i, (_, prefix) => prefix + canonical)
    .replace(/(<meta[^>]*property="(?:og:url|twitter:url)"[^>]*content=")[^"]*/gi, (_, prefix) => prefix + canonical);
  let catalog = html;
  if (enabled && seo) {
    const esc = text => String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    catalog = catalog.replace(/<title>.*?<\/title>/s, () => `<title>${esc(seo.catalogTitle)}</title>`)
      .replace(/(<meta[^>]*(?:name="description"|property="(?:og:description|twitter:description)")[^>]*content=")[^"]*/g, (_, prefix) => prefix + esc(seo.catalogDescription))
      .replace(/(<meta[^>]*property="(?:og:title|twitter:title)"[^>]*content=")[^"]*/g, (_, prefix) => prefix + esc(seo.catalogTitle))
      .replace(/<script type="application\/ld\+json">[\s\S]*?<\/script>/, () => `<script type="application/ld+json">${jsonScript({
        '@context':'https://schema.org', '@type':'WebSite', name:seo.siteName, url:new URL('/', value('WEB_LINK')).href,
      })}</script>`);
  }
  catalogOutput = catalog.replace(/<html lang="[^"]*"/, `<html lang="${context.locale ?? 'cs'}"`);
}
const manifestPath = path.join(path.dirname(target), 'organizer-pages.json');
const cleanOutputs = () => {
  fs.rmSync(path.join(path.dirname(target),'organizers/updates'),{recursive:true,force:true});
  fs.rmSync(path.join(path.dirname(target),'platform-updates.json'),{force:true});
  if (process.argv.includes('--built-index')) fs.rmSync(path.join(path.dirname(target),'platform-updates-media'),{recursive:true,force:true});
  for (const asset of [...Object.values(pageDefinitions).map(page=>page.asset), ...retiredPageAssets]) fs.rmSync(path.join(path.dirname(target), asset.slice(1)), {force:true});
};
if (!enabled) {
  cleanOutputs();
  fs.mkdirSync(path.dirname(target), {recursive:true});
  fs.writeFileSync(manifestPath, JSON.stringify(publicManifest(context)) + '\n');
  if (catalogOutput) fs.writeFileSync(index, catalogOutput);
  console.log('Organizer pages disabled for this tenant.');
  process.exit(0);
}
const tokens = {
  ...projection.templateTexts,
  APP_NAME: value('APP_NAME'), CONTACT_EMAIL: projection.contact, PROVIDER_NAME: projection.provider.name,
  PROVIDER_IDENTIFIER: projection.provider.identifierLabel + ' ' + projection.provider.identifier,
  CTA_HREF: projection.cta.href, CTA_LABEL: projection.cta.label, CTA_NOTE: projection.cta.note,
  EVENT_DIRECTORY_HREF: projection.footerLinks?.find(link=>link.href.startsWith('https:'))?.href ?? '/events',
  HOME_LABEL: projection.ui.home, GUIDE_URL: projection.footerLinks?.find(link=>link.href.startsWith('https:'))?.href ?? '/',
  PRIVACY_URL: value('PRIVACY_URL'), TERMS_URL: value('TERMS_URL'), SUPPORT_URL: value('SUPPORT_URL'),
};
const template = expandSiteShell(fs.readFileSync(path.join(root, 'automation/release/organizers/page.html'), 'utf8'));
const css = fs.readFileSync(path.join(root, 'automation/release/organizers/page.css'), 'utf8');
const primary = /^#[0-9a-f]{6}$/i.test(value('THEME_SEED_3')) ? value('THEME_SEED_3') : '#4465a6';
const socialImage = new URL(seo.image, context.origin).href;
const outputs = [];
const updateAssets=(context.updates?.assets ?? []).map(asset=>({asset,bytes:fs.readFileSync(path.join(process.argv.includes('--built-index')?path.dirname(target):path.join(root,'web'),asset))}));
// Validate actual media bytes before accepting any generated document.
const mediaPaths = marketingMedia(context);
for (const media of process.argv.includes("--preview") ? [] : mediaPaths) {
  const url = new URL(media, context.origin);
  if (url.origin !== context.origin || !url.pathname.startsWith('/') || url.pathname.includes('..') || !fs.existsSync(path.join(process.argv.includes('--built-index') ? path.dirname(target) : path.join(root,'web'), url.pathname))) throw new Error(`Missing/foreign marketing media: ${media}`);
}
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
    .filter(tag => /href="\/web-assets\/[^"]+\.css"/.test(tag) || tag.includes("https://fonts.googleapis.com/icon?family=Material+Icons")).join('');
  if (!themeLinks) throw new Error('Built organizer page needs the existing Vite theme stylesheet');
}
  for (const page of context.pages) {
  if (page.type) {outputs.push({asset:page.asset,html:renderUpdate(page,context,{css,themeLinks,primary,entryScript})});continue;}
  const richTokens = renderLandingContent(contentData, clipsData, page, context.pages.filter(other=>!other.type));
  const substitute = text => text.replace(/{{([A-Z_0-9]+)}}/g, (_, key) => {
    if (key === 'PLATFORM_UPDATES_LINK') return context.updates ? `<a href="${updatePaths[context.locale]}">${context.locale==='cs'?'Co je nového':'What&#39;s new'}</a>` : '';
    if (key === 'HELP_LINK') return projection.helpLink ? `<a class="header-help" href="${escape(projection.helpLink.href)}">${escape(projection.helpLink.label)}</a>` : '';
    if (key in richTokens) return richTokens[key];
    if (!(key in tokens) || tokens[key] === '') throw new Error(`Missing marketing text ${key}`);
    return escape(String(tokens[key]).replace(/{{([A-Z_0-9]+)}}/g, (_, nested) => {
      if (!(nested in tokens)) throw new Error(`Unknown nested organizer token ${nested}`);
      return tokens[nested];
    }));
  });
  let body = template;
  if (projection.locale === 'cs') {
    body=body.replace(/<a href="#(?:vstupenka|vyber-mist|odbaveni)">[\s\S]*?<\/a>/g,'');
    const reference=body.match(/<section id="reference"[\s\S]*?<\/section>/)?.[0] ?? '';
    body=body.replace(reference,'').replace(/<section class="steps wrap reveal"[\s\S]*?<\/section>/,'').replace(/<section class="technical-options wrap"[\s\S]*?<\/section>/,'');
    body=body.replace(/<details><summary>{{PAGE_(?:CAN_GUESTS_CHOOSE_SPECIFIC_SEATS|WHAT_CAN_I_CUSTOMIZE|HOW_DO_I_CHECK_TICKETS_AT_THE_DOOR)}}<\/summary>[\s\S]*?<\/details>/g,'');
    body=body.replace('<section class="payments',reference+'<section class="payments');
  }

  if (!projection.references?.length) body = body.replace(/<section id="reference"[\s\S]*?<\/section>/, "");
  if (page.id !== 'home') body = body.replace(/<main id="main">[\s\S]*?<\/main>/, '<main id="main">{{TOPIC_CONTENT}}</main>');
  const content = substitute(body);
  const canonical = page.canonical, title = page.title, description = page.description;
  const home = context.origin + '/';
  const structured = {'@context':'https://schema.org', '@graph':[
    {'@type':'WebSite','@id':home+'#website',url:home,name:seo.siteName,inLanguage:projection.languageTag,publisher:{'@id':home+'#provider'}},
    {'@type':'WebPage','@id':canonical+'#webpage',url:canonical,name:title,description,inLanguage:projection.languageTag,isPartOf:{'@id':home+'#website'},mainEntity:{'@id':canonical+'#service'}},
    {'@type':'Service','@id':canonical+'#service',url:canonical,name:page.heading ?? projection.serviceName,serviceType:projection.serviceType,description,provider:{'@id':home+'#provider'}},
    {'@type':'Person','@id':home+'#provider',name:projection.provider.name,url:home,email:projection.contact,identifier:{'@type':'PropertyValue',propertyID:projection.provider.identifierLabel,value:projection.provider.identifier}},
  ]};
const html = `<!doctype html><html lang="${escape(context.locale)}"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><meta name="color-scheme" content="light dark">
<title>${escape(title)}</title><meta name="description" content="${escape(description)}">
<meta name="robots" content="index,follow,max-image-preview:large"><link rel="canonical" href="${canonical}">
<meta property="og:type" content="website"><meta property="og:locale" content="${escape(projection.ogLocale)}"><meta property="og:site_name" content="${escape(seo.siteName)}">
<meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(description)}"><meta property="og:url" content="${canonical}">
<meta property="og:image" content="${socialImage}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="${escape(seo.imageAlt)}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${escape(title)}"><meta name="twitter:description" content="${escape(description)}"><meta name="twitter:image" content="${socialImage}"><meta name="twitter:image:alt" content="${escape(seo.imageAlt)}">
<script type="application/ld+json">${jsonScript(structured)}</script>
<link rel="icon" href="/favicon.ico">${themeLinks}<style>:root{--primary-color:${primary}}${css}</style><noscript><style>.auth-pending :is(.header-signin,.header-cta){visibility:visible;pointer-events:auto}</style></noscript></head><body data-page="organizers" data-topic="${escape(page.id)}">${content}<script type="application/json" id="marketing-ui">${jsonScript(projection.ui)}</script>${entryScript}</body></html>\n`;

outputs.push({asset:page.asset, html});
}
// Complete staging first: an invalid profile never replaces part of a bundle.
fs.mkdirSync(path.dirname(target), {recursive:true});
const staging = fs.mkdtempSync(path.join(path.dirname(target), '.organizers-stage-'));
try {
  for (const output of outputs) {
    const file = path.join(staging, output.asset.slice(1));
    fs.mkdirSync(path.dirname(file), {recursive:true}); fs.writeFileSync(file, output.html);
  }
  if (context.updates) fs.writeFileSync(path.join(staging,'platform-updates.json'),JSON.stringify(context.updates.feed)+'\n');
  cleanOutputs();
  if (context.updates) fs.renameSync(path.join(staging,'platform-updates.json'),path.join(path.dirname(target),'platform-updates.json'));
  if (process.argv.includes('--built-index')) for (const {asset,bytes} of updateAssets) {const file=path.join(path.dirname(target),asset);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);}
  for (const {asset} of outputs) {
    const destination = asset === '/organizers-page' ? target : path.join(path.dirname(target), asset.slice(1));
    fs.mkdirSync(path.dirname(destination), {recursive:true});
    fs.renameSync(path.join(staging,asset.slice(1)), destination);
  }
  fs.writeFileSync(manifestPath, JSON.stringify(publicManifest(context)) + '\n');
  if (catalogOutput) fs.writeFileSync(index, catalogOutput);
} finally { fs.rmSync(staging, {recursive:true,force:true}); }
console.log(`Rendered ${outputs.length} organizer pages (${context.locale}).`);
