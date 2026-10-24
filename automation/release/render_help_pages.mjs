import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const arg = name => { const index = process.argv.indexOf(name); return index < 0 ? null : process.argv[index + 1]; };
const config = fs.readFileSync(path.resolve(arg('--config') || path.join(root, 'automation/project.conf')), 'utf8');
const value = key => (config.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1] || '').trim().replace(/^(['"])(.*)\1$/, '$2');
const enabled = value('WEB_ORGANIZER_LANDING_ENABLED') === 'true' && new URL(value('WEB_LINK')).hostname === 'vstupenky.online';
const targets = arg('--output') ? [path.resolve(arg('--output'))] : [path.join(root, 'web/napoveda'), path.join(root, 'web_client/public/napoveda')];
for (const target of targets) {
  if (path.basename(target) !== 'napoveda') throw new Error('Help output must be a napoveda directory');
  fs.rmSync(target, {recursive: true, force: true});
}
if (!enabled) { console.log('Public Czech help disabled for this tenant.'); process.exit(0); }
const directory = path.join(root, 'automation/release/help');
const pages = JSON.parse(fs.readFileSync(path.join(directory, 'pages.json'), 'utf8'));
const origin = new URL(value('WEB_LINK')).origin;
const escape = text => String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const digest = data => createHash('sha256').update(data).digest('hex').slice(0, 12);
const assets = {};
const media = JSON.parse(fs.readFileSync(path.join(directory, 'media.json'), 'utf8'));
const figures = new Map(media.map(item => {
  if (!/^[a-z0-9/-]+$/.test(item.id) || !/^[a-z0-9/-]+\.png$/.test(item.file)) throw new Error('Invalid help media path');
  const data = fs.readFileSync(path.join(directory, 'media', item.file));
  const name = `${item.id.replaceAll('/', '-')}.${digest(data)}.png`;
  assets[name] = data;
  const href = `/napoveda/assets/${name}`;
  return [item.id, `<figure class="guide-screenshot"><a href="${href}" target="_blank" rel="noopener" aria-label="${escape(item.openLabel)}"><img src="${href}" width="${item.width}" height="${item.height}" loading="lazy" alt="${escape(item.alt)}"></a><figcaption>${escape(item.caption)}</figcaption></figure>`];
}));
let fontFaces = '';
for (const [file,weight] of [['FuturaPTBook.ttf',400],['FuturaPTMedium.ttf',500]]) {
  const data = fs.readFileSync(path.join(root, 'web_client/src/assets/fonts', file));
  const name = file.replace('.ttf', `.${digest(data)}.ttf`); assets[name] = data;
  fontFaces += `@font-face{font-family:Futura;src:url("${name}") format("truetype");font-weight:${weight};font-style:normal;font-display:swap}\n`;
}
const css = fontFaces + fs.readFileSync(path.join(directory, 'help.css'), 'utf8');
const cssName = `help.${digest(css)}.css`; assets[cssName] = css;
const script = fs.readFileSync(path.join(directory, 'help.js'), 'utf8');
const jsName = `help.${digest(script)}.js`; assets[jsName] = script;
const product = JSON.parse(fs.readFileSync(path.join(root, 'integrations/wordpress/products.json'), 'utf8')).find(p => p.slug === 'vstupenky-online');
const zipName = `${product.slug}-${product.version}.zip`;
const packaged = spawnSync('python3', [path.join(root, 'integrations/wordpress/scripts/package.py'), '--product', product.slug], {encoding:'utf8'});
if (packaged.status !== 0) throw new Error(packaged.stderr || packaged.stdout || 'WordPress package failed');
assets[zipName] = fs.readFileSync(path.join(root, 'integrations/wordpress/dist', zipName));
const download = JSON.parse(fs.readFileSync(path.join(directory, 'download.json'), 'utf8'));
if (download.plugin !== product.slug || download.version !== product.version || createHash('sha256').update(assets[zipName]).digest('hex') !== download.sha256) throw new Error('Public plugin download differs from its reviewed release');
const generator = fs.readFileSync(path.join(directory, 'embed-generator.html'), 'utf8');
const navigation = current => pages.map(page => `<li><a href="/napoveda/${page.slug ? page.slug + '/' : ''}"${page.slug === current ? ' aria-current="page"' : ''}>${escape(page.label)}</a></li>`).join('');
for (const page of pages) {
  const canonical = `${origin}/napoveda/${page.slug ? page.slug + '/' : ''}`;
  const body = fs.readFileSync(path.join(directory, `${page.slug || 'index'}.html`), 'utf8').replace('{{EMBED_GENERATOR}}', generator).replace(/\{\{MEDIA:([a-z0-9/-]+)\}\}/g, (_, id) => {
    if (!figures.has(id)) throw new Error(`Missing help screenshot: ${id}`);
    return figures.get(id);
  }).replaceAll('vstupenky-online-1.0.0.zip', zipName).replaceAll('vstupenky.online 1.0.0', `vstupenky.online ${product.version}`);
  const toc = [...body.matchAll(/<h2 id="([^"]+)">([^<]+)<\/h2>/g)].map(([,id,label]) => `<li><a href="#${id}">${label}</a></li>`).join('');
  const structured = {'@context':'https://schema.org','@type':page.slug ? 'TechArticle' : 'CollectionPage',headline:page.title,description:page.description,url:canonical,inLanguage:'cs-CZ',isPartOf:{'@type':'WebSite',name:'vstupenky.online',url:origin+'/'}};
  const json = JSON.stringify(structured).replace(/</g,'\\u003c');
  const html = `<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>${escape(page.seoTitle)} | vstupenky.online</title><meta name="description" content="${escape(page.description)}"><meta name="robots" content="index,follow"><link rel="canonical" href="${canonical}"><meta property="og:type" content="article"><meta property="og:title" content="${escape(page.seoTitle)}"><meta property="og:description" content="${escape(page.description)}"><meta property="og:url" content="${canonical}"><meta property="og:site_name" content="vstupenky.online"><link rel="icon" href="/favicon.ico"><link rel="stylesheet" href="/napoveda/assets/${cssName}"><script type="application/ld+json">${json}</script>${body.includes('data-embed-generator') ? `<script src="/napoveda/assets/${jsName}" defer></script>` : ''}</head><body>
<a class="skip-link" href="#main">Přejít k obsahu</a><header class="help-header"><a class="brand" href="/">vstupenky.online</a><nav aria-label="Hlavní navigace"><a class="events-link" href="/events">Akce</a><a href="/login">Administrace</a></nav></header>
<div class="help-layout"><aside class="help-sidebar"><p>Nápověda pro pořadatele</p><nav aria-label="Návody"><ul>${navigation(page.slug)}</ul></nav></aside><details class="mobile-menu"><summary>Návody pro pořadatele</summary><nav aria-label="Návody"><ul>${navigation(page.slug)}</ul></nav></details>
<main id="main" class="help-main"><nav class="breadcrumb" aria-label="Drobečková navigace"><a href="/">Úvod</a> / ${page.slug ? '<a href="/napoveda/">Nápověda</a> / <span aria-current="page">' + escape(page.label) + '</span>' : '<span aria-current="page">Nápověda</span>'}</nav><h1>${escape(page.title)}</h1>${page.slug && toc ? `<details class="guide-toc"><summary>Na této stránce</summary><ul>${toc}</ul></details>` : ''}${body}<div class="guide-related"><p>Další pomoc</p><a href="/napoveda/">Všechny návody</a><a href="/support/">Kontakt na podporu</a></div></main></div>
<footer class="help-footer"><div><p>vstupenky.online · Prodej vstupenek a správa akcí</p><nav aria-label="Odkazy v patičce"><a href="/napoveda/">Nápověda</a><a href="/privacy/">Soukromí</a><a href="/terms/">Podmínky</a><a href="/support/">Podpora</a></nav></div></footer></body></html>\n`;
  for (const target of targets) { const folder = path.join(target,page.slug); fs.mkdirSync(folder,{recursive:true}); fs.writeFileSync(path.join(folder,'index.html'),html); }
}
for (const target of targets) { fs.mkdirSync(path.join(target,'assets'),{recursive:true}); for (const [name,data] of Object.entries(assets)) fs.writeFileSync(path.join(target,'assets',name),data); }
console.log(`Rendered ${pages.length} public help pages and verified WordPress download.`);

// The Pages worker emits these routes dynamically; static hosts use this file.
if (!arg('--output')) {
  const sitemap = path.join(root, 'web_client/public/sitemap.xml');
  if (fs.existsSync(sitemap)) {
    const original = fs.readFileSync(sitemap, 'utf8').replace(/\s*<url><loc>https:\/\/[^<]+\/napoveda\/[^<]*<\/loc><\/url>/g, '');
    const entries = pages.map(page => `  <url><loc>${origin}/napoveda/${page.slug ? page.slug + '/' : ''}</loc></url>`).join('\n');
    fs.writeFileSync(sitemap, original.replace('</urlset>', entries + '\n</urlset>'));
  }
}
