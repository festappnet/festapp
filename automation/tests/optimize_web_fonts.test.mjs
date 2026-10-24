import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { optimizeWebFonts } from '../optimize_web_fonts.mjs';

async function fixture(run) {
  const root = await mkdtemp(path.join(tmpdir(), 'festapp-font-registration-'));
  try {
    await mkdir(path.join(root, 'assets'));
    const families = ['MaterialIcons', 'Futura',
      'packages/lucide_icons_flutter/Lucide',
      'packages/lucide_icons_flutter/Lucide100',
      'packages/lucide_icons_flutter/Lucide200',
      'packages/golden_toolkit/Roboto', 'packages/shadcn_ui/GeistMono'];
    const manifest = families.map((family, index) => ({ family,
      fonts: [{ asset: `font-${index}.ttf` }] }));
    for (const entry of manifest) {
      await writeFile(path.join(root, 'assets', entry.fonts[0].asset), 'font');
    }
    await writeFile(path.join(root, 'assets/FontManifest.json'), JSON.stringify(manifest));
    await writeFile(path.join(root, 'assets/AssetManifest.bin'), 'unchanged asset index');
    await writeFile(path.join(root, 'main.dart.js'), 'Lucide Futura MaterialIcons');
    await run(root, manifest);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test('avoids unused dependency fonts at startup while preserving usable assets and typography', async () => {
  await fixture(async (root) => {
    const result = await optimizeWebFonts(root);
    assert.equal(result.removedFamilies.length, 3);
    assert.equal(result.avoidedStartupBytes, 12);
    const kept = JSON.parse(await readFile(path.join(root, 'assets/FontManifest.json'), 'utf8'));
    assert.deepEqual(kept.map(({ family }) => family), [
      'MaterialIcons', 'Futura', 'packages/lucide_icons_flutter/Lucide',
      'packages/shadcn_ui/GeistMono',
    ]);
    assert.equal(await readFile(path.join(root, 'assets/font-3.ttf'), 'utf8'), 'font');
    assert.equal(await readFile(path.join(root, 'assets/AssetManifest.bin'), 'utf8'), 'unchanged asset index');
    assert.equal((await optimizeWebFonts(root)).removedFamilies.length, 0);
  });
});

test('a family referenced only by a deferred module remains registered', async () => {
  await fixture(async (root) => {
    await writeFile(path.join(root, 'main.dart.js_3.part.js'), 'Lucide200 golden_toolkit');
    const result = await optimizeWebFonts(root);
    assert.deepEqual(result.removedFamilies, ['packages/lucide_icons_flutter/Lucide100']);
  });
});

test('missing compiled entry fails before changing the font manifest', async () => {
  await fixture(async (root, manifest) => {
    await rm(path.join(root, 'main.dart.js'));
    await assert.rejects(optimizeWebFonts(root), /Missing main.dart.js/);
    assert.deepEqual(JSON.parse(await readFile(path.join(root, 'assets/FontManifest.json'), 'utf8')), manifest);
  });
});

test('the selected tenant font is preserved even when it matches an unused dependency family', async () => {
  await fixture(async (root) => {
    const configPath = path.join(root, 'selected-tenant.conf');
    await writeFile(configPath, 'FONT_FAMILY_BASE="Lucide100"\nFONT_FILES=fonts/Tenant-Regular.ttf\n');
    execFileSync(process.execPath, [
      fileURLToPath(new URL('../optimize_web_fonts.mjs', import.meta.url)),
      root, configPath,
    ], { stdio: 'pipe' });
    const kept = JSON.parse(await readFile(path.join(root, 'assets/FontManifest.json'), 'utf8'));
    assert.ok(kept.some(({ family }) => family === 'packages/lucide_icons_flutter/Lucide100'));
    assert.ok(!kept.some(({ family }) => family === 'packages/lucide_icons_flutter/Lucide200'));
  });
});

test('missing tenant font configuration fails without changing registrations', async () => {
  await fixture(async (root, manifest) => {
    assert.throws(() => execFileSync(process.execPath, [
      fileURLToPath(new URL('../optimize_web_fonts.mjs', import.meta.url)),
      root, path.join(root, 'missing.conf'),
    ], { stdio: 'pipe' }));
    assert.deepEqual(JSON.parse(await readFile(path.join(root, 'assets/FontManifest.json'), 'utf8')), manifest);
  });
});
