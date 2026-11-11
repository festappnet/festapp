import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';

// Inspect the actual Vite document after tenant generation and bundle assembly.
export async function verifyBundleEntries(directory, html) {
  const entries = [...html.matchAll(/<script\b([^>]*)>/gi)]
    .map(([, attributes]) => ({
      type: attributes.match(/\btype=["']([^"']+)["']/i)?.[1],
      src: attributes.match(/\bsrc=["']([^"']+)["']/i)?.[1],
    }))
    .filter(({type}) => type === 'module');
  assert.ok(entries.length > 0, 'built web document lacks an executable module entry');
  for (const {src} of entries) {
    assert.ok(src, 'built web module must have an immutable asset URL');
    const url = new URL(src, 'https://bundle.invalid/');
    assert.equal(url.origin, 'https://bundle.invalid', 'web module must belong to this bundle');
    assert.match(url.pathname, /^\/web-assets\/[A-Za-z0-9_.-]+\.js$/, 'web entry must reference a built Vite module');
    const bytes = await readFile(path.join(directory, decodeURIComponent(url.pathname)));
    assert.ok(bytes.length > 0, 'built web module is empty');
  }
}
