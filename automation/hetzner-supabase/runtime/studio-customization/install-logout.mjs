#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const studioRoot = process.env.FESTAPP_STUDIO_ROOT || '/app/apps/studio';
const chunksRoot = path.join(studioRoot, '.next/server/chunks/ssr');
const pagesRoot = path.join(studioRoot, '.next/server/pages');
const sourceAsset = process.env.FESTAPP_STUDIO_LOGOUT_ASSET || '/opt/festapp-studio/logout.js';
const targetAsset = path.join(studioRoot, 'public/festapp-admin/logout.js');
const documents = [
  ['children:[(0,b.jsx)(c.Main,{}),(0,b.jsx)(c.NextScript,{})]', 'b'],
  ['children:[(0,d.jsx)(f.r,{}),(0,d.jsx)(e.Main,{}),(0,d.jsx)(e.NextScript,{})]', 'd'],
].map(([original, jsx]) => ({ original,
  patched: original.slice(0, -1) + `,(0,${jsx}.jsx)("script",{src:"/festapp-admin/logout.js",defer:!0})]`,
}));

const javascriptFiles = fs.readdirSync(chunksRoot)
  .filter((name) => name.endsWith('.js'))
  .map((name) => path.join(chunksRoot, name));
const originalMatches = javascriptFiles.flatMap(file => documents
  .filter(document => fs.readFileSync(file, 'utf8').includes(document.original))
  .map(document => ({ file, document })));
const patchedMatches = javascriptFiles.flatMap(file => documents
  .filter(document => fs.readFileSync(file, 'utf8').includes(document.patched))
  .map(document => ({ file, document })));

if (originalMatches.length + patchedMatches.length !== 1) {
  throw new Error(
    `Expected one pinned Studio document chunk, found ${originalMatches.length + patchedMatches.length}`,
  );
}

if (originalMatches.length === 1) {
  const { file: documentChunk, document } = originalMatches[0];
  const source = fs.readFileSync(documentChunk, 'utf8');
  const patched = source.replace(document.original, document.patched);
  if (patched === source || patched.split('/festapp-admin/logout.js').length !== 2) {
    throw new Error('Failed to install the pinned Studio logout script reference');
  }
  fs.writeFileSync(documentChunk, patched);
}

function filesBelow(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    return entry.isDirectory() ? filesBelow(entryPath) : [entryPath];
  });
}

const exportedPages = filesBelow(pagesRoot).filter((file) => file.endsWith('.html'));
if (exportedPages.length === 0) {
  throw new Error('Pinned Studio image contains no exported HTML pages');
}
for (const page of exportedPages) {
  const html = fs.readFileSync(page, 'utf8');
  if (html.includes('/festapp-admin/logout.js')) continue;
  if (!html.includes('</body>')) {
    throw new Error(`Exported Studio page has no body element: ${page}`);
  }
  fs.writeFileSync(
    page,
    html.replace('</body>', '<script src="/festapp-admin/logout.js" defer></script></body>'),
  );
}

fs.mkdirSync(path.dirname(targetAsset), { recursive: true });
fs.copyFileSync(sourceAsset, targetAsset);
