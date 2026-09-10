#!/usr/bin/env node

import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import vm from 'node:vm';

const projectRoot = path.resolve(import.meta.dirname, '../..');
const tempRoot = await mkdtemp(path.join(tmpdir(), 'festapp-pwa-'));

try {
  await mkdir(path.join(tempRoot, 'assets'), { recursive: true });
  await mkdir(path.join(tempRoot, 'privacy'), { recursive: true });
  await writeFile(path.join(tempRoot, 'flutter'), '<html>flutter</html>');
  await writeFile(path.join(tempRoot, 'webclient'), '<html>web</html>');
  await writeFile(path.join(tempRoot, 'main.dart.js'), 'main');
  await writeFile(path.join(tempRoot, 'main.dart.js_7.part.js'), 'deferred');
  await writeFile(path.join(tempRoot, 'main.dart.1.2.3-4.js'), 'duplicate');
  await writeFile(path.join(tempRoot, 'flutter_service_worker.js'), 'obsolete');
  await writeFile(path.join(tempRoot, '_worker.js'), 'server only');
  await writeFile(path.join(tempRoot, 'assets', 'translation.json'), '{}');
  await writeFile(
    path.join(tempRoot, 'privacy', 'index.html'),
    '<html>privacy policy</html>',
  );

  const result = spawnSync(process.execPath, [
    path.join(projectRoot, 'automation/generate_pwa_service_worker.mjs'),
    tempRoot,
    '1.2.3+4',
    'csmostrava2026',
  ], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr);
  const worker = (await readFile(
    path.join(tempRoot, 'festapp_service_worker.js'),
    'utf8',
  )).replace(
    'const CLIENT_VERSION_REPORT_TIMEOUT_MS = 1000;',
    'const CLIENT_VERSION_REPORT_TIMEOUT_MS = 10;',
  );
  assert.match(worker, /festapp-app-shell-1\.2\.3\+4/);
  assert.match(worker, /"\/flutter\?pwa-cache=1"/);
  assert.match(worker, /"\/webclient\?pwa-cache=1"/);
  assert.match(worker, /"\/main\.dart\.js"/);
  assert.match(worker, /"\/main\.dart\.js_7\.part\.js"/);
  assert.match(worker, /"\/assets\/translation\.json"/);
  assert.doesNotMatch(worker, /main\.dart\.1\.2\.3-4\.js/);
  assert.doesNotMatch(worker, /"\/flutter_service_worker\.js"/);
  assert.doesNotMatch(worker, /"\/_worker\.js"/);
  assert.match(worker, /request\.mode === 'navigate'/);
  assert.match(worker, /cache\.match\(request, \{ ignoreSearch: true \}\)/);
  assert.match(worker, /event\.data === 'SKIP_WAITING'/);
  assert.match(worker, /FESTAPP_QUERY_BUILD_VERSION/);
  assert.match(worker, /url\.pathname === '\/festapp-version\.json'/);
  assert.match(worker, /url\.pathname === '\/backend-activation\.json'/);
  assert.match(worker, /url\.pathname === '\/client-sync-config\.json'/);
  assert.match(worker, /fetch\(request, \{ cache: 'no-store' \}\)/);
  assert.match(worker, /url\.origin === 'https:\/\/fonts\.gstatic\.com'/);
  assert.match(worker, /url\.origin === 'https:\/\/fonts\.googleapis\.com'/);
  assert.match(worker, /festapp-used-fonts-v1/);
  assert.match(worker, /festapp-app-shell-0\.19\.85\+418/);
  assert.match(worker, /event\.resultingClientId \|\| event\.clientId/);
  assert.match(worker, /if \(emergencyCutover\)/);
  assert.match(worker, /const FORCED_OCCASION_PATH = "\/csmostrava2026\/event";/);
  assert.match(worker, /cache\.put\(request, response\.clone\(\)\)/);
  const coreUrls = JSON.parse(worker.match(/const CORE_URLS = (\[[\s\S]*?\]);/)[1]);
  const precacheUrls = JSON.parse(
    worker.match(/const PRECACHE_URLS = (\[[\s\S]*?\]);/)[1],
  );
  assert.ok(!precacheUrls.includes('/backend-activation.json'),
    'backend activation must not be part of the app-shell precache');
  assert.ok(!precacheUrls.includes('/client-sync-config.json'),
    'client sync runtime config must not be part of the app-shell precache');
  assert.ok(coreUrls.includes('/main.dart.js'));
  assert.ok(coreUrls.includes('/flutter?pwa-cache=1'));
  assert.ok(coreUrls.includes('/privacy/'),
    'standalone documents must be available before their first navigation');
  assert.ok(coreUrls.includes('/main.dart.js_7.part.js'),
    'every deferred executable must be installed for offline cold-start routes');

  const genericRoot = await mkdtemp(path.join(tmpdir(), 'festapp-pwa-generic-'));
  try {
    await writeFile(path.join(genericRoot, 'flutter'), '<html>flutter</html>');
    await writeFile(path.join(genericRoot, 'webclient'), '<html>web</html>');
    await writeFile(path.join(genericRoot, 'main.dart.js'), 'main');
    const genericResult = spawnSync(process.execPath, [
      path.join(projectRoot, 'automation/generate_pwa_service_worker.mjs'),
      genericRoot,
      '1.2.3+4',
    ], { encoding: 'utf8' });
    assert.equal(genericResult.status, 0, genericResult.stderr);
    const genericWorker = await readFile(
      path.join(genericRoot, 'festapp_service_worker.js'),
      'utf8',
    );
    assert.match(genericWorker, /const FORCED_OCCASION_PATH = null;/);
  } finally {
    await rm(genericRoot, { recursive: true, force: true });
  }

  const handlers = {};
  const fontUrl = 'https://fonts.gstatic.com/s/notocoloremoji/test.woff2';
  const cachedFont = new Response('cached emoji font');
  const cachedShell = new Response('<html>offline shell</html>');
  const cachedWebClient = new Response('<html>generic event list</html>');
  const cachedPrivacy = new Response('<html>privacy policy</html>');
  let networkCalls = 0;
  let activationNetworkCalls = 0;
  let activationDocument = '{"schemaVersion":1,"tenantId":"test","generation":1,"backend":"legacy"}\n';
  let serverVersion = '1.2.3+5';
  let cachePutFails = false;
  const cachedPuts = [];
  const deletedCaches = [];
  const openedCaches = [];
  let cacheNames = [
    'festapp-app-shell-1.2.3+2',
    'festapp-app-shell-1.2.3+3',
    'festapp-app-shell-1.2.3+4',
    'festapp-used-fonts-v1',
  ];
  let claimedExistingClients = 0;
  const navigatedClients = [];
  const clientsById = new Map([
    ['updating-tab', {
      id: 'updating-tab',
      url: 'https://app.test/csmostrava2026/news',
      navigate: async (url) => { navigatedClients.push(['updating-tab', url]); },
      postMessage: () => {},
    }],
    ['older-open-tab', {
      id: 'older-open-tab',
      url: 'https://app.test/csmostrava2026/news',
      navigate: async (url) => { navigatedClients.push(['older-open-tab', url]); },
      postMessage: () => {},
    }],
  ]);
  const cache = {
    addAll: async () => {},
    put: async (request) => {
      if (cachePutFails) throw new Error('storage quota exceeded');
      cachedPuts.push(String(request.url || request));
    },
    match: async (request) => {
      const url = typeof request === 'string' ? request : request.url;
      if (url === fontUrl) return cachedFont.clone();
      if (url.includes('/flutter?pwa-cache=1')) return cachedShell.clone();
      if (url.includes('/webclient?pwa-cache=1')) return cachedWebClient.clone();
      if (url === '/privacy/') return cachedPrivacy.clone();
      if (url.includes('/assets/translation.json')) return new Response('{}');
      return undefined;
    },
  };
  const context = {
    URL,
    Request,
    Response,
    Promise,
    setTimeout,
    clearTimeout,
    caches: {
      open: async (name) => {
        openedCaches.push(name);
        return cache;
      },
      keys: async () => [...cacheNames],
      delete: async (name) => {
        deletedCaches.push(name);
        cacheNames = cacheNames.filter((candidate) => candidate !== name);
        return true;
      },
    },
    fetch: async (request) => {
      const url = String(request.url || request);
      if (url.includes('/backend-activation.json')) {
        activationNetworkCalls++;
        if (!context.self.navigator.onLine) throw new Error('offline');
        return new Response(activationDocument, {
          headers: { 'content-type': 'application/json' },
        });
      }
      networkCalls++;
      if (url.includes('/festapp-version.json')) {
        return new Response(JSON.stringify({ version: serverVersion }), {
          headers: { 'content-type': 'application/json' },
        });
      }
      if (url.includes('/main.dart.js')) {
        return new Response('recovered current executable');
      }
      throw new Error(`unexpected network request: ${url}`);
    },
    self: {
      location: { origin: 'https://app.test' },
      navigator: { onLine: false },
      clients: {
        claim: async () => { claimedExistingClients++; },
        get: async (id) => clientsById.get(id),
        matchAll: async () => [...clientsById.values()],
      },
      skipWaiting: async () => {},
      addEventListener: (type, handler) => { handlers[type] = handler; },
    },
  };
  vm.runInNewContext(worker, context);

  async function dispatchFetch(request, clientId = '', resultingClientId = '') {
    let responsePromise;
    handlers.fetch({
      request,
      clientId,
      resultingClientId,
      respondWith: (promise) => { responsePromise = promise; },
    });
    assert.ok(responsePromise, `worker did not handle ${request.url}`);
    return responsePromise;
  }

  async function reportVersion(client, version) {
    let pending = Promise.resolve();
    handlers.message({
      data: { type: 'FESTAPP_CLIENT_VERSION', version },
      source: client,
      waitUntil: (promise) => { pending = promise; },
    });
    await pending;
  }

  // The requesting tab needs controllerchange so its existing update script
  // can reload it. Other tabs are claimed too, but must remain mapped to the
  // cache generation from which their JavaScript is already executing.
  handlers.message({
    data: 'SKIP_WAITING',
    source: {id: 'updating-tab'},
  });

  // Claim both tabs so the updating tab's next navigation cannot fall back
  // through the old worker. Keep the other tab pinned to its original shell;
  // both tabs share Cache Storage and it can still request deferred chunks.
  let activation;
  handlers.activate({ waitUntil: (promise) => { activation = promise; } });
  await activation;
  assert.equal(claimedExistingClients, 1);
  assert.deepEqual(deletedCaches, []);

  // A cold navigation has no clientId: the newly created page is identified
  // by resultingClientId. Its first scripts must inherit the navigation's
  // current shell without waiting for a report from a script that has not yet
  // been allowed to load.
  const freshNavigation = new Request('https://app.test/csmostrava2026/');
  Object.defineProperty(freshNavigation, 'mode', { value: 'navigate' });
  const freshShellResponse = await dispatchFetch(
    freshNavigation,
    '',
    'fresh-tab',
  );
  assert.equal(await freshShellResponse.text(), '<html>offline shell</html>');
  const freshAssetResponse = await dispatchFetch(
    new Request('https://app.test/assets/translation.json'),
    'fresh-tab',
  );
  assert.equal(await freshAssetResponse.text(), '{}',
    'a cold page must load subresources before its report script executes');

  const openedBeforeUnknownFetch = openedCaches.length;
  const unknownGenerationResponse = await dispatchFetch(
    new Request('https://app.test/assets/translation.json'),
    'older-open-tab',
  );
  assert.equal(unknownGenerationResponse.type, 'error');
  assert.equal(openedCaches.length, openedBeforeUnknownFetch,
    'activation must not guess one old cache for an unreported client');
  await reportVersion(clientsById.get('older-open-tab'), '1.2.3+3');

  // controllerchange runs inside the old page before its accepted reload and
  // therefore reports the previous version to the new worker. The updating
  // tab must stay on the new shell instead of being pinned back to the old one.
  handlers.message({
    data: { type: 'FESTAPP_CLIENT_VERSION', version: '1.2.3+3' },
    source: { id: 'updating-tab' },
    waitUntil: () => {},
  });

  const fontResponse = await dispatchFetch(new Request(fontUrl));
  assert.equal(await fontResponse.text(), 'cached emoji font');
  const navigation = new Request('https://app.test/csmostrava2026/');
  Object.defineProperty(navigation, 'mode', { value: 'navigate' });
  const shellResponse = await dispatchFetch(navigation, 'updating-tab');
  assert.equal(await shellResponse.text(), '<html>offline shell</html>');
  assert.equal(openedCaches.at(-1), 'festapp-app-shell-1.2.3+4',
    'the tab that requested the update must navigate through the new shell');
  const rootNavigation = new Request('https://app.test/');
  Object.defineProperty(rootNavigation, 'mode', { value: 'navigate' });
  const rootResponse = await dispatchFetch(rootNavigation, 'updating-tab');
  assert.equal(await rootResponse.text(), '<html>offline shell</html>',
    'a forced-occasion tenant must never open the generic event list at /');
  const privacyNavigation = new Request('https://app.test/privacy');
  Object.defineProperty(privacyNavigation, 'mode', { value: 'navigate' });
  const privacyResponse = await dispatchFetch(privacyNavigation, 'updating-tab');
  assert.equal(await privacyResponse.text(), '<html>privacy policy</html>',
    'standalone documents must not fall through to the Flutter router');
  const versionResponse = await dispatchFetch(
    new Request('https://app.test/festapp-version.json?t=offline'),
  );
  assert.equal(versionResponse.type, 'error');
  assert.equal(networkCalls, 0);

  const activationRequest = new Request(
    'https://app.test/backend-activation.json?t=first',
  );
  await assert.rejects(
    dispatchFetch(activationRequest),
    /offline/,
    'offline activation must fail without a cached document fallback',
  );
  assert.equal(activationNetworkCalls, 1);
  context.self.navigator.onLine = true;
  const legacyActivationResponse = await dispatchFetch(activationRequest);
  assert.match(await legacyActivationResponse.text(), /"backend":"legacy"/);
  activationDocument = '{"schemaVersion":1,"tenantId":"test","generation":1,"backend":"canonical"}\n';
  const canonicalActivationResponse = await dispatchFetch(new Request(
    'https://app.test/backend-activation.json?t=second',
  ));
  assert.match(await canonicalActivationResponse.text(), /"backend":"canonical"/);
  assert.equal(activationNetworkCalls, 3);
  assert.ok(!cachedPuts.some((url) => url.includes('backend-activation.json')),
    'the activation document must never enter Cache Storage');

  // An incomplete/stale app-shell must never fill an executable Flutter chunk
  // from a newer deployment. Mixing main.dart.js generations leaves the app
  // permanently stuck on its loader; the version cutover owns recovery.
  context.self.navigator.onLine = true;
  const missingChunkResponse = await dispatchFetch(
    new Request('https://app.test/main.dart.js_99.part.js'),
  );
  assert.equal(missingChunkResponse.type, 'error');
  assert.equal(networkCalls, 1);

  await dispatchFetch(
    new Request('https://app.test/assets/translation.json'),
    'older-open-tab',
  );
  assert.equal(openedCaches.at(-1), 'festapp-app-shell-1.2.3+3');

  // An older open Flutter runtime cannot execute a deferred chunk from this
  // worker's newer build. If its versioned cache never saw that route before
  // the deployment, cut the tab over to the complete current shell instead of
  // mixing JS generations and leaving AutoRoute on an endless spinner.
  serverVersion = '1.2.3+4';
  const staleChunkResponse = await dispatchFetch(
    new Request('https://app.test/main.dart.js_7.part.js'),
    'older-open-tab',
  );
  assert.equal(staleChunkResponse.type, 'error');
  assert.deepEqual(navigatedClients, [[
    'older-open-tab',
    'https://app.test/csmostrava2026/news',
  ]]);
  assert.equal(networkCalls, 1,
    'a stale runtime must never download an executable from the new build');

  // If an old controller outlives its evicted cache while the deployment has
  // already advanced, the entry bundle is the safe cutover boundary. Returning
  // Response.error() here reproduces the production blank-canvas cold start.
  serverVersion = '1.2.3+5';
  const latestMainResponse = await dispatchFetch(
    new Request('https://app.test/main.dart.js'),
  );
  assert.equal(await latestMainResponse.text(), 'recovered current executable');
  assert.deepEqual(cachedPuts, [],
    'a newer entry bundle must not be written into the old worker cache');
  assert.equal(networkCalls, 3);

  // If storage eviction/corruption removed an executable from this worker's
  // own build, recover that exact build from the network instead of leaving
  // every controlled reload permanently stuck on the Flutter loader.
  serverVersion = '1.2.3+4';
  const recoveredMainResponse = await dispatchFetch(
    new Request('https://app.test/main.dart.js'),
  );
  assert.equal(await recoveredMainResponse.text(), 'recovered current executable');
  assert.deepEqual(cachedPuts, ['https://app.test/main.dart.js']);
  assert.equal(networkCalls, 5);

  // A full/evicted cache must not discard an already verified executable.
  // Serving it keeps this reload alive even if persistence cannot self-heal.
  cachePutFails = true;
  const uncachedMainResponse = await dispatchFetch(
    new Request('https://app.test/main.dart.js_7.part.js'),
  );
  assert.equal(await uncachedMainResponse.text(), 'recovered current executable');
  assert.deepEqual(cachedPuts, ['https://app.test/main.dart.js']);
  assert.equal(networkCalls, 7);

  await reportVersion(clientsById.get('updating-tab'), '1.2.3+4');
  await reportVersion(clientsById.get('older-open-tab'), '1.2.3+3');
  assert.deepEqual(deletedCaches, ['festapp-app-shell-1.2.3+2']);
  assert.ok(cacheNames.includes('festapp-used-fonts-v1'));

  context.self.navigator.onLine = false;
  const currentAfterPrune = await dispatchFetch(navigation, 'updating-tab');
  assert.equal(await currentAfterPrune.text(), '<html>offline shell</html>');
  assert.equal(openedCaches.at(-1), 'festapp-app-shell-1.2.3+4');
  const liveAfterPrune = await dispatchFetch(
    new Request('https://app.test/assets/translation.json'),
    'older-open-tab',
  );
  assert.equal(await liveAfterPrune.text(), '{}');
  assert.equal(openedCaches.at(-1), 'festapp-app-shell-1.2.3+3');

  const webClientIndex = await readFile(
    path.join(projectRoot, 'web_client/index.html'),
    'utf8',
  );
  assert.match(webClientIndex, /serviceWorker\.register\('\/festapp_service_worker\.js'/);
  assert.match(webClientIndex, /import \{ APP_VERSION \} from '\/src\/version\.js'/);
  assert.match(webClientIndex, /type: 'FESTAPP_CLIENT_VERSION'/);
  assert.match(webClientIndex, /version: APP_VERSION/);
  assert.match(webClientIndex, /controllerchange/);
  assert.match(webClientIndex, /visibilitychange/);
  assert.doesNotMatch(webClientIndex, /serviceWorker\.getRegistrations\(\)/);
  assert.match(webClientIndex, /performance\.getEntriesByType\('resource'\)/);
  const flutterIndex = await readFile(path.join(projectRoot, 'web/index.html'), 'utf8');
  const ciBuild = await readFile(
    path.join(projectRoot, 'automation/ci_build.sh'),
    'utf8',
  );
  const cloudflareBuild = await readFile(
    path.join(projectRoot, 'automation/cloudflare_build.sh'),
    'utf8',
  );
  const sharedBuild = await readFile(
    path.join(projectRoot, 'automation/build_web_bundle.sh'),
    'utf8',
  );
  const flutterVersionScript = await readFile(
    path.join(projectRoot, 'automation/flutter_version.mjs'),
    'utf8',
  );
  const appConfig = await readFile(path.join(projectRoot, 'lib/app_config.dart'), 'utf8');
  const oneSignalWorker = await readFile(
    path.join(projectRoot, 'web/push/OneSignalSDKWorker.js'),
    'utf8',
  );
  assert.match(
    appConfig,
    /static const bool isWebNotificationsSupported = true;/,
    'installed PWA notifications must remain enabled for this deployment',
  );
  assert.match(flutterIndex, /serviceWorkerPath: "\.\/push\/OneSignalSDKWorker\.js"/);
  assert.match(worker, /festapp-occasion-media-v1/);
  assert.match(worker, /request\.destination === 'image'/);
  assert.doesNotMatch(
    flutterIndex,
    /canvasKitForceMultiSurfaceRasterizer/,
    'Chromium must keep Flutter’s default offscreen rasterizer; the multi-surface fallback uses multiple WebGL contexts and is reserved for Safari/Firefox',
  );
  assert.doesNotMatch(ciBuild, /FLUTTER_WEB_CANVASKIT_FORCE_MULTI_SURFACE_RASTERIZER/);
  assert.doesNotMatch(
    cloudflareBuild,
    /FLUTTER_WEB_CANVASKIT_FORCE_MULTI_SURFACE_RASTERIZER/,
  );
  assert.match(ciBuild, /build_web_bundle\.sh" static/);
  assert.match(cloudflareBuild, /build_web_bundle\.sh" cloudflare/);
  assert.match(cloudflareBuild, /path === "\/backend-activation\.json"[\s\S]*?"no-store, max-age=0"/);
  assert.match(
    cloudflareBuild,
    /path === "\/backend-activation\.json" && request\.method === "OPTIONS"[\s\S]*?activationCorsHeaders/,
    'the public activation manifest must support cross-origin preview preflights',
  );
  assert.match(
    cloudflareBuild,
    /activationCorsHeaders[\s\S]*?access-control-allow-origin[\s\S]*?access-control-allow-headers/,
    'activation responses must carry the public CORS contract',
  );
  assert.match(sharedBuild, /cd web_client && npm ci && npm run build/);
  assert.match(sharedBuild, /apply_config\.sh/);
  assert.match(sharedBuild, /emit_version_manifest\.sh/);
  assert.match(sharedBuild, /verify_web_build\.mjs/);
  assert.match(sharedBuild, /flutter_version\.mjs/);
  assert.match(
    flutterVersionScript,
    /project\.conf/,
  );
  assert.doesNotMatch(
    flutterVersionScript,
    /\.fvmrc/,
  );
  assert.match(sharedBuild, /fvm install "\$FLUTTER_VERSION"/);
  assert.match(sharedBuild, /flutter-\$\{FLUTTER_VERSION\}/);
  assert.match(sharedBuild, /--strip-components=1/);
  assert.match(flutterIndex, /serviceWorkerParam: \{ scope: "\/push\/" \}/);
  assert.match(
    flutterIndex,
    /OneSignal initialization failed:[\s\S]*window\.OneSignalInitialized = false;[\s\S]*errorCallback\(error\);[\s\S]*return;/,
    'a failed SDK initialization must remain retryable after reconnect',
  );
  assert.match(oneSignalWorker, /OneSignalSDK\.sw\.js/);
  assert.match(flutterIndex, /e\.preventDefault\(\)/);
  assert.match(flutterIndex, /function promptInstall\(\)/);
  assert.doesNotMatch(
    flutterIndex,
    /promptInstall\(\)[\s\S]*?await window\.festappOfflineReady/,
    'the browser install prompt must run synchronously while user activation is valid',
  );
  assert.match(flutterIndex, /performance\.getEntriesByType\('resource'\)/);
  assert.match(flutterIndex, /window\.recoverFestappStartup\('bootstrap-error'\)/);
  assert.match(flutterIndex, /festapp-app-ready/);
  assert.match(flutterIndex, /window\.markFestappAppReady = function/);
  const engineStarted = flutterIndex.match(
    /await appRunner\.runApp\(\);[\s\S]*?const loader/,
  )?.[0] ?? '';
  assert.doesNotMatch(
    engineStarted,
    /__FESTAPP_APP_READY__\s*=\s*true/,
    'engine startup must not hide an application startup stall from PWA recovery',
  );
  assert.match(flutterIndex, /__FESTAPP_LOCAL_DEVELOPMENT__/);
  assert.match(flutterIndex, /festappLocalDevelopmentReady/);
  assert.match(flutterIndex, /serviceWorker\.getRegistrations\(\)/);
  assert.match(flutterIndex, /festapp-app-shell-/);
  assert.match(flutterIndex, /<img class="initial-logo"/);
  assert.match(
    flutterIndex,
    /img\.initial-logo\s*\{[\s\S]*?max-width:\s*320px/,
    'the configured tenant startup logo must keep its loading-screen sizing',
  );
  assert.doesNotMatch(flutterIndex, /<svg class="initial-logo"/);
  assert.doesNotMatch(flutterIndex, /CSM Ostrava 2026/);
  const updatePrompt = await readFile(
    path.join(projectRoot, 'web/festapp_update_prompt.js'),
    'utf8',
  );
  assert.match(updatePrompt, /function recoverStalledStartup\(reason\)/);
  assert.match(updatePrompt, /scheduleStartupRecovery\(\)/);
  assert.match(updatePrompt, /startupRecoveryStorageKey/);
  assert.match(updatePrompt, /navigator\.onLine === false/);
  assert.match(updatePrompt, /FESTAPP_CLIENT_VERSION/);
  assert.match(updatePrompt, /serviceWorker\.ready\.then\(reportClientVersion\)/);
  assert.match(
    updatePrompt,
    /if \(window\.__FESTAPP_LOCAL_DEVELOPMENT__\) return;/,
  );
  const networkReload = updatePrompt.match(
    /async function prepareNetworkReload\(\) \{[\s\S]*?\n  \}/,
  )?.[0];
  assert.ok(networkReload);
  assert.match(networkReload, /registration\.update\(\)/);
  assert.doesNotMatch(networkReload, /unregister\(\)/);
  assert.doesNotMatch(networkReload, /caches\.delete|festapp-app-shell-/);
  console.log('pwa_offline.test: ok');
} finally {
  await rm(tempRoot, { recursive: true, force: true });
}
