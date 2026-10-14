import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import vm from 'node:vm';
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

test('precache contains the immutable main selected by the deployed Flutter HTML', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'festapp-main-identity-'));
  try {
    await writeFile(path.join(root, 'flutter'), 'flutter');
    await writeFile(path.join(root, 'webclient'), 'web');
    await writeFile(path.join(root, 'main.dart.js'), 'main');
    await writeFile(path.join(root, 'main.dart.1.0.0-1.js'), 'main');
    await writeFile(path.join(root, 'main.dart.0.9.0-9.js'), 'old');
    await writeFile(path.join(root, 'festapp-version.json'), JSON.stringify({
      version: '1.0.0+1', main: 'main.dart.1.0.0-1.js',
    }));
    await writeFile(path.join(root, 'festapp_flutter_bootstrap_guard.js'), 'guard');
    const manifest = await collectPwaShellManifest(root);
    assert.ok(manifest.coreResources.includes('/main.dart.1.0.0-1.js'),
      'the exact executable requested by Flutter must be installed before handoff');
    assert.ok(!manifest.knownResources.includes('/main.dart.js'),
      'do not duplicate the same executable under the mutable alias');
    assert.ok(!manifest.knownResources.includes('/main.dart.0.9.0-9.js'));
    assert.ok(manifest.coreResources.includes('/festapp_flutter_bootstrap_guard.js'));

    const generated = spawnSync(process.execPath, [
      path.resolve(import.meta.dirname, '../generate_pwa_service_worker.mjs'),
      root, '1.0.0+1',
    ], { encoding: 'utf8' });
    assert.equal(generated.status, 0, generated.stderr);
    const workerSource = await readFile(path.join(root, 'festapp_service_worker.js'), 'utf8');
    const handlers = {};
    const entries = new Map();
    const key = (request) => new URL(request.url || request, 'https://app.test').pathname;
    const cache = {
      async addAll(urls) {
        for (const url of urls) {
          entries.set(key(url), new Response(await readFile(path.join(root, key(url).slice(1)))));
        }
      },
      async match(request) { return entries.get(key(request))?.clone(); },
      async put(request, response) { entries.set(key(request), response.clone()); },
    };
    const context = {
      URL, Request, Response, Promise, setTimeout, clearTimeout,
      caches: { open: async () => cache, keys: async () => [] },
      fetch: async () => { throw new Error('offline mobile handoff'); },
      self: {
        location: { origin: 'https://app.test' }, navigator: { onLine: false },
        addEventListener: (type, handler) => { handlers[type] = handler; },
      },
    };
    vm.runInNewContext(workerSource, context);
    let installation;
    handlers.install({ waitUntil: (promise) => { installation = promise; } });
    await installation;
    function fetchThroughWorker(request) {
      let response;
      handlers.fetch({ request, clientId: 'mobile', resultingClientId: 'mobile',
        respondWith: (promise) => { response = promise; } });
      return response;
    }
    const navigation = new Request('https://app.test/login?redirect=/unit/1003/edit');
    Object.defineProperty(navigation, 'mode', { value: 'navigate' });
    assert.equal(await (await fetchThroughWorker(navigation)).text(), 'flutter');
    assert.equal(await (await fetchThroughWorker(new Request(
      'https://app.test/main.dart.1.0.0-1.js'))).text(), 'main',
      'homepage-to-Flutter handoff must load the exact main while the network is unavailable');
    assert.equal(await (await fetchThroughWorker(new Request(
      'https://app.test/festapp_flutter_bootstrap_guard.js'))).text(), 'guard');

  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
