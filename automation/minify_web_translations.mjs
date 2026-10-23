#!/usr/bin/env node

import { readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

/** Remove JSON formatting from built catalogs while retaining every translation. */
export async function minifyWebTranslations(buildDir) {
  const directory = path.join(buildDir, 'assets/translations');
  const files = (await readdir(directory, { withFileTypes: true }))
    .filter(entry => entry.isFile() && entry.name.endsWith('.json'));
  let beforeBytes = 0, afterBytes = 0;
  for (const { name } of files) {
    const file = path.join(directory, name);
    const original = await readFile(file, 'utf8');
    const compact = JSON.stringify(JSON.parse(original)) + '\n';
    const before = Buffer.byteLength(original), after = Buffer.byteLength(compact);
    beforeBytes += before;
    if (after < before) await writeFile(file, compact);
    afterBytes += Math.min(before, after);
  }
  return { files: files.length, beforeBytes, afterBytes };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const result = await minifyWebTranslations(path.resolve(process.argv[2] || 'build/web'));
  console.log(`Web translations: ${result.files} catalogs, ${result.beforeBytes - result.afterBytes} formatting bytes removed`);
}
