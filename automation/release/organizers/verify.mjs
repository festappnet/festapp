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
