import {publicHelpRoot} from '../../../web_client/src/services/help_action_routes.js';
import {documentLocales, localizedAssets, publicAlternates, publicLanguageUrl, readPublicProfiles} from './public_languages.mjs';
import {pressAssetBase, pressLogos, logoFilename} from './press.mjs';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { readConfig, resolveContext, publicManifest, marketingMedia } from './context.mjs';
const escape = value => String(value).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function verifyMarketingHtml(html, page, context) {
  assert.ok(html.includes(`<html lang="${page.locale ?? context.locale}">`), 'marketing locale');
  assert.ok(html.includes(`<title>${escape(page.title)}</title>`), 'marketing title');
  assert.ok(html.includes(`rel="canonical" href="${page.canonical}"`), 'marketing canonical');
  assert.equal((html.match(/<h1[ >]/g) ?? []).length, 1, 'marketing heading');
  if (page.heading) {
    const heading=html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1].replace(/<[^>]+>/g,'').replace(/\s+/g,' ').trim();
    assert.equal(heading,escape(page.heading),'own topic heading');
  }
  assert.ok(!html.includes('{{'), 'unresolved marketing text');
}
export async function verifyMarketingBundle(buildDir, configPath) {
  const context = resolveContext(readConfig(configPath));
  const manifest = JSON.parse(await fs.readFile(path.join(buildDir,'organizer-pages.json'),'utf8'));
  assert.deepEqual(manifest, publicManifest(context), 'marketing registry differs from configuration');
  for (const media of marketingMedia(context)) await fs.access(path.join(buildDir,new URL(media,context.origin).pathname));
  for (const page of context.pages) verifyMarketingHtml(await fs.readFile(path.join(buildDir,page.asset),'utf8'),page,context);
  if (context.pages.some(page=>page.id==='press')) {
    for (const name of [...pressLogos.flatMap(logo=>[false,true].flatMap(dark=>['svg',...(logo.png?['png']:[])].map(format=>logoFilename(logo,dark,format)))),'vstupenky-online-loga.zip','pouziti-loga.txt','o-projektu.txt']) await fs.access(path.join(buildDir,pressAssetBase,name));
  }
  if (context.updates) assert.deepEqual(JSON.parse(await fs.readFile(path.join(buildDir,'platform-updates.json'),'utf8')),context.updates.feed,'updates feed');
  return context;
}

export async function localizedPublicDocuments(config) {
  const profiles = readPublicProfiles();
  const locales = documentLocales(config, profiles);
  if (locales.length < 2) return [];
  const primary = profiles[config.WEB_ORGANIZER_CONTENT_PROFILE];
  const home = resolveContext(config).pages[0];
  const publication = [{path: home.path, asset: home.asset, locales}];
  const helpLocales = locales.filter((locale, index) => index === 0 || profiles[primary.translations[locale]]?.help);
  if (primary.help && helpLocales.length > 1) {
    const helpRoot = publicHelpRoot(locales[0]);
    const read = async file => JSON.parse(await fs.readFile(new URL('../help/' + file, import.meta.url), 'utf8'));
    const pages = await read(primary.help.pages);
    const categories = (await read(primary.help.categories ?? 'categories.json'))
      .map(row => primary.help.categories ? row : row[locales[0]]);
    for (const {slug} of [...pages, ...categories]) {
      const route = helpRoot + (slug ? slug + '/' : '');
      publication.push({path:route, asset:route + 'index.html', locales:helpLocales});
    }
  }
  const {origin} = new URL(config.WEB_LINK);
  return publication.flatMap(doc => doc.locales.map((locale, index) => {
    const route = publicLanguageUrl(doc.path, locale, doc.locales[0]);
    return { ...doc, route, locale, canonical:new URL(route, origin).href,
      alternates:publicAlternates(origin, doc.path, doc.locales),
      file: (index === 0 ? doc.asset : localizedAssets + '/' + locale + doc.asset).slice(1) };
  }));
}

export function verifyLocalizedHtml(html, doc) {
  assert.ok(html.includes(`<html lang="${doc.locale}">`), `document language ${doc.route}`);
  assert.ok(html.includes(`rel="canonical" href="${escape(doc.canonical)}"`), `document canonical ${doc.route}`);
  assert.ok(html.includes(doc.alternates), `reciprocal language links ${doc.route}`);
}

export async function verifyLocalizedPublicBundle(buildDir, config, cspManifest) {
  const docs = await localizedPublicDocuments(config);
  for (const doc of docs) {
    assert.ok(cspManifest.documents[doc.file]?.profile, `document CSP ${doc.route}`);
    verifyLocalizedHtml(await fs.readFile(path.join(buildDir, doc.file), 'utf8'), doc);
  }
}
