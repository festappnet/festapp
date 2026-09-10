import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { collectPwaShellManifest } from '../lib/pwa_shell_manifest.mjs';

test('worker and budget share normalized resource sets and raw bytes', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'festapp-manifest-'));
  try {
    await mkdir(path.join(root, 'privacy'));
    await writeFile(path.join(root, 'flutter'), 'flutter');
    await writeFile(path.join(root, 'webclient'), 'web');
    await writeFile(path.join(root, 'main.dart.js'), 'main');
    await writeFile(path.join(root, 'main.dart.1.0.0-1.js'), 'diagnostic-copy');
    await writeFile(path.join(root, 'asset.bin'), 'asset');
    await writeFile(path.join(root, 'backend-activation.json'), 'activation');
    await writeFile(path.join(root, 'client-sync-config.json'), 'runtime');
    await writeFile(path.join(root, 'privacy/index.html'), 'privacy');
    const manifest = await collectPwaShellManifest(root);
    assert.deepEqual(manifest.knownResources, [
      '/asset.bin', '/flutter?pwa-cache=1', '/main.dart.js', '/privacy/',
      '/webclient?pwa-cache=1',
    ]);
    assert.ok(!manifest.knownResources.includes('/backend-activation.json'));
    assert.ok(!manifest.knownResources.includes('/client-sync-config.json'));
    assert.deepEqual(manifest.coreResources, [
      '/flutter?pwa-cache=1', '/main.dart.js', '/privacy/', '/webclient?pwa-cache=1',
    ]);
    assert.equal(manifest.knownBytes, 26);
    assert.equal(manifest.coreBytes, 21);

    const configPath = path.join(root, 'project.conf');
    await writeFile(configPath,
      'PWA_CORE_CACHE_BUDGET_BYTES=20\nPWA_KNOWN_CACHE_BUDGET_BYTES=25\n');
    const gate = spawnSync(process.execPath, [
      path.resolve(import.meta.dirname, '../check_pwa_shell_budget.mjs'),
      root,
      configPath,
    ], { encoding: 'utf8' });
    assert.notEqual(gate.status, 0);
    assert.match(gate.stderr, /PWA cache budget exceeded/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
