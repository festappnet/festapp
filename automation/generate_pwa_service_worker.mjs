#!/usr/bin/env node

import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { collectPwaShellManifest } from './lib/pwa_shell_manifest.mjs';

const buildDir = path.resolve(process.argv[2] || 'build/web');
const version = process.argv[3];
const forcedOccasionLink = (process.argv[4] || '').trim().replace(/^\/+|\/+$/g, '');

if (!version) {
  throw new Error(
    'Usage: generate_pwa_service_worker.mjs <build-dir> <version> [forced-occasion-link]',
  );
}
if (forcedOccasionLink && !/^[a-zA-Z0-9_-]+$/.test(forcedOccasionLink)) {
  throw new Error('forced-occasion-link contains unsupported characters');
}

const outputName = 'festapp_service_worker.js';
const manifest = await collectPwaShellManifest(buildDir);
const assets = manifest.knownResources;
const coreAssets = manifest.coreResources;
const standaloneDocuments = manifest.standaloneDocuments;
const flutterEntry = manifest.flutterEntry;
const webClientEntry = manifest.webClientEntry;
const cacheName = `festapp-app-shell-${version}`;
const source = `'use strict';

const BUILD_VERSION = ${JSON.stringify(version)};
const CACHE_NAME = ${JSON.stringify(cacheName)};
const CACHE_PREFIX = 'festapp-app-shell-';
const FONT_CACHE_NAME = 'festapp-used-fonts-v1';
const OCCASION_MEDIA_CACHE_NAME = 'festapp-occasion-media-v1';
const PRECACHE_URLS = ${JSON.stringify(assets, null, 2)};
const CORE_URLS = ${JSON.stringify(coreAssets, null, 2)};
const FLUTTER_ENTRY = ${JSON.stringify(flutterEntry)};
const WEB_CLIENT_ENTRY = ${JSON.stringify(webClientEntry)};
const FORCED_OCCASION_PATH = ${JSON.stringify(forcedOccasionLink ? `/${forcedOccasionLink}/event` : null)};
const STANDALONE_DOCUMENT_PATHS = new Set(${JSON.stringify(standaloneDocuments, null, 2)});
const PRECACHE_PATHS = new Set(PRECACHE_URLS.map((url) =>
  new URL(url, self.location.origin).pathname));
const clientVersions = new Map();
const clientCacheNames = new Map();
const pendingClientVersionReports = new Map();
let cutoverClientId = null;
let cacheMutationStatusUnknown = false;
const STORAGE_API_TIMEOUT_MS = 1000;
const CLIENT_VERSION_REPORT_TIMEOUT_MS = 1000;
const MAX_EXPLICIT_PRUNE_OPERATIONS = 100;
// 0.19.85+418 recorded cold navigations under the empty clientId instead of
// resultingClientId, deadlocking every first-party subresource. A waiting
// worker cannot be activated by that page because its update script is one of
// the blocked resources. Only clients carrying this known-bad shell may bypass
// the normal user-confirmed cutover.
const EMERGENCY_RECOVERY_CACHE_NAMES = new Set([
  'festapp-app-shell-0.19.85+418',
]);
// These releases predate the web-client -> Flutter runtime coordinator. A new
// worker must take control without reloading their existing page; otherwise
// the old worker can keep serving the old web client that has no way to
// activate its successor. Per-client cache pinning below keeps that open page
// coherent, while its next full navigation deliberately enters the new shell.
// Remove this bounded migration list once supported installations are newer
// than 0.19.93+459.
const HANDOFF_BOOTSTRAP_CACHE_NAMES = new Set([
  'festapp-app-shell-0.19.93+455',
  'festapp-app-shell-0.19.93+456',
  'festapp-app-shell-0.19.93+457',
  'festapp-app-shell-0.19.93+458',
  'festapp-app-shell-0.19.93+459',
]);

function withStorageTimeout(promise) {
  let timeoutId;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timeoutId = setTimeout(
        () => reject(new Error('storage-api-timeout')),
        STORAGE_API_TIMEOUT_MS,
      );
    }),
  ]).finally(() => clearTimeout(timeoutId));
}

async function precacheAtomically() {
  const cache = await caches.open(CACHE_NAME);
  // Install every executable chunk atomically. Flutter defers routes into
  // main.dart.js_<n>.part.js files; omitting an unvisited route can make an
  // installed PWA stall when it is cold-started offline on that URL. Large
  // non-code assets remain lazy so maps/media do not delay activation.
  await cache.addAll(CORE_URLS);
}

async function requiresEmergencyCutover() {
  try {
    const names = await withStorageTimeout(caches.keys());
    return names.some((name) => EMERGENCY_RECOVERY_CACHE_NAMES.has(name));
  } catch (_) {
    return false;
  }
}

async function requiresHandoffBootstrapActivation() {
  try {
    const names = await withStorageTimeout(caches.keys());
    return names.some((name) => HANDOFF_BOOTSTRAP_CACHE_NAMES.has(name));
  } catch (_) {
    return false;
  }
}

function recordClientVersion(clientId, version) {
  clientVersions.set(clientId, version);
  const pending = pendingClientVersionReports.get(clientId);
  if (pending) {
    clearTimeout(pending.timeoutId);
    pending.resolve(true);
    pendingClientVersionReports.delete(clientId);
  }
}

function waitForClientVersion(clientId) {
  if (clientVersions.has(clientId)) return Promise.resolve(true);
  const existing = pendingClientVersionReports.get(clientId);
  if (existing) return existing.promise;
  let resolveReport;
  const promise = new Promise((resolve) => { resolveReport = resolve; });
  const pending = {
    promise,
    resolve: resolveReport,
    timeoutId: setTimeout(() => {
      pendingClientVersionReports.delete(clientId);
      resolveReport(false);
    }, CLIENT_VERSION_REPORT_TIMEOUT_MS),
  };
  pendingClientVersionReports.set(clientId, pending);
  return promise;
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    await precacheAtomically();
    if (await requiresEmergencyCutover() ||
        await requiresHandoffBootstrapActivation()) {
      await self.skipWaiting();
    }
  })());
});

async function reconcileShellCaches({ apply = false } = {}) {
  try {
    const windowClients = await withStorageTimeout(self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    }));
    const names = await withStorageTimeout(caches.keys());
    const shellNames = names.filter((name) => name.startsWith(CACHE_PREFIX));
    const liveVersions = [];
    let unknown = 0;
    for (const client of windowClients) {
      const version = clientVersions.get(client.id);
      if (typeof version !== 'string' || version.length === 0) {
        unknown++;
      } else {
        liveVersions.push(version);
      }
    }
    const live = [...new Set(liveVersions)].sort();
    const retained = [...new Set([
      CACHE_NAME,
      ...live.map((version) => CACHE_PREFIX + version),
    ])].sort();
    const missing = retained.filter((name) => !shellNames.includes(name));
    let blocker = cacheMutationStatusUnknown
      ? 'cache-delete-status-unknown'
      : unknown > 0
      ? 'unknown-live-client'
      : missing.length > 0
        ? 'missing-live-shell'
        : null;
    const deletable = blocker === null
      ? shellNames.filter((name) => !retained.includes(name)).sort()
      : [];
    const deleted = [];
    if (apply && blocker === null && deletable.length > 0) {
      // Cache Storage has no transactional multi-delete or cancellation. Apply
      // one already-approved name per reconciliation so a later API failure can
      // never leave an unreported partially-completed batch.
      const name = deletable[0];
      try {
        if (await withStorageTimeout(caches.delete(name))) {
          deleted.push(name);
        } else {
          blocker = 'cache-delete-rejected';
        }
      } catch (error) {
        blocker = error?.message === 'storage-api-timeout'
          ? 'cache-delete-status-unknown'
          : 'cache-delete-error';
        if (blocker === 'cache-delete-status-unknown') {
          // Cache Storage cannot cancel an already-dispatched delete. Keep all
          // later mutation attempts blocked for this worker lifetime rather
          // than racing an operation whose eventual result is unknown.
          cacheMutationStatusUnknown = true;
        }
      }
    }
    return {
      current: BUILD_VERSION,
      live,
      unknown,
      retained,
      deletable,
      blocker,
      deleted,
    };
  } catch (error) {
    return {
      current: BUILD_VERSION,
      live: [],
      unknown: 0,
      retained: [CACHE_NAME],
      deletable: [],
      blocker: error?.message === 'storage-api-timeout'
        ? 'storage-api-timeout'
        : 'storage-api-error',
      deleted: [],
    };
  }
}

async function pruneAllUnusedShellCaches() {
  const deleted = [];
  for (let operation = 0; operation < MAX_EXPLICIT_PRUNE_OPERATIONS; operation++) {
    const result = await reconcileShellCaches({ apply: true });
    deleted.push(...result.deleted);
    if (result.blocker !== null || result.deleted.length === 0) {
      return { ...result, deleted };
    }
    if (result.deletable.length === 1) {
      return { ...result, deletable: [], deleted };
    }
  }
  const result = await reconcileShellCaches({ apply: false });
  return {
    ...result,
    blocker: result.blocker || 'prune-operation-limit',
    deleted,
  };
}

// Cache Storage mutations are serialized. Concurrent client reports, manual
// pruning and activation must not inspect the same stale set and race to delete
// it twice.
let reconcileQueue = Promise.resolve();
function scheduleShellReconcile(options) {
  const scheduled = reconcileQueue.then(() => reconcileShellCaches(options));
  reconcileQueue = scheduled.catch(() => {});
  return scheduled;
}

function scheduleExplicitShellPrune() {
  const scheduled = reconcileQueue.then(() => pruneAllUnusedShellCaches());
  reconcileQueue = scheduled.catch(() => {});
  return scheduled;
}

self.addEventListener('message', (event) => {
  if (event.data?.type === 'FESTAPP_QUERY_BUILD_VERSION') {
    event.ports?.[0]?.postMessage({ version: BUILD_VERSION });
    return;
  }
  if (event.data?.type === 'FESTAPP_INSPECT_SHELLS') {
    event.waitUntil(scheduleShellReconcile({ apply: false }).then((result) => {
      event.ports?.[0]?.postMessage(result);
    }));
    return;
  }
  if (event.data?.type === 'FESTAPP_PRUNE_UNUSED_SHELLS') {
    event.waitUntil(scheduleExplicitShellPrune().then((result) => {
      event.ports?.[0]?.postMessage(result);
    }));
    return;
  }
  if (event.data === 'SKIP_WAITING') {
    cutoverClientId = event.source?.id || null;
    self.skipWaiting();
    return;
  }
  if (event.data?.type === 'FESTAPP_CLIENT_VERSION' && event.source?.id) {
    // controllerchange fires in the old page before its accepted reload. Its
    // report still contains the previous build number; mapping that cutover
    // client back to the old shell recreates a mixed-generation mobile reload.
    if (event.source.id === cutoverClientId &&
        event.data.version !== BUILD_VERSION) return;
    recordClientVersion(event.source.id, event.data.version);
    if (event.data.version === BUILD_VERSION) {
      clientCacheNames.delete(event.source.id);
      if (event.source.id === cutoverClientId) cutoverClientId = null;
    } else {
      clientCacheNames.set(
        event.source.id,
        CACHE_PREFIX + event.data.version,
      );
    }
    event.waitUntil(scheduleShellReconcile({ apply: true }));
  }
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    let windowClients = [];
    try {
      windowClients = await withStorageTimeout(self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      }));
    } catch (_) {
      // Activation remains available, but reconciliation below fails closed.
    }
    const emergencyCutover = await requiresEmergencyCutover();
    // Do not guess one "previous" cache for every already-open tab: multiple
    // old generations can legitimately coexist. After claim, runtime fetches
    // wait briefly for each page's exact version report and fail closed if it
    // never arrives. Navigations are the explicit current-version boundary.
    await self.clients.claim();
    if (emergencyCutover) {
      // The broken page never loaded its reporting script. Bind it to this
      // fully installed shell before reloading so no request can re-enter the
      // client-version handshake deadlock.
      for (const client of windowClients) {
        clientCacheNames.delete(client.id);
        recordClientVersion(client.id, BUILD_VERSION);
        try {
          await client.navigate(client.url);
        } catch (_) {
          // A later manual navigation remains recoverable by resultingClientId.
        }
      }
    } else {
      for (const client of windowClients) {
        client.postMessage({ type: 'FESTAPP_REPORT_VERSION' });
      }
    }
    await scheduleShellReconcile({ apply: true });
  })());
});

function cachedNavigationTarget(pathname) {
  const normalizedPath = pathname.endsWith('/') ? pathname : pathname + '/';
  if (STANDALONE_DOCUMENT_PATHS.has(normalizedPath)) {
    return normalizedPath;
  }
  if (pathname === '/' && FORCED_OCCASION_PATH) {
    return FLUTTER_ENTRY;
  }
  if (pathname === '/' || pathname.startsWith('/form/')) {
    return WEB_CLIENT_ENTRY;
  }
  return FLUTTER_ENTRY;
}

function isFlutterExecutable(pathname) {
  return pathname === '/main.dart.js' ||
    /^\\/main\\.dart\\.js_\\d+\\.part\\.js$/.test(pathname) ||
    pathname === '/flutter.js' ||
    pathname === '/flutter_bootstrap.js';
}

function isFlutterBootstrapExecutable(pathname) {
  return pathname === '/main.dart.js' ||
    pathname === '/flutter.js' ||
    pathname === '/flutter_bootstrap.js';
}

async function recoverCurrentExecutable(request, cache, allowNewerBootstrap) {
  if (self.navigator.onLine === false) return Response.error();
  try {
    const versionResponse = await fetch('/festapp-version.json?sw-recovery=' +
      encodeURIComponent(BUILD_VERSION), { cache: 'no-store' });
    if (!versionResponse.ok) return Response.error();
    const manifest = await versionResponse.json();
    if (manifest?.version !== BUILD_VERSION) {
      // The active worker can outlive its cache while a newer deployment is
      // already live. Failing the entry bundle here leaves every cold start on
      // a blank canvas. A bootstrap request is a safe generation boundary: no
      // Dart runtime is executing yet, so let the network's coherent release
      // start and allow its worker to take over. Deferred chunks remain strict.
      if (!allowNewerBootstrap) return Response.error();
      const latestResponse = await fetch(request);
      return latestResponse.ok ? latestResponse : Response.error();
    }

    const response = await fetch(request);
    if (!response.ok) return Response.error();
    try {
      await cache.put(request, response.clone());
    } catch (_) {
      // A full/evicted cache must not discard an executable already verified
      // against this exact deployment. This reload can still finish online.
    }
    return response;
  } catch (_) {
    return Response.error();
  }
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  // Cache only font resources the application actually requests. This covers
  // Google Fonts stylesheets/binaries and Flutter's demand-loaded Noto Color
  // Emoji shards without downloading either provider's unused catalog.
  if (url.origin === 'https://fonts.googleapis.com' ||
      url.origin === 'https://fonts.gstatic.com') {
    event.respondWith((async () => {
      const cache = await caches.open(FONT_CACHE_NAME);
      const cached = await cache.match(request);
      if (cached) return cached;
      if (self.navigator.onLine === false) return Response.error();
      const response = await fetch(request);
      if (response.ok || response.type === 'opaque') {
        await cache.put(request, response.clone());
      }
      return response;
    })());
    return;
  }
  // Media listed by occasion_config is prefetched into a stable CacheStorage
  // sidecar by Flutter. Serve that exact response to normal image requests on
  // cold offline PWA starts; unrelated cross-origin requests remain untouched.
  if (request.destination === 'image' && url.origin !== self.location.origin) {
    event.respondWith((async () => {
      const mediaCache = await caches.open(OCCASION_MEDIA_CACHE_NAME);
      return (await mediaCache.match(request)) || fetch(request);
    })());
    return;
  }
  if (url.origin !== self.location.origin) return;

  // A transition release must observe this document from the deployment, not
  // from an app-shell generation. It is deliberately absent from PRECACHE_URLS
  // and has no offline fallback: the client itself keeps legacy until it sees
  // the exact pinned canonical bytes, then persists a monotonic local marker.
  if (url.pathname === '/backend-activation.json' ||
      url.pathname === '/client-sync-config.json') {
    event.respondWith(fetch(request, { cache: 'no-store' }));
    return;
  }

  // This is the network truth used to discover a newer completed deployment.
  if (url.pathname === '/festapp-version.json') {
    if (self.navigator.onLine === false) {
      event.respondWith(caches.open(CACHE_NAME).then(async (cache) =>
        (await cache.match('/festapp-version.json')) || Response.error()));
      return;
    }
    event.respondWith(fetch(request));
    return;
  }

  event.respondWith((async () => {
    // Navigation fetches create a new WindowClient. Browsers expose that new
    // identity as resultingClientId while clientId is commonly empty. Every
    // subsequent subresource request uses the resulting id, so record and
    // select the shell under that same canonical identity or the page deadlocks
    // before its version-reporting script can load.
    const clientId = request.mode === 'navigate'
      ? (event.resultingClientId || event.clientId)
      : event.clientId;
    // A full-page navigation is the explicit cutover boundary for that tab.
    // Runtime requests from an older, still-open tab stay on its mapped shell.
    if (request.mode === 'navigate' && clientId) {
      clientCacheNames.delete(clientId);
      recordClientVersion(clientId, BUILD_VERSION);
    } else if (clientId && !clientVersions.has(clientId)) {
      const reported = await waitForClientVersion(clientId);
      if (!reported) return Response.error();
    }
    const selectedCacheName = clientCacheNames.get(clientId) || CACHE_NAME;
    const cache = await caches.open(selectedCacheName);
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;

    if (request.mode === 'navigate') {
      const exactIndex = await cache.match(url.pathname.replace(/\\/$/, '') + '/index.html');
      if (exactIndex) return exactIndex;
      const entry = await cache.match(cachedNavigationTarget(url.pathname));
      if (entry) return entry;
    }


    // A Flutter main bundle and its deferred parts are one indivisible build.
    // Recover an evicted/corrupt cache entry only while the network deployment
    // still matches this worker. A newer manifest must cut over atomically via
    // the update prompt instead of mixing executable generations.
    if (isFlutterExecutable(url.pathname)) {
      // A client that is still executing an older main.dart.js must never be
      // given a deferred chunk from this worker's newer deployment. That is a
      // valid situation when the route was not opened before the deployment,
      // because deferred chunks are populated lazily. Reload the stale tab
      // through the current versioned shell; otherwise AutoRoute keeps its
      // loading placeholder forever after the incompatible chunk fails.
      if (selectedCacheName !== CACHE_NAME) {
        if (isFlutterBootstrapExecutable(url.pathname)) {
          clientCacheNames.delete(clientId);
          const currentCache = await caches.open(CACHE_NAME);
          const currentExecutable = await currentCache.match(request, {
            ignoreSearch: true,
          });
          if (currentExecutable) return currentExecutable;
          return recoverCurrentExecutable(request, currentCache, true);
        }
        try {
          const client = clientId
            ? await self.clients.get(clientId)
            : null;
          if (client) await client.navigate(client.url);
        } catch (_) {
          // Returning a failed executable request is still safer than mixing
          // Flutter builds if the browser rejects the navigation request.
        }
        return Response.error();
      }
      return recoverCurrentExecutable(
        request,
        cache,
        isFlutterBootstrapExecutable(url.pathname),
      );
    }

    // Fill the rest of this build's known shell lazily. This keeps updates
    // quick while preserving offline access for resources the user has used.
    if (self.navigator.onLine === false) return Response.error();
    const response = await fetch(request);
    if (response.ok && PRECACHE_PATHS.has(url.pathname)) {
      try {
        await cache.put(request, response.clone());
      } catch (_) {
        // A storage quota issue must not break an otherwise valid online load.
      }
    }
    return response;
  })());
});
`;

await writeFile(path.join(buildDir, outputName), source);

console.log(`generate_pwa_service_worker: ${assets.length} files, ${(manifest.knownBytes / 1024 / 1024).toFixed(1)} MiB, ${cacheName}`);
