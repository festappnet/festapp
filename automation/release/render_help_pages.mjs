import { helpActionWebPath } from '../../web_client/src/services/help_action_routes.js';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {articleSections} from './help/search_index.mjs';
import {renderSiteShell, publicThemeHead, publicThemeBody} from './organizers/site_shell.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const arg = name => {const i = process.argv.indexOf(name); return i < 0 ? null : process.argv[i + 1];};
const config = fs.readFileSync(path.resolve(arg('--config') || path.join(root, 'automation/project.conf')), 'utf8');
const value = key => (config.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1] || '').trim().replace(/^(['"])(.*)\1$/, '$2');
const locale = arg('--locale') || 'cs';
const preview = process.argv.includes('--preview');
if (!['cs', 'en'].includes(locale)) throw new Error('Unknown help locale');
if (locale !== 'cs' && (!preview || !arg('--output'))) throw new Error('English help is preview-only until localized screenshot capture is complete');
const enabled = value('WEB_ORGANIZER_LANDING_ENABLED') === 'true' && new URL(value('WEB_LINK')).hostname === 'vstupenky.online';
const targets = arg('--output') ? [path.resolve(arg('--output'))] : [path.join(root, 'web/napoveda'), path.join(root, 'web_client/public/napoveda')];
for (const target of targets) {
  if (path.basename(target) !== 'napoveda') throw new Error('Help output must be a napoveda directory');
  fs.rmSync(target, {recursive:true, force:true});
}
if (!enabled) {console.log('Public help disabled for this tenant.'); process.exit(0);}
const directory = path.join(root, 'automation/release/help');
const source = locale === 'cs' ? directory : path.join(directory, 'en');
const pages = JSON.parse(fs.readFileSync(path.join(directory, locale === 'cs' ? 'pages.json' : 'pages.en.json'), 'utf8'));
const ui = JSON.parse(fs.readFileSync(path.join(directory, 'ui.json'), 'utf8'))[locale];
const site = JSON.parse(fs.readFileSync(path.join(root, 'automation/release/organizers', locale === 'cs' ? 'content.json' : 'content.en.json'), 'utf8')).publicProjection;
const brand = locale === 'cs' ? (value('APP_NAME') || site.seo.siteName) : site.seo.siteName;
const origin = new URL(value('WEB_LINK')).origin;
const helpRoot = '/napoveda/';
const escape = text => String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const digest = data => createHash('sha256').update(data).digest('hex').slice(0,12);
const read = file => fs.readFileSync(path.join(directory,file), 'utf8');
const assets = {};
const media = JSON.parse(read('media.json')).filter(item => item.locale === locale);
const mediaWorkflows = new Map(media.map(item => [item.id,item.workflow]));
const previewImages = new Map();
const figures = new Map(media.map(item => {
  if (!/^[a-z0-9/-]+$/.test(item.id)) throw new Error('Invalid help media identity');
  const relative = item.sourceAsset || item.file;
  const valid = item.sourceAsset ? /^web\/organizers-media\/(?:en\/)?[a-z0-9-]+\.(?:png|jpg|webp)$/ : /^[a-z0-9/-]+\.(?:png|jpg|webp)$/;
  if (!valid.test(relative)) throw new Error('Invalid help media path');
  const data = fs.readFileSync(path.join(item.sourceAsset ? root : path.join(directory,'media'),relative));
  if (item.sha256 && createHash('sha256').update(data).digest('hex') !== item.sha256) throw new Error(`Help screenshot requires review: ${item.id}`);
  const name = `${item.id.replaceAll('/','-')}.${digest(data)}${path.extname(relative)}`;
  assets[name] = data;
  const href = `${helpRoot}assets/${name}`;
  const previewContent = `<img src="${href}" width="${item.width}" height="${item.height}" alt="" loading="lazy" decoding="async">`;
  previewImages.set(item.id, `<span class="guide-preview${item.device === 'mobile' ? ' guide-preview-mobile' : ''}${['detail','upper'].includes(item.previewCrop) ? ' guide-preview-'+item.previewCrop : ''}">${item.device === 'mobile' ? `<span class="guide-device">${previewContent}</span>` : previewContent}</span>`);
  return [item.id, `<figure class="guide-screenshot${item.device === 'mobile' ? ' guide-screenshot-mobile' : ''}"><a href="${href}" target="_blank" rel="noopener" aria-label="${escape(item.openLabel)}"><img src="${href}" width="${item.width}" height="${item.height}" loading="lazy" alt="${escape(item.alt)}"></a><figcaption>${escape(item.caption)}</figcaption></figure>`];
}));
let fontFaces = '';
for (const [file,weight] of [['FuturaPTBook.ttf',400],['FuturaPTMedium.ttf',500]]) {
  const data = fs.readFileSync(path.join(root,'web_client/src/assets/fonts',file));
  const name = file.replace('.ttf',`.${digest(data)}.ttf`); assets[name] = data;
  fontFaces += `@font-face{font-family:Futura;src:url("${name}") format("truetype");font-weight:${weight};font-style:normal;font-display:swap}\n`;
}
// A single style authority for the homepage and help shell, followed by reader-only rules.
const css = fontFaces + fs.readFileSync(path.join(root,'automation/release/organizers/page.css'),'utf8') + '\n' + read('help.css');
const cssName = `help.${digest(css)}.css`; assets[cssName] = css;
const script = read('help.js'); const jsName = `help.${digest(script)}.js`; assets[jsName] = script;
const product = JSON.parse(fs.readFileSync(path.join(root,'integrations/wordpress/products.json'),'utf8')).find(p => p.slug === 'vstupenky-online');
const zipName = `${product.slug}-${product.version}.zip`;
const packaged = spawnSync('python3',[path.join(root,'integrations/wordpress/scripts/package.py'),'--product',product.slug],{encoding:'utf8'});
if (packaged.status !== 0) throw new Error(packaged.stderr || packaged.stdout || 'WordPress package failed');
assets[zipName] = fs.readFileSync(path.join(root,'integrations/wordpress/dist',zipName));
const download = JSON.parse(read('download.json'));
if (download.plugin !== product.slug || download.version !== product.version || createHash('sha256').update(assets[zipName]).digest('hex') !== download.sha256) throw new Error('Public plugin download differs from its reviewed release');
const generator = fs.readFileSync(path.join(source,'embed-generator.html'),'utf8');
const href = page => helpRoot + (page.slug ? page.slug + '/' : '');
const categoryPages = JSON.parse(read('categories.json')).map(category => ({...category[locale], id:'category.'+category.id, category:category.id, label:ui.categories[category.id], collection:true}));
const categoryFor = page => categoryPages.find(category => category.category === page.category);
const allPages = [...pages, ...categoryPages];
if (new Set(allPages.map(page => page.slug)).size !== allPages.length) throw new Error('Duplicate help route');
const previewImage = id => {
  if (!previewImages.has(id)) throw new Error(`Missing ${locale} guide preview: ${id}`);
  return previewImages.get(id);
};
const articleList = category => `<div class="guide-list">${pages.filter(p => p.category === category).map(page => `<a href="${href(page)}">${previewImage(page.preview)}<strong>${escape(page.title)}</strong><span>${escape(page.description)}</span></a>`).join('')}</div>`;
const navigation = current => `<ul><li><a href="${helpRoot}"${!current.slug ? ' aria-current="page"' : ''}>${escape(pages[0].label)}</a></li>${categoryPages.map(category => `<li><a href="${href(category)}"${current.id === category.id ? ' aria-current="page"' : ''}>${escape(category.label)}</a>${current.category === category.category ? `<ul class="help-nav-articles">${pages.filter(page => page.category === category.category).map(page => `<li><a href="${href(page)}"${page.id === current.id ? ' aria-current="page"' : ''}>${escape(page.label)}</a></li>`).join('')}</ul>` : ''}</li>`).join('')}</ul>`;
const guideDirectory = `<div class="help-category-directory">${categoryPages.map(category => `<section><h2><a href="${href(category)}">${previewImage(category.preview)}${escape(category.label)}</a></h2><p>${escape(category.description)}</p><a href="${href(category)}">${escape(ui.browseCategory)}</a></section>`).join('')}</div>`;
const appLink = intent => {
  const label = ui.appActions[intent];
  if (!label) throw new Error(`Unknown help action: ${intent}`);
  const url = helpActionWebPath(intent);
  if (!url) throw new Error(`Unknown help action: ${intent}`);
  return `<a class="help-step-action" href="${url}" target="_blank" rel="noopener" aria-label="${escape(label+' ('+ui.opensNewTab+')')}">${escape(label)}<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M14 3h7v7M21 3 10 14M10 5H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-5"/></svg></a>`;
};
const searchIcon = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/></svg>';
const searchChrome = `<div class="help-toolbar"><div class="help-toolbar-inner"><a href="${helpRoot}" class="help-toolbar-home">${escape(ui.organizerHelp)}</a><button type="button" class="help-search-trigger" data-search-open aria-haspopup="dialog" aria-controls="help-search-dialog" hidden>${searchIcon}<span>${escape(ui.searchTrigger)}</span><kbd data-search-shortcut>Ctrl K</kbd></button></div></div><dialog id="help-search-dialog" class="help-search-dialog" aria-labelledby="help-search-title"><div class="help-search-top"><h2 id="help-search-title">${escape(ui.searchLabel)}</h2><button type="button" data-search-close aria-label="${escape(ui.searchClose)}"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg></button></div><form class="help-search" data-help-search role="search" action="${helpRoot}" method="get"><div class="help-search-fields">${searchIcon}<input id="help-query" name="q" aria-label="${escape(ui.searchLabel)}" type="search" maxlength="200" placeholder="${escape(ui.searchPlaceholder)}" autocomplete="off" autofocus><button type="button" data-search-clear hidden>${escape(ui.searchClear)}</button></div><div class="help-search-options"><label for="help-category">${escape(ui.searchCategory)}</label><select id="help-category" name="category"><option value="">${escape(ui.searchAll)}</option>${categoryPages.map(category => `<option value="${category.category}">${escape(category.label)}</option>`).join('')}</select></div></form><div class="help-search-body"><div data-search-intro><h3>${escape(ui.searchIntro)}</h3><p>${escape(ui.searchHint)}</p></div><section data-search-results aria-label="${escape(ui.searchTitle)}"><p role="status" aria-live="polite" aria-atomic="true"></p><ol></ol></section></div><div class="help-search-footer"><span><kbd>↓</kbd> ${escape(ui.searchKeyboard)}</span><span><kbd>Esc</kbd> ${escape(ui.searchClose)}</span></div></dialog><a data-help-base href="${helpRoot}" hidden></a>`;
let accountScript = '', themeLinks = '';
if (arg('--built-index')) {
  const builtIndex = path.resolve(arg('--built-index'));
  const manifest = JSON.parse(fs.readFileSync(path.join(path.dirname(builtIndex),'.vite/manifest.json'),'utf8'));
  const entry = manifest['src/marketing/help.js'];
  if (!entry?.file) throw new Error('Built help needs the Vite help entry');
  // The installed app worker intentionally never pins /napoveda/assets/.
  // Publish the same built graph under that public owner so existing workers
  // can load help without an app-version report or forced PWA update.
  const dist = path.dirname(builtIndex);
  const runtimeRoot = helpRoot + 'assets/runtime/';
  const relocate = text => text.replaceAll('web-assets/', runtimeRoot.slice(1))
    .replaceAll('/assets/translations/', helpRoot + 'assets/translations/');
  for (const file of fs.readdirSync(path.join(dist,'web-assets'),{recursive:true})) {
    const full = path.join(dist,'web-assets',file);
    if (!fs.statSync(full).isFile()) continue;
    assets['runtime/' + file] = /\.(?:m?js|css)$/.test(file)
      ? relocate(fs.readFileSync(full,'utf8')) : fs.readFileSync(full);
  }
  const translations = path.join(dist,'assets/translations');
  for (const file of fs.readdirSync(translations)) {
    if (file.endsWith('.json')) assets['translations/' + file] = fs.readFileSync(path.join(translations,file));
  }
  accountScript = `<script type="module" data-help-runtime src="${escape(relocate('/' + entry.file))}"></script>`;
  themeLinks = (fs.readFileSync(builtIndex,'utf8').match(/<link[^>]*rel="stylesheet"[^>]*>/g) || []).filter(tag => /href="\/web-assets\/[^\"]+\.css"/.test(tag) || tag.includes('https://fonts.googleapis.com/icon?family=Material+Icons')).map(relocate).join('');
}
const shell = renderSiteShell({locale,brand,contact:site.contact,helpPath:helpRoot,helpLabel:ui.help,accountHeader:!!accountScript});
const videos = JSON.parse(read('videos.json'));
const videoLink = id => {
  const video = videos[id]?.[locale];
  if (!video || !/^https:\/\/www\.youtube\.com\/watch\?v=[A-Za-z0-9_-]{11}$/.test(video.url)) throw new Error(`Invalid help video: ${id}`);
  const videoId = new URL(video.url).searchParams.get('v');
  return `<figure class="guide-video"><div class="guide-video-player"><iframe src="https://www.youtube-nocookie.com/embed/${videoId}" title="${escape(video.title)}" loading="lazy" referrerpolicy="strict-origin-when-cross-origin" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe></div><figcaption>${escape(video.description)} <a href="${escape(video.url)}" target="_blank" rel="noopener">${escape(video.title)}</a></figcaption></figure>`;
};
const bodies = new Map();
for (const page of pages) {
  let body = fs.readFileSync(path.join(source,`${page.slug || 'index'}.html`),'utf8')
    .replace('{{EMBED_GENERATOR}}',generator).replace('{{GUIDE_DIRECTORY}}',guideDirectory)
    .replace(/\{\{PREVIEW:([a-z0-9/-]+)\}\}/g, (_,id) => previewImage(id))
    .replace(/\{\{VIDEO:([a-z-]+)\}\}/g, (_,id) => videoLink(id))
    .replace(/\{\{APP_LINK:([a-z-]+)\}\}/g, (_,intent) => appLink(intent))
    .replace(/\{\{MEDIA:([a-z0-9/-]+)\}\}/g,(_,id) => {
      if (page.workflow === 'administration' && mediaWorkflows.get(id) === 'wizard') throw new Error(`Wizard screenshot in administration guide: ${id}`);
      if (!figures.has(id)) throw new Error(`Missing ${locale} help screenshot: ${id}`);
      return figures.get(id);
    }).replaceAll('{{HELP_ROOT}}',helpRoot).replaceAll('{{HELP_ASSETS}}',helpRoot+'assets/').replaceAll('{{FORM_ORIGIN}}',escape(origin))
    .replaceAll('vstupenky-online-1.0.0.zip',zipName).replaceAll('vstupenky.online 1.0.0',`vstupenky.online ${product.version}`);
  if (body.includes('{{')) throw new Error(`Unresolved help content token: ${page.id}`);
  if (page.workflow) {
    const context = ui.workflows[page.workflow];
    if (!context) throw new Error(`Unknown help workflow: ${page.workflow}`);
    body = `<p class="note" data-help-workflow="${escape(page.workflow)}">${escape(context)}</p>` + body;
  }
  bodies.set(page.id, body);
}
for (const category of categoryPages) bodies.set(category.id, `<p class="lead">${escape(category.description)}</p><p>${escape(category.intro)}</p><h2 id="guides">${escape(ui.categoryGuides)}</h2>${articleList(category.category)}<h2 id="related">${escape(ui.categoryRelated)}</h2><ul>${categoryPages.filter(other => other.id !== category.id).map(other => `<li><a href="${href(other)}">${escape(other.label)}</a></li>`).join('')}</ul>`);
const aliases = JSON.parse(read('search_terms.json'))[locale];
const entries = pages.filter(page => page.category).map(page => ({id:page.id,title:page.title,description:page.description,url:href(page),category:page.category,categoryLabel:categoryFor(page).label,aliases:aliases[page.id] || [],sections:articleSections(bodies.get(page.id))}));
const searchData = {entries,locale,ui,helpRoot,supportUrl:origin+'/support/'};
const searchScript = 'globalThis.FestappHelpSearchData='+JSON.stringify(searchData).replace(/</g,'\\u003c')+';\n'+read('search_engine.js')+'\n'+read('search_ui.js');
const searchName = `search.${digest(searchScript)}.js`; assets[searchName] = searchScript;
for (const page of allPages) {
  const body = bodies.get(page.id);
  const toc = [...body.matchAll(/<h2 id="([^"]+)">([^<]+)<\/h2>/g)].map(([,id,label]) => `<li><a href="#${id}">${label}</a></li>`).join('');
  const canonical = origin + href(page);
  const category = categoryFor(page);
  const crumbs = [{name:ui.home,item:origin+'/'},{name:ui.help,item:origin+helpRoot}];
  if (category && category.id !== page.id) crumbs.push({name:category.label,item:origin+href(category)});
  if (page.slug) crumbs.push({name:page.label,item:canonical});
  const collection = !page.slug || page.collection;
  const itemPages = !page.slug ? categoryPages : pages.filter(p => p.category === page.category);
  const structured = {'@context':'https://schema.org','@graph':[
    {'@type':collection ? 'CollectionPage' : 'TechArticle',headline:page.title,name:page.title,description:page.description,url:canonical,inLanguage:ui.languageTag,isPartOf:category && !page.collection ? {'@type':'CollectionPage',name:category.title,url:origin+href(category)} : {'@type':'WebSite',name:brand,url:origin+'/'},...(collection ? {mainEntity:{'@type':'ItemList',itemListElement:itemPages.map((item,i) => ({'@type':'ListItem',position:i+1,name:item.title,url:origin+href(item)}))}} : {})},
    {'@type':'BreadcrumbList',itemListElement:crumbs.map((crumb,i) => ({'@type':'ListItem',position:i+1,...crumb}))}
  ]};
  const json = JSON.stringify(structured).replace(/</g,'\\u003c');
  const breadcrumb = crumbs.map((crumb,i) => i === crumbs.length-1 ? `<span aria-current="page">${escape(crumb.name)}</span>` : `<a href="${escape(new URL(crumb.item).pathname)}">${escape(crumb.name)}</a>`).join(' / ');
  const html = `<!doctype html><html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light">${publicThemeHead}<meta name="referrer" content="no-referrer"><title>${escape(page.seoTitle)} | ${escape(brand)}</title><meta name="description" content="${escape(page.description)}"><meta name="robots" content="${preview ? 'noindex,nofollow' : 'index,follow'}">${preview ? '' : `<link rel="canonical" href="${canonical}">`}<meta property="og:type" content="${collection ? 'website' : 'article'}"><meta property="og:title" content="${escape(page.seoTitle)}"><meta property="og:description" content="${escape(page.description)}"><meta property="og:url" content="${canonical}"><meta property="og:site_name" content="${escape(brand)}"><link rel="icon" href="/favicon.ico">${themeLinks}<link rel="stylesheet" href="${helpRoot}assets/${cssName}"><script type="application/ld+json">${json}</script><script src="${helpRoot}assets/${searchName}" defer></script><script src="${helpRoot}assets/${jsName}" defer></script><noscript><style>.auth-pending :is(.header-signin,.header-cta){visibility:visible;pointer-events:auto}</style></noscript></head><body data-page="help">${publicThemeBody}<a class="skip-link" href="#main">${escape(ui.skip)}</a>${shell.header}${searchChrome}
<div class="help-layout"><aside class="help-sidebar"><p>${escape(ui.categoryNav)}</p><nav aria-label="${escape(ui.guides)}">${navigation(page)}</nav></aside><details class="help-mobile-menu"><summary>${escape(ui.mobileGuides)}</summary><nav aria-label="${escape(ui.guides)}">${navigation(page)}</nav></details>
<main id="main" class="help-main"><nav class="breadcrumb" aria-label="${escape(ui.breadcrumb)}">${breadcrumb}</nav><h1>${escape(page.title)}</h1><div data-help-browse>${page.slug && toc ? `<details class="guide-toc"><summary>${escape(ui.onThisPage)}</summary><ul>${toc}</ul></details>` : ''}${body}<div class="guide-related"><p>${escape(ui.related)}</p>${category && !page.collection ? `<a href="${href(category)}">${escape(category.label)}</a>` : ''}<a href="${helpRoot}">${escape(ui.allGuides)}</a><a href="/support/">${escape(ui.support)}</a></div></div></main></div>${shell.footer}${accountScript}</body></html>\n`;
  for (const target of targets) {const folder = path.join(target,page.slug); fs.mkdirSync(folder,{recursive:true}); fs.writeFileSync(path.join(folder,'index.html'),html);}
}
for (const target of targets) {fs.mkdirSync(path.join(target,'assets'),{recursive:true}); for (const [name,data] of Object.entries(assets)) {const file=path.join(target,'assets',name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,data);}}
console.log(`Rendered ${allPages.length} ${locale} help pages and verified WordPress download.`);
if (!arg('--output')) {
  const sitemap = path.join(root,'web_client/public/sitemap.xml');
  if (fs.existsSync(sitemap)) {
    const original = fs.readFileSync(sitemap,'utf8').replace(/\s*<url><loc>https:\/\/[^<]+\/napoveda\/[^<]*<\/loc><\/url>/g,'');
    const entries = allPages.map(page => `  <url><loc>${origin}${href(page)}</loc></url>`).join('\n');
    fs.writeFileSync(sitemap,original.replace('</urlset>',entries+'\n</urlset>'));
  }
}
