import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { readConfig, resolveContext, publicManifest, marketingMedia } from './context.mjs';
const escape = value => String(value).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function verifyMarketingHtml(html, page, context) {
  assert.ok(html.includes(`<html lang="${context.locale}">`), 'marketing locale');
  assert.ok(html.includes(`<title>${escape(page.title)}</title>`), 'marketing title');
  assert.ok(html.includes(`rel="canonical" href="${page.canonical}"`), 'marketing canonical');
  assert.equal((html.match(/<h1[ >]/g) ?? []).length, 1, 'marketing heading');
  if (page.heading) assert.ok(html.includes(escape(page.heading)), 'own topic content');
  assert.ok(!html.includes('{{'), 'unresolved marketing text');
}
export async function verifyMarketingBundle(buildDir, configPath) {
  const context = resolveContext(readConfig(configPath));
  const manifest = JSON.parse(await fs.readFile(path.join(buildDir,'organizer-pages.json'),'utf8'));
  assert.deepEqual(manifest, publicManifest(context), 'marketing registry differs from configuration');
  for (const media of marketingMedia(context)) await fs.access(path.join(buildDir,new URL(media,context.origin).pathname));
  for (const page of context.pages) verifyMarketingHtml(await fs.readFile(path.join(buildDir,page.asset),'utf8'),page,context);
  return context;
}
