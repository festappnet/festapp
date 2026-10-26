#!/usr/bin/env node

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const index = await readFile(new URL('../../web/index.html', import.meta.url), 'utf8');
const installHandler = index.match(
  /window\.addEventListener\('beforeinstallprompt',[\s\S]*?\n\s*}\);/,
)?.[0];

assert.ok(installHandler, 'web/index.html must listen for beforeinstallprompt');
assert.doesNotMatch(
  installHandler,
  /preventDefault\(/,
  'the app must not suppress Chrome\'s native PWA installation affordance',
);
assert.match(
  installHandler,
  /deferredPrompt\s*=\s*e/,
  'the in-app install button should retain the prompt event as a fallback',
);

console.log('PASS native and in-app PWA installation affordances stay available');
