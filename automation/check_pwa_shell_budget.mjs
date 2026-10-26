#!/usr/bin/env node

import path from 'node:path';
import { collectPwaShellManifest } from './lib/pwa_shell_manifest.mjs';
import { parseKeyValueFile } from './lib/supabase_management.mjs';

const buildDir = path.resolve(process.argv[2] || 'build/web');
const config = parseKeyValueFile(path.resolve(process.argv[3] || 'automation/project.conf'));
const coreLimit = Number(config.get('PWA_CORE_CACHE_BUDGET_BYTES'));
const knownLimit = Number(config.get('PWA_KNOWN_CACHE_BUDGET_BYTES'));
if (!Number.isSafeInteger(coreLimit) || coreLimit <= 0 ||
    !Number.isSafeInteger(knownLimit) || knownLimit <= 0) {
  throw new Error('PWA core and known cache budgets must be configured as integer bytes');
}

const manifest = await collectPwaShellManifest(buildDir);
console.log(`PWA cache budget: core ${manifest.coreResources.length} files / ${manifest.coreBytes} bytes; known ${manifest.knownResources.length} files / ${manifest.knownBytes} bytes`);
if (manifest.coreBytes > coreLimit || manifest.knownBytes > knownLimit) {
  throw new Error(`PWA cache budget exceeded (limits: core ${coreLimit}, known ${knownLimit})`);
}
