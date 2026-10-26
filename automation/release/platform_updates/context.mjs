import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
export const updatePaths = Object.freeze({cs:'/co-je-nove', en:'/en/whats-new'});
export const updateText = Object.freeze({
  cs:{title:'Co je nového',description:'Nové funkce, vylepšení a opravy platformy pro pořadatele.',empty:'Zatím zde nejsou žádné zveřejněné aktualizace.',back:'Zpět na přehled',home:'Pro pořadatele',updated:'Upraveno',feature:'Nová funkce',improvement:'Vylepšení',fix:'Oprava'},
  en:{title:"What's new",description:'New features, improvements and fixes for event organizers.',empty:'There are no published updates yet.',back:'Back to updates',home:'For organizers',updated:'Updated',feature:'New feature',improvement:'Improvement',fix:'Fix'},
});
export const escape = value => String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fail = (file,field) => { throw new Error(`${file}: invalid or missing ${field}`); };
function markdown(source, file, assetsDir, origin) {
  const MarkdownIt = require('markdown-it');
  const parser = new MarkdownIt({html:false,linkify:false,typographer:false});
  const assets = new Set();
  const tokens = parser.parse(source, {});
  const inspect = list => { for (const token of list) {
    if (token.type === 'heading_open' || token.type === 'heading_close') token.tag = 'h'+Math.min(6,Number(token.tag.slice(1))+1);
    if (token.type === 'html_block' || token.type === 'html_inline' || /<\/?[a-z!][^>]*>/i.test(token.content) && token.type === 'text') fail(file,'raw HTML');
    if (token.type === 'link_open' || token.type === 'image') {
      const href = token.attrGet(token.type === 'image' ? 'src' : 'href');
      let url; try {url=new URL(href,origin);} catch {fail(file,'link URL');}
      if (!['https:','mailto:'].includes(url.protocol) || url.username || url.password || /[\\\x00-\x20]/.test(href)) fail(file,'link URL');
      if (token.type === 'image') {
        if (!token.content.trim() || url.origin !== origin || !/^\/platform-updates-media\/[a-zA-Z0-9/_-]+\.(png|jpe?g|webp|gif)$/.test(url.pathname) || url.search || url.hash) fail(file,'image/alt');
        const asset = url.pathname;
        if (!fs.existsSync(path.join(assetsDir,asset)) || !fs.statSync(path.join(assetsDir,asset)).isFile() || !fs.realpathSync(path.join(assetsDir,asset)).startsWith(fs.realpathSync(assetsDir)+path.sep)) fail(file,`missing asset ${asset}`);
        token.attrSet('src',asset); assets.add(asset);
      } else token.attrSet('href', url.href);
    }
    if (token.children) inspect(token.children);
  }};
  // markdown-it rejects dangerous links before tokenization; reject those source
  // attempts as author errors too, instead of silently publishing broken markup.
  if (/<\/?[a-z!][^>]*>/i.test(source) || /\]\(\s*(?:javascript|data|vbscript|file):/i.test(source)) fail(file,'unsafe markup');
  inspect(tokens);
  return {html:parser.renderer.render(tokens,parser.options,{}),assets:[...assets]};
}
export function resolveUpdates(origin, {contentDir=path.join(root,'content/platform-updates'),assetsDir=path.join(root,'web'),now=new Date()}={}) {
  if (!fs.existsSync(contentDir)) fail(contentDir,'content directory');
  const items = [], ids = new Set(), assets = new Set();
  for (const entry of fs.readdirSync(contentDir,{withFileTypes:true})) {
    if (!entry.isDirectory()) continue;
    const file = path.join(contentDir,entry.name,'meta.json');
    let meta; try {meta=JSON.parse(fs.readFileSync(file,'utf8'));} catch (error) {throw new Error(`${file}: ${error.message}`);}
    if (!meta || typeof meta !== 'object' || Array.isArray(meta)) fail(file,'metadata');
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(meta.id) || meta.id !== entry.name || ids.has(meta.id)) fail(file,'id');
    ids.add(meta.id);
    if (!['draft','published'].includes(meta.status)) fail(file,'status');
    if (meta.status === 'draft') continue;
    const instant = field => {const value=meta[field]; if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(value) || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().replace('.000Z','Z') !== value.replace('.000Z','Z')) fail(file,field); return Date.parse(value);};
    if (instant('publishedAt') > +now) fail(file,'publishedAt (future publication is unsupported)');
    if ('updatedAt' in meta && (instant('updatedAt') < Date.parse(meta.publishedAt) || Date.parse(meta.updatedAt) > +now)) fail(file,'updatedAt');
    if (!['feature','improvement','fix'].includes(meta.kind)) fail(file,'kind');
    const translations = {};
    for (const locale of Object.keys(updatePaths)) {
      const copy=meta.translations?.[locale];
      for (const field of ['title','summary']) if (typeof copy?.[field] !== 'string' || !copy[field].trim()) fail(file,`translations.${locale}.${field}`);
      const bodyFile=path.join(contentDir,entry.name,`${locale}.md`);
      let body; try {body=fs.readFileSync(bodyFile,'utf8');} catch {fail(bodyFile,'body');}
      if (!body.trim()) fail(bodyFile,'body');
      const rendered=markdown(body,bodyFile,assetsDir,origin);
      for (const asset of rendered.assets) assets.add(asset);
      translations[locale]={title:copy.title,summary:copy.summary,url:new URL(`${updatePaths[locale]}/${meta.id}`,origin).href,html:rendered.html};
    }
    items.push({id:meta.id,kind:meta.kind,publishedAt:meta.publishedAt,...(meta.updatedAt?{updatedAt:meta.updatedAt}:{}),translations});
  }
  items.sort((a,b)=>Date.parse(b.publishedAt)-Date.parse(a.publishedAt) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const pages=[];
  for (const [locale,base] of Object.entries(updatePaths)) {
    const t=updateText[locale];
    pages.push({id:`updates-${locale}`,type:'updates-index',locale,path:base,asset:`/organizers/updates/${locale}/index`,canonical:new URL(base,origin).href,title:t.title,description:t.description,heading:t.title});
    for (const item of items) {const copy=item.translations[locale]; pages.push({id:`updates-${locale}-${item.id}`,type:'update-detail',locale,updateId:item.id,path:`${base}/${item.id}`,asset:`/organizers/updates/${locale}/${item.id}`,canonical:copy.url,title:copy.title,description:copy.summary,heading:copy.title});}
  }
  return {items,pages,assets:[...assets],feed:{schemaVersion:1,items:items.map(({translations,...meta})=>({...meta,translations:Object.fromEntries(Object.entries(translations).map(([locale,{html,...copy}])=>[locale,copy]))}))}};
}
