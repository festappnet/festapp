import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const configArgument = process.argv.indexOf('--config');
const configPath = configArgument === -1
  ? path.join(root, 'automation/project.conf')
  : path.resolve(process.argv[configArgument + 1] || '');
const projectConfig = fs.readFileSync(configPath, 'utf8');
const configValue = (key) => projectConfig.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1]
  .trim()
  .replace(/^(['"])(.*)\1$/, '$2');
const appName = configValue('APP_NAME');
const domain = configValue('DOMAIN');
if (!appName) throw new Error(`${configPath} lacks APP_NAME`);
if (!domain) throw new Error(`${configPath} lacks DOMAIN`);
const checkOnly = process.argv.includes('--check');
const validateOnly = process.argv.includes('--validate');
const pages = [
  { key: 'PRIVACY_URL', source: 'privacy-policy.cs.md', output: 'privacy/index.html', pathname: '/privacy/', title: 'Ochrana osobních údajů', nav: 'Soukromí' },
  { key: 'PRIVACY_CHOICES_URL', source: 'privacy-choices.cs.md', output: 'privacy/choices/index.html', pathname: '/privacy/choices/', title: 'Vaše volby a práva', nav: 'Volby' },
  { key: 'TERMS_URL', source: 'terms.cs.md', output: 'terms/index.html', pathname: '/terms/', title: 'Podmínky', nav: 'Podmínky' },
  { key: 'SUPPORT_URL', source: 'support.cs.md', output: 'support/index.html', pathname: '/support/', title: 'Podpora', nav: 'Podpora' },
];
const expectedOrigin = `https://${domain}`;
const configuredUrls = new Map();
for (const page of pages) {
  const value = configValue(page.key);
  if (!value) throw new Error(`${page.key} must be defined in ${configPath}`);
  const url = new URL(value);
  if (url.origin !== expectedOrigin || url.pathname !== page.pathname || url.search || url.hash || url.username || url.password) {
    throw new Error(`${page.key} must equal ${expectedOrigin}${page.pathname}`);
  }
  configuredUrls.set(page.key, url);
}
const deleteAccountUrl = configValue('DELETE_ACCOUNT_URL');
if (!deleteAccountUrl) throw new Error(`DELETE_ACCOUNT_URL must be defined in ${configPath}`);
const parsedDeleteAccountUrl = new URL(deleteAccountUrl);
if (parsedDeleteAccountUrl.origin !== expectedOrigin || parsedDeleteAccountUrl.pathname !== '/delete-account/' ||
    parsedDeleteAccountUrl.search || parsedDeleteAccountUrl.hash || parsedDeleteAccountUrl.username || parsedDeleteAccountUrl.password) {
  throw new Error(`DELETE_ACCOUNT_URL must equal ${expectedOrigin}/delete-account/`);
}
for (const page of pages) {
  const sourcePath = path.join(root, 'automation/release/legal', page.source);
  if (!fs.existsSync(sourcePath) || !fs.readFileSync(sourcePath, 'utf8').trim()) {
    throw new Error(`Required legal source is missing or empty: ${sourcePath}`);
  }
}
if (validateOnly) {
  console.log(`Validated required legal configuration for ${domain}.`);
  process.exit(0);
}

const escape = (value) => value
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

function inline(value) {
  return escape(value)
    .replaceAll(/`([^`]+)`/g, (_, text) =>
      /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(text)
        ? `<a href="mailto:${text}">${text}</a>`
        : `<code>${text}</code>`)
    .replaceAll(/&lt;(https:\/\/[^&]+)&gt;/g, (_, url) => {
      const parsed = new URL(url);
      const normalizedPath = parsed.pathname.endsWith('/')
        ? parsed.pathname
        : `${parsed.pathname}/`;
      const isInternalLegalLink = parsed.origin === expectedOrigin &&
        pages.some((page) => page.pathname === normalizedPath);
      const href = isInternalLegalLink ? normalizedPath : url;
      const label = pages.find((page) => parsed.origin === expectedOrigin && page.pathname === normalizedPath)?.title
        || (parsed.hostname === 'uoou.gov.cz' ? 'Úřad pro ochranu osobních údajů' : '')
        || (parsed.hostname === 'www.apple.com' ? 'Licenční smlouva Apple' : '')
        || (parsed.origin === expectedOrigin && normalizedPath === '/delete-account/' ? 'Potvrzení smazání účtu' : url);
      return `<a href="${href.replaceAll('"', '&quot;')}"${isInternalLegalLink ? ' data-legal-link' : ''}>${escape(label)}</a>`;
    });
}

function markdown(value) {
  return value.trim().split(/\n\s*\n/).map((block) => {
    if (block.startsWith('# ')) return `<h1>${inline(block.slice(2))}</h1>`;
    if (block.startsWith('## ')) return `<h2>${inline(block.slice(3))}</h2>`;
    if (block.startsWith('Účinnost:')) return `<p class="document-meta">${inline(block)}</p>`;
    return `<p>${inline(block.replaceAll('\n', ' '))}</p>`;
  }).join('\n');
}

function document(title, content) {
  const color = (key, fallback) => /^#[0-9a-f]{6}$/i.test(configValue(key) || '')
    ? configValue(key) : fallback;
  const navigation = pages.map((page) =>
    `<a href="${configuredUrls.get(page.key).pathname}" data-legal-link${page.title === title ? ' aria-current="page"' : ''}>${page.nav}</a>`
  ).join('');
  return `<!doctype html>
<html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="index,follow"><meta name="color-scheme" content="light dark"><title>${escape(title)} | ${escape(appName)}</title>
<script>try{const mode=localStorage.getItem('theme');if(mode==='dark'||(!mode&&matchMedia('(prefers-color-scheme:dark)').matches))document.documentElement.dataset.theme='dark';}catch{}</script>
<style>
:root{--primary:${color('THEME_SEED_3', '#4465a6')};--ink:#202734;--muted:#596579;--bg:#ebf1f6;--surface:#fff;--line:#d9e1ea;--hover:#f2f5f9;color-scheme:light}
:root[data-theme=dark]{--primary:${color('THEME_SEED_2', '#80bdf2')};--ink:#e5eaf1;--muted:#b5bfcd;--bg:#232529;--surface:#2b2d31;--line:#454c57;--hover:#343942;color-scheme:dark}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.7 system-ui,sans-serif}a{color:var(--primary);text-underline-offset:3px;overflow-wrap:anywhere}a:hover{text-decoration-thickness:2px}a:focus-visible,button:focus-visible{outline:2px solid var(--primary);outline-offset:4px;border-radius:4px}header{max-width:1040px;margin:auto;padding:24px 32px;display:flex;align-items:center;justify-content:space-between;gap:16px}.brand{font-size:20px;font-weight:700;color:var(--ink);text-decoration:none}.header-actions{display:flex;gap:12px;align-items:center}.app-close,.theme-toggle{display:inline-flex;align-items:center;justify-content:center;min-height:44px;padding:8px 14px;border:1px solid var(--line);border-radius:8px;background:var(--surface);color:var(--ink);font:500 14px system-ui,sans-serif;text-decoration:none;cursor:pointer}.app-close:hover,.theme-toggle:hover{background:var(--hover)}.layout{max-width:1040px;margin:8px auto 64px;display:grid;grid-template-columns:180px minmax(0,1fr);gap:32px;padding:0 32px}nav{display:flex;flex-direction:column;gap:4px;padding-top:28px;align-self:start}nav p{font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);margin:0 12px 12px}nav a{display:flex;align-items:center;min-height:44px;padding:8px 12px;border-radius:8px;color:var(--muted);text-decoration:none}nav a:hover{background:var(--hover)}nav a[aria-current=page]{background:var(--surface);color:var(--primary);font-weight:600}main{min-width:0;background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:40px 48px}h1{font-size:32px;font-weight:650;letter-spacing:-.7px;line-height:1.2;margin:0 0 16px}h2{font-size:19px;line-height:1.4;margin:32px 0 10px}p{margin:0 0 16px}code{font:inherit}.document-meta{font-size:13px;color:var(--muted);padding-bottom:24px;border-bottom:1px solid var(--line)}footer{border-top:1px solid var(--line);margin-top:36px;padding-top:20px;font-size:13px;color:var(--muted)}
@media(max-width:700px){header{padding:16px}.brand{font-size:18px}.header-actions{gap:8px}.app-close,.theme-toggle{padding:8px 10px;font-size:12px}.layout{display:block;padding:0 16px;margin-top:0}nav{flex-direction:row;flex-wrap:wrap;gap:4px;margin-bottom:16px;padding:0}nav p{display:none}nav a{font-size:14px;padding:8px 10px}main{padding:28px 24px;border-radius:12px}h1{font-size:27px}h2{margin-top:28px}}
</style></head>
<body><header><a class="brand" href="/">${escape(appName)}</a><div class="header-actions"><button class="theme-toggle" type="button" aria-label="Přepnout barevný režim">Tmavý režim</button><a class="app-close" href="/login" aria-label="Zavřít a vrátit se do aplikace">Zpět do aplikace</a></div></header><div class="layout"><nav aria-label="Právní informace"><p>Právní informace</p>${navigation}</nav><main>${content}<footer><a href="${configuredUrls.get('SUPPORT_URL').pathname}" data-legal-link>Kontakt a podpora</a></footer></main></div><script>(()=>{
const toggle=document.querySelector('.theme-toggle');
const updateToggle=()=>{toggle.textContent=document.documentElement.dataset.theme==='dark'?'Světlý režim':'Tmavý režim';};updateToggle();
toggle.addEventListener('click',()=>{const dark=document.documentElement.dataset.theme!=='dark';document.documentElement.dataset.theme=dark?'dark':'light';try{localStorage.setItem('theme',dark?'dark':'light');}catch{}updateToggle();});
const params=new URLSearchParams(window.location.search);const returnTo=params.get('returnTo');const close=document.querySelector('.app-close');
if(!returnTo||!returnTo.startsWith('/')||returnTo.startsWith('//')){close.addEventListener('click',(event)=>{event.preventDefault();window.close();window.setTimeout(()=>window.location.assign(close.href),350);});return;}
const parsedDepth=Number.parseInt(params.get('legalDepth')||'1',10);const legalDepth=Number.isSafeInteger(parsedDepth)&&parsedDepth>0?parsedDepth:1;
close.setAttribute('href',returnTo);close.addEventListener('click',(event)=>{event.preventDefault();window.setTimeout(()=>window.location.assign(returnTo),350);window.history.go(-legalDepth);});
document.querySelectorAll('[data-legal-link]').forEach((link)=>{const target=new URL(link.href);target.searchParams.set('returnTo',returnTo);target.searchParams.set('legalDepth',String(legalDepth+1));link.href=target.pathname+target.search+target.hash;});
})();</script></body></html>\n`;
}

let stale = false;
for (const page of pages) {
  const markdownText = fs.readFileSync(path.join(root, 'automation/release/legal', page.source), 'utf8');
  const target = path.join(root, 'web', page.output);
  const rendered = document(page.title, markdown(markdownText));
  if (checkOnly) {
    if (!fs.existsSync(target) || fs.readFileSync(target, 'utf8') !== rendered) {
      console.error(`Stale generated legal page: ${page.output}`);
      stale = true;
    }
  } else {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, rendered);
  }
}

if (stale) process.exit(1);
console.log(checkOnly
  ? `Verified ${pages.length} generated legal pages.`
  : `Rendered ${pages.length} legal pages.`);
