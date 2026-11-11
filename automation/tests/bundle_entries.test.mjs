import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {verifyBundleEntries} from '../lib/verify_bundle_entries.mjs';

test('assembled web document must resolve a nonempty module in this tenant bundle', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'festapp-bundle-'));
  try {
    await mkdir(path.join(directory, 'web-assets'));
    const entry = path.join(directory, 'web-assets/main-123.js');
    await writeFile(entry, 'export const startup = true;');
    const html = '<script type="module" crossorigin src="/web-assets/main-123.js"></script>';
    await verifyBundleEntries(directory, html);
    for (const invalid of ['', html.replace('main-123', 'missing'),
      html.replace('/web-assets/', 'https://foreign.invalid/web-assets/'),
      html.replace('/web-assets/main-123.js', '/source.js')]) {
      await assert.rejects(verifyBundleEntries(directory, invalid));
    }
    await writeFile(entry, '');
    await assert.rejects(verifyBundleEntries(directory, html), /empty/);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});
