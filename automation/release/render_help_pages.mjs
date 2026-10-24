import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {renderSiteShell} from './organizers/site_shell.mjs';

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
  return [item.id, `<figure class="guide-screenshot"><a href="${href}" target="_blank" rel="noopener" aria-label="${escape(item.openLabel)}"><img src="${href}" width="${item.width}" height="${item.height}" loading="lazy" alt="${escape(item.alt)}"></a><figcaption>${escape(item.caption)}</figcaption></figure>`];
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
const groups = Object.entries(ui.categories);
const navigation = current => `<ul><li><a href="${helpRoot}"${current === '' ? ' aria-current="page"' : ''}>${escape(pages[0].label)}</a></li></ul>` + groups.map(([id,label]) => `<p class="help-nav-group">${escape(label)}</p><ul>${pages.filter(p => p.category === id).map(page => `<li><a href="${href(page)}"${page.slug === current ? ' aria-current="page"' : ''}>${escape(page.label)}</a></li>`).join('')}</ul>`).join('');
const topicIndex = `<nav class="help-topic-index" aria-label="${escape(ui.organizerHelp)}"><ul>${groups.map(([id,label]) => `<li><a href="#category-${id}">${escape(label)}</a></li>`).join('')}</ul></nav>`;
const guideDirectory = topicIndex + groups.map(([id,label]) => `<section aria-labelledby="category-${id}"><h2 id="category-${id}">${escape(label)}</h2><div class="guide-list">${pages.filter(p => p.category === id).map(page => `<a href="${href(page)}"><strong>${escape(page.title)}</strong><span>${escape(page.description)}</span></a>`).join('')}</div></section>`).join('');
let accountScript = '', themeLinks = '';
if (arg('--built-index')) {
  const builtIndex = path.resolve(arg('--built-index'));
  const manifest = JSON.parse(fs.readFileSync(path.join(path.dirname(builtIndex),'.vite/manifest.json'),'utf8'));
  const entry = manifest['src/marketing/help.js'];
  if (!entry?.file) throw new Error('Built help needs the Vite help entry');
  accountScript = `<script type="module" src="/${escape(entry.file)}"></script>`;
  themeLinks = (fs.readFileSync(builtIndex,'utf8').match(/<link[^>]*rel="stylesheet"[^>]*>/g) || []).filter(tag => /href="\/web-assets\/[^\"]+\.css"/.test(tag) || tag.includes('https://fonts.googleapis.com/icon?family=Material+Icons')).join('');
}
const shell = renderSiteShell({locale,brand,contact:site.contact,helpPath:helpRoot,helpLabel:ui.help,accountHeader:!!accountScript});
for (const page of pages) {
  let body = fs.readFileSync(path.join(source,`${page.slug || 'index'}.html`),'utf8')
    .replace('{{EMBED_GENERATOR}}',generator).replace('{{GUIDE_DIRECTORY}}',guideDirectory)
    .replace(/\{\{MEDIA:([a-z0-9/-]+)\}\}/g,(_,id) => {
      if (!figures.has(id)) throw new Error(`Missing ${locale} help screenshot: ${id}`);
      return figures.get(id);
    }).replaceAll('{{HELP_ROOT}}',helpRoot).replaceAll('{{HELP_ASSETS}}',helpRoot+'assets/').replaceAll('{{FORM_ORIGIN}}',escape(origin))
    .replaceAll('vstupenky-online-1.0.0.zip',zipName).replaceAll('vstupenky.online 1.0.0',`vstupenky.online ${product.version}`);
  if (body.includes('{{')) throw new Error(`Unresolved help content token: ${page.id}`);
  const toc = [...body.matchAll(/<h2 id="([^"]+)">([^<]+)<\/h2>/g)].map(([,id,label]) => `<li><a href="#${id}">${label}</a></li>`).join('');
  const canonical = origin + href(page);
  const structured = {'@context':'https://schema.org','@type':page.slug ? 'TechArticle' : 'CollectionPage',headline:page.title,description:page.description,url:canonical,inLanguage:ui.languageTag,isPartOf:{'@type':'WebSite',name:brand,url:origin+'/'}};
  const json = JSON.stringify(structured).replace(/</g,'\\u003c');
  const html = `<!doctype html><html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><meta name="referrer" content="no-referrer"><title>${escape(page.seoTitle)} | ${escape(brand)}</title><meta name="description" content="${escape(page.description)}"><meta name="robots" content="${preview ? 'noindex,nofollow' : 'index,follow'}">${preview ? '' : `<link rel="canonical" href="${canonical}">`}<meta property="og:type" content="article"><meta property="og:title" content="${escape(page.seoTitle)}"><meta property="og:description" content="${escape(page.description)}"><meta property="og:url" content="${canonical}"><meta property="og:site_name" content="${escape(brand)}"><link rel="icon" href="/favicon.ico">${themeLinks}<link rel="stylesheet" href="${helpRoot}assets/${cssName}"><script type="application/ld+json">${json}</script>${body.includes('data-embed-generator') ? `<script src="${helpRoot}assets/${jsName}" defer></script>` : ''}<noscript><style>.auth-pending .header-signin{visibility:visible}</style></noscript></head><body data-page="help"><a class="skip-link" href="#main">${escape(ui.skip)}</a>${shell.header}
<div class="help-layout"><aside class="help-sidebar"><p>${escape(ui.organizerHelp)}</p><nav aria-label="${escape(ui.guides)}">${navigation(page.slug)}</nav></aside><details class="help-mobile-menu"><summary>${escape(ui.mobileGuides)}</summary><nav aria-label="${escape(ui.guides)}">${navigation(page.slug)}</nav></details>
<main id="main" class="help-main"><nav class="breadcrumb" aria-label="${escape(ui.breadcrumb)}"><a href="/">${escape(ui.home)}</a> / ${page.slug ? `<a href="${helpRoot}">${escape(ui.help)}</a> / <span aria-current="page">${escape(page.label)}</span>` : `<span aria-current="page">${escape(ui.help)}</span>`}</nav><h1>${escape(page.title)}</h1>${page.slug && toc ? `<details class="guide-toc"><summary>${escape(ui.onThisPage)}</summary><ul>${toc}</ul></details>` : ''}${body}<div class="guide-related"><p>${escape(ui.related)}</p><a href="${helpRoot}">${escape(ui.allGuides)}</a><a href="/support/">${escape(ui.support)}</a></div></main></div>${shell.footer}${accountScript}</body></html>\n`;
  for (const target of targets) {const folder = path.join(target,page.slug); fs.mkdirSync(folder,{recursive:true}); fs.writeFileSync(path.join(folder,'index.html'),html);}
}
for (const target of targets) {fs.mkdirSync(path.join(target,'assets'),{recursive:true}); for (const [name,data] of Object.entries(assets)) fs.writeFileSync(path.join(target,'assets',name),data);}
console.log(`Rendered ${pages.length} ${locale} help pages and verified WordPress download.`);
if (!arg('--output')) {
  const sitemap = path.join(root,'web_client/public/sitemap.xml');
  if (fs.existsSync(sitemap)) {
    const original = fs.readFileSync(sitemap,'utf8').replace(/\s*<url><loc>https:\/\/[^<]+\/napoveda\/[^<]*<\/loc><\/url>/g,'');
    const entries = pages.map(page => `  <url><loc>${origin}${href(page)}</loc></url>`).join('\n');
    fs.writeFileSync(sitemap,original.replace('</urlset>',entries+'\n</urlset>'));
  }
}
