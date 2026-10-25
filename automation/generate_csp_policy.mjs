#!/usr/bin/env node
// One policy owner. Run only after every HTML/version transformation.
import { createHash } from 'node:crypto';
import { readFile, writeFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from '../web_client/node_modules/parse5/dist/index.js';

import { BASE_POLICY, CSP_MODE, scriptPolicy, headerBlock } from './lib/csp_policy.mjs';
export { BASE_POLICY, scriptPolicy, headerBlock };
export function inlineHashes(html) {
  const hashes = new Set();
  function visit(node) {
    if (node.tagName === 'script' && !node.attrs.some(a => a.name === 'src')) {
      const body = node.childNodes.map(n => n.value || '').join('');
      hashes.add("'sha256-" + createHash('sha256').update(body).digest('base64') + "'");
    }
    for (const child of node.childNodes || []) visit(child);
  }
  visit(parse(html));
  return [...hashes].sort();
}
export async function generateManifest(dir, target = 'cloudflare') {
  const entries = { webclient: target === 'cloudflare' ? 'webclient' : 'index.html', flutter: target === 'cloudflare' ? 'flutter' : 'flutter.html', auth_bridge: target === 'cloudflare' ? 'auth_bridge' : 'auth_bridge.html' };
  // The renderer removes this optional document for other tenants. Every
  // document that actually ships still receives its own bound CSP profile.
  try {
    if ((await stat(path.join(dir, 'organizers-page'))).isFile()) entries.organizers = 'organizers-page';
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  try {
    const marketing = JSON.parse(await readFile(path.join(dir,'organizer-pages.json'),'utf8'));
    for (const page of marketing.pages.filter(page=>page.id !== 'home')) entries['organizer-' + page.id] = page.asset.slice(1);
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const documents = {};
  const profiles = {};
  async function add(file, profile) {
    const html = await readFile(path.join(dir, file), 'utf8');
    const hashes = inlineHashes(html);
    documents[file] = { profile, sha256: createHash('sha256').update(html).digest('hex'), hashes };
    profiles[profile] = { policy: scriptPolicy(profile, hashes, /<script\b[^>]*src=["']https:\/\/static\.cloudflareinsights\.com\/beacon\.min\.js["']/i.test(html)) };
  }
  for (const [profile, file] of Object.entries(entries)) await add(file, profile);
  // Legal/static documents are also served by ASSETS and must not escape CSP.
  async function scan(relative = '') {
    for (const entry of await readdir(path.join(dir, relative), { withFileTypes: true })) {
      const file = path.posix.join(relative, entry.name);
      if (entry.isDirectory()) await scan(file);
      else if (entry.name.endsWith('.html') && !documents[file]) await add(file, 'static-' + Object.keys(documents).length);
    }
  }
  await scan();
  profiles.none = { policy: scriptPolicy('none', []) };
  return { schemaVersion: 1, mode: CSP_MODE, basePolicy: BASE_POLICY, documents, profiles };
}
export async function verifyManifest(dir) {
  const actual = JSON.parse(await readFile(path.join(dir, 'csp-manifest.json'), 'utf8'));
  const target = actual.documents.webclient ? 'cloudflare' : 'static';
  const expected = await generateManifest(dir, target);
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error('CSP manifest differs from final HTML/scripts/policy; regenerate after all transformations');
  return actual;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const dir = path.resolve(process.argv[2]);
  const manifest = await generateManifest(dir, process.argv[3]);
  await writeFile(path.join(dir, 'csp-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  const file = path.join(dir, '_headers');
  const template = await readFile(new URL('./lib/web_headers.template', import.meta.url), 'utf8');
  let headers = template.replace('/*\n', `/*\n  Content-Security-Policy: ${BASE_POLICY}\n`);
  for (const [file, doc] of Object.entries(manifest.documents)) {
    headers += '\n/' + file + '\n' + headerBlock(manifest.profiles[doc.profile].policy, doc.profile);
  }
  // Static rewrites must apply policy to document destinations, not URL prefixes.
  if (process.argv[3] === 'static') {
    headers += '\n/\n' + headerBlock(manifest.profiles.webclient.policy, 'webclient');
  }
  await writeFile(file, headers);
}
