import writeIfChanged from '../lib/write_if_changed.cjs';
import {execFileSync} from 'node:child_process';
import {pressAssetBase, pressLogos, logoFilename} from './organizers/press.mjs';
import {publicRuntime} from './organizers/public_runtime.mjs';
import { expandSiteShell, publicThemeHead, publicThemeBody } from './organizers/site_shell.mjs';
import { renderUpdate } from './platform_updates/render.mjs';
import {updatePaths} from './platform_updates/context.mjs';
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
  fs.rmSync(path.join(path.dirname(target),pressAssetBase.slice(1)),{recursive:true,force:true});
  fs.rmSync(path.join(path.dirname(target),'organizers/updates'),{recursive:true,force:true});
  fs.rmSync(path.join(path.dirname(target),'platform-updates.json'),{force:true});
  fs.rmSync(path.join(path.dirname(target),'co-je-nove/_assets'),{recursive:true,force:true});
  fs.rmSync(path.join(path.dirname(target),'organizers-assets'),{recursive:true,force:true});
  if (process.argv.includes('--built-index')) fs.rmSync(path.join(path.dirname(target),'platform-updates-media'),{recursive:true,force:true});
  for (const asset of [...Object.values(pageDefinitions).map(page=>page.asset), ...retiredPageAssets]) fs.rmSync(path.join(path.dirname(target), asset.slice(1)), {force:true});
};
if (process.argv.includes('--catalog-only')) {
  // Preserve overlay-owned generated leaves; source must remain clean for upload.
  if(catalogOutput)writeIfChanged.writeFileSync(index,catalogOutput);
  console.log('Prepared catalogue; public documents are assembled after compilation.');
  process.exit(0);
}
if (!enabled) {
  cleanOutputs();
  fs.mkdirSync(path.dirname(target), {recursive:true});
  writeIfChanged.writeFileSync(manifestPath, JSON.stringify(publicManifest(context)) + '\n');
  if (catalogOutput) writeIfChanged.writeFileSync(index, catalogOutput);
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
const pressCss = fs.readFileSync(path.join(root, 'automation/release/organizers/press.css'), 'utf8');
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
// The homepage and its account header share the same public runtime owner as
// help/update pages. A fresh deployment namespace also bypasses cached 404s
// for unchanged shared chunk names from an earlier partial load.
const marketingRuntime = builtIndexArg < 0
  ? {assets: {}, assetRoot: '/', entryUrl: null, themeLinks: ''}
  : publicRuntime(root, {
  builtIndex: path.resolve(process.argv[builtIndexArg + 1]),
  entry: 'src/marketing/landing.js', assetRoot: '/organizers-assets/', versioned: true,
});
const {themeLinks} = marketingRuntime;
if (builtIndexArg >= 0 && !themeLinks) throw new Error('Built organizer page needs the existing Vite theme stylesheet');
const entryScript = marketingRuntime.entryUrl
  ? `<script type="module" src="${marketingRuntime.entryUrl}"></script>` : '';
const updatesRuntime=context.updates?publicRuntime(root,{builtIndex:builtIndexArg<0?null:path.resolve(process.argv[builtIndexArg+1]),entry:'src/marketing/landing.js',assetRoot:'/co-je-nove/_assets/',versioned:true}):null;
if(updatesRuntime)for(const {asset,bytes}of updateAssets)updatesRuntime.assets['media/'+asset.slice('/platform-updates-media/'.length)]=bytes;
  for (const page of context.pages) {
  if (page.type) {outputs.push({asset:page.asset,html:renderUpdate(page,context,{css,themeLinks:updatesRuntime.themeLinks,primary,entryScript:updatesRuntime.entryUrl?`<script type="module" src="${updatesRuntime.entryUrl}"></script>`:'',assetRoot:updatesRuntime.assetRoot})});continue;}
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
  const illustrated = page.id === 'home' && projection.homeStyle === 'illustrated';
  let body = illustrated ? fs.readFileSync(path.join(root, 'automation/release/organizers/illustrated-home.html'), 'utf8') : template;
  const pageCss = illustrated ? fs.readFileSync(path.join(root, 'automation/release/organizers/illustrated-home.css'), 'utf8') : css;
  if (projection.locale === 'cs') {
    body=body.replace(/<a href="#(?:vstupenka|vyber-mist|odbaveni)">[\s\S]*?<\/a>/g,'');
    const reference=body.match(/<section id="reference"[\s\S]*?<\/section>/)?.[0] ?? '';
    body=body.replace(reference,'').replace(/<section class="steps wrap reveal"[\s\S]*?<\/section>/,'').replace(/<section class="technical-options wrap"[\s\S]*?<\/section>/,'');
    body=body.replace(/<details><summary>{{PAGE_(?:CAN_GUESTS_CHOOSE_SPECIFIC_SEATS|WHAT_CAN_I_CUSTOMIZE|HOW_DO_I_CHECK_TICKETS_AT_THE_DOOR)}}<\/summary>[\s\S]*?<\/details>/g,'');
    body=body.replace('<section class="payments',reference+'<section class="payments');
  }

  if (!projection.references?.length) body = body.replace(/<section id="reference"[\s\S]*?<\/section>/, "");
  if (page.id !== 'home') body = body.replace(/<main id="main">[\s\S]*?<\/main>/, '<main id="main">{{TOPIC_CONTENT}}</main>');
  const content = substitute(body)
    .replace('<header class="site-header auth-pending"', marketingRuntime.entryUrl
      ? `<header class="site-header auth-pending" data-brand-asset-base="${escape(marketingRuntime.assetRoot)}"`
      : '<header class="site-header auth-pending"')
    .replace(/src="\/(brand-logo(?:-light)?\.svg)"/g,
      (_, name) => `src="${escape(marketingRuntime.assetRoot + name)}"`);
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
<meta name="referrer" content="no-referrer"><meta name="color-scheme" content="light">${publicThemeHead}
<title>${escape(title)}</title><meta name="description" content="${escape(description)}">
<meta name="robots" content="index,follow,max-image-preview:large"><link rel="canonical" href="${canonical}">
<meta property="og:type" content="website"><meta property="og:locale" content="${escape(projection.ogLocale)}"><meta property="og:site_name" content="${escape(seo.siteName)}">
<meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(description)}"><meta property="og:url" content="${canonical}">
<meta property="og:image" content="${socialImage}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="${escape(seo.imageAlt)}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${escape(title)}"><meta name="twitter:description" content="${escape(description)}"><meta name="twitter:image" content="${socialImage}"><meta name="twitter:image:alt" content="${escape(seo.imageAlt)}">
<script type="application/ld+json">${jsonScript(structured)}</script>
<link rel="icon" href="/favicon.ico">${illustrated ? '<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png"><link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png"><link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png"><link rel="manifest" href="/manifest.json">' : ''}${themeLinks}<style>:root{--primary-color:${primary}}${pageCss}${page.id === 'press' ? pressCss : ''}</style><noscript><style>.auth-pending :is(.header-signin,.header-cta){visibility:visible;pointer-events:auto}</style></noscript></head><body data-page="organizers" data-topic="${escape(page.id)}"${illustrated ? ' data-drawing="original" data-story="revised-english" data-cinematic="true"' : ''}>${publicThemeBody}${content}<script type="application/json" id="marketing-ui">${jsonScript(projection.ui)}</script>${entryScript}</body></html>\n`;

outputs.push({asset:page.asset, html});
}
// Complete staging first: an invalid profile never replaces part of a bundle.
fs.mkdirSync(path.dirname(target), {recursive:true});
const staging = fs.mkdtempSync(path.join(path.dirname(target), '.organizers-stage-'));
try {
  const press = context.pages.find(page=>page.id==='press');
  if (press) execFileSync('python3',[path.join(root,'automation/release/organizers/build_press_kit.py'),path.join(root,'assets/brand/vstupenky-online'),path.join(staging,pressAssetBase.slice(1))],{input:JSON.stringify({
    files:pressLogos.flatMap(logo=>[false,true].flatMap(dark=>['svg',...(logo.png?['png']:[])].map(format=>logoFilename(logo,dark,format)))),
    texts:{'o-projektu.txt':press.press.summary+'\n\n'+press.press.features.map(item=>item.title+'\n'+item.text).join('\n\n')+'\n\nKontakt: '+projection.provider.name+' | '+projection.contact+'\n',
      'pouziti-loga.txt':'vstupenky.online - oficiální loga\n\n'+press.press.usage.join('\n\n')+'\n\nSoubory s příponou -dark jsou určeny na tmavé pozadí.\nBarvy: námořnická #19243b, modrá #80bdf2.\nKontakt: '+projection.contact+'\n'}
  })});
  for (const output of outputs) {
    const file = path.join(staging, output.asset.slice(1));
    fs.mkdirSync(path.dirname(file), {recursive:true}); writeIfChanged.writeFileSync(file, output.html);
  }
  if (context.updates) writeIfChanged.writeFileSync(path.join(staging,'platform-updates.json'),JSON.stringify(context.updates.feed)+'\n');
  for(const [name,bytes]of Object.entries(marketingRuntime.assets)){const file=path.join(staging,marketingRuntime.assetRoot.slice(1),name);fs.mkdirSync(path.dirname(file),{recursive:true});writeIfChanged.writeFileSync(file,bytes);}
  if(updatesRuntime)for(const [name,bytes]of Object.entries(updatesRuntime.assets)){const file=path.join(staging,updatesRuntime.assetRoot.slice(1),name);fs.mkdirSync(path.dirname(file),{recursive:true});writeIfChanged.writeFileSync(file,bytes);}
  // Remove only retired outputs. Preserve unchanged generated bytes and mtimes.
  const active = new Set(outputs.map(output=>output.asset));
  for (const asset of [...Object.values(pageDefinitions).map(page=>page.asset), ...retiredPageAssets]) {
    if (!active.has(asset)) fs.rmSync(path.join(path.dirname(target),asset.slice(1)),{recursive:true,force:true});
  }
  fs.rmSync(path.join(path.dirname(target),'organizers/updates'),{recursive:true,force:true});
  const pressDestination=path.join(path.dirname(target),pressAssetBase.slice(1));
  if (press) writeIfChanged.syncTree(path.join(staging,pressAssetBase.slice(1)),pressDestination);
  else fs.rmSync(pressDestination,{recursive:true,force:true});
  const feed=path.join(path.dirname(target),'platform-updates.json');
  if (context.updates) writeIfChanged.copyFileSync(path.join(staging,'platform-updates.json'),feed);
  else fs.rmSync(feed,{force:true});
  if (process.argv.includes('--built-index')) {
    const mediaRoot=path.join(path.dirname(target),'platform-updates-media');
    const stagedMedia=path.join(staging,'platform-updates-media');
    fs.mkdirSync(stagedMedia,{recursive:true});
    for (const {asset,bytes} of updateAssets) {const file=path.join(staging,asset);fs.mkdirSync(path.dirname(file),{recursive:true});writeIfChanged.writeFileSync(file,bytes);}
    writeIfChanged.syncTree(stagedMedia,mediaRoot);
  }
  const runtimeOutput=path.join(path.dirname(target),'co-je-nove/_assets');
  if(updatesRuntime)writeIfChanged.syncTree(path.join(staging,'co-je-nove/_assets'),runtimeOutput);
  else fs.rmSync(runtimeOutput,{recursive:true,force:true});
  const marketingOutput=path.join(path.dirname(target),'organizers-assets');
  if(marketingRuntime.entryUrl)writeIfChanged.syncTree(path.join(staging,'organizers-assets'),marketingOutput);
  else fs.rmSync(marketingOutput,{recursive:true,force:true});
  for (const {asset} of outputs) {
    const destination = asset === '/organizers-page' ? target : path.join(path.dirname(target), asset.slice(1));
    fs.mkdirSync(path.dirname(destination), {recursive:true});
    writeIfChanged.copyFileSync(path.join(staging,asset.slice(1)),destination);
  }
  writeIfChanged.writeFileSync(manifestPath, JSON.stringify(publicManifest(context)) + '\n');
  if (catalogOutput) writeIfChanged.writeFileSync(index, catalogOutput);
} finally { fs.rmSync(staging, {recursive:true,force:true}); }
console.log(`Rendered ${outputs.length} organizer pages (${context.locale}).`);
