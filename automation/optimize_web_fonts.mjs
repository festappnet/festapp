#!/usr/bin/env node

import { readFile, readdir, writeFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseKeyValueFile } from './lib/supabase_management.mjs';

// Dependencies declare these fonts even when no compiled widget uses them.
// Only remove automatic engine registration, keeping AssetManifest and assets
// intact. A future reference in main or any deferred part retains the family.
const candidates = new Map([
  ...[100, 200, 300, 400, 500, 600].map((weight) => [
    `packages/lucide_icons_flutter/Lucide${weight}`, `Lucide${weight}`,
  ]),
  ['packages/golden_toolkit/Roboto', 'golden_toolkit'],
]);

export async function optimizeWebFonts(buildDir, { fontFamilyBase = '' } = {}) {
  const entries = await readdir(buildDir);
  const executables = entries.filter((name) =>
    /^main\.dart\.js(?:_\d+\.part\.js)?$/.test(name));
  if (!executables.includes('main.dart.js')) {
    throw new Error('Missing main.dart.js; optimize fonts after Flutter compilation');
  }
  const code = await Promise.all(executables.map((name) =>
    readFile(path.join(buildDir, name), 'utf8')));
  const manifestPath = path.join(buildDir, 'assets/FontManifest.json');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  const removed = manifest.filter(({ family }) => {
    if (family === fontFamilyBase || family.split('/').at(-1) === fontFamilyBase) {
      return false;
    }
    const token = candidates.get(family);
    return token && code.every((source) => !source.includes(token));
  });
  const removedFamilies = new Set(removed.map(({ family }) => family));
  const retained = manifest.filter(({ family }) => !removedFamilies.has(family));
  const retainedAssets = new Set(retained.flatMap(({ fonts }) =>
    fonts.map(({ asset }) => asset)));
  const avoidedAssets = [...new Set(removed.flatMap(({ fonts }) =>
    fonts.map(({ asset }) => asset)))].filter((asset) => !retainedAssets.has(asset));
  const sizes = await Promise.all(avoidedAssets.map((asset) =>
    stat(path.join(buildDir, 'assets', asset))));
  if (removed.length) {
    await writeFile(manifestPath, JSON.stringify(retained));
  }
  return {
    removedFamilies: [...removedFamilies],
    avoidedStartupBytes: sizes.reduce((sum, file) => sum + file.size, 0),
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const configPath = path.resolve(process.argv[3] || 'automation/project.conf');
  const fontFamilyBase = parseKeyValueFile(configPath).get('FONT_FAMILY_BASE');
  if (!fontFamilyBase) throw new Error(`Missing FONT_FAMILY_BASE in ${configPath}`);
  const result = await optimizeWebFonts(path.resolve(process.argv[2] || 'build/web'), {
    fontFamilyBase,
  });
  console.log(`Web fonts: ${result.removedFamilies.length} unused registrations removed; ${result.avoidedStartupBytes} uncompressed startup bytes avoided`);
}
