#!/usr/bin/env node

import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { collectPwaShellManifest } from './lib/pwa_shell_manifest.mjs';
import { isPublicOccasionAppPath, unsupportedOccasionAppRedirect } from '../web_client/src/services/public_occasion_routes.js';
import { resolveScannerRoute } from '../web_client/src/services/scanner_routes.js';

const buildDir = path.resolve(process.argv[2] || 'build/web');
const version = process.argv[3];
const forcedOccasionLink = (process.argv[4] || '').trim().replace(/^\/+|\/+$/g, '');
const appSupported = process.argv[5] ?? 'true';
if (!['true', 'false'].includes(appSupported)) {
  throw new Error('app-supported must be true or false');
}
const isAppSupported = appSupported === 'true';

if (!version) {
  throw new Error(
    'Usage: generate_pwa_service_worker.mjs <build-dir> <version> [forced-occasion-link] [app-supported]',
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
const FLUTTER_MAIN = ${JSON.stringify(manifest.flutterMain)};
const WEB_CLIENT_ENTRY = ${JSON.stringify(webClientEntry)};
const IS_APP_SUPPORTED = ${JSON.stringify(isAppSupported)};
const ORGANIZER_HOMEPAGE = ${JSON.stringify(manifest.organizerHomepage)};
${isPublicOccasionAppPath.toString()}
${unsupportedOccasionAppRedirect.toString()}
${resolveScannerRoute.toString()}
const FORCED_OCCASION_PATH = ${JSON.stringify(isAppSupported && forcedOccasionLink ? `/${forcedOccasionLink}/event` : null)};
const STANDALONE_DOCUMENT_PATHS = new Set(${JSON.stringify(standaloneDocuments, null, 2)});
const PRECACHE_PATHS = new Set(PRECACHE_URLS.map((url) =>
  new URL(url, self.location.origin).pathname));
// Worker globals can disappear between the HTML response and its first script.
// Keep only the served build identity, never auth or application data.
const CLIENT_VERSION_CACHE_NAME = 'festapp-client-versions-v1';
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
// This generation's web HTML has no version reporter or update coordinator.
// Its lazy imports can disappear from the deployment while its cached home
// still works. Recovery must also run when Safari correctly reports online.
// A complete installation, not navigator.onLine, proves a replacement exists.
const LEGACY_WEB_RECOVERY_CACHE_NAMES = new Set([
  'festapp-app-shell-0.20.17+501',
]);
// These releases predate the web-client -> Flutter runtime coordinator. A new
// worker must take control without reloading their existing page; otherwise
// the old worker can keep serving the old web client that has no way to
// activate its successor. Per-client cache pinning below keeps that open page
// coherent, while its next full navigation deliberately enters the new shell.
// Remove this bounded migration list once supported installations are newer
// than 0.19.93+459.
const HANDOFF_BOOTSTRAP_CACHE_NAMES = new Set([
  // These installed routers predate the standalone order route. Claim without
  // reloading their forms so new navigations reach /order rather than home.
  'festapp-app-shell-0.20.222+706',
  'festapp-app-shell-0.20.223+707',
  'festapp-app-shell-0.20.224+708',
  'festapp-app-shell-0.20.225+709',
  'festapp-app-shell-0.20.226+710',
  'festapp-app-shell-0.20.185+669',
  'festapp-app-shell-0.20.186+670',
  'festapp-app-shell-0.20.187+671',
  'festapp-app-shell-0.20.188+672',
  'festapp-app-shell-0.20.189+673',
  'festapp-app-shell-0.20.190+674',
  'festapp-app-shell-0.20.191+675',
  'festapp-app-shell-0.20.192+676',
  'festapp-app-shell-0.20.193+677',
  'festapp-app-shell-0.20.194+678',
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
  // A cached failed deployment response must not poison every install retry.
  await cache.addAll(CORE_URLS.map((url) => new Request(
    new URL(url, self.location.origin), { cache: 'no-store' })));
}

async function requiresEmergencyCutover() {
  try {
    const names = await withStorageTimeout(caches.keys());
    return names.some((name) => EMERGENCY_RECOVERY_CACHE_NAMES.has(name));
  } catch (_) {
    return false;
  }
}

async function requiresLegacyWebRecovery() {
  try {
    const names = await withStorageTimeout(caches.keys());
    return names.some((name) => LEGACY_WEB_RECOVERY_CACHE_NAMES.has(name));
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

async function recordClientVersion(clientId, version) {
  clientVersions.set(clientId, version);
  const pending = pendingClientVersionReports.get(clientId);
  if (pending) {
    clearTimeout(pending.timeoutId);
    pending.resolve(true);
    pendingClientVersionReports.delete(clientId);
  }
  try {
    const cache = await withStorageTimeout(caches.open(CLIENT_VERSION_CACHE_NAME));
    await withStorageTimeout(cache.put(clientVersionRequest(clientId),
      new Response(JSON.stringify({ version }), { headers: { 'content-type': 'application/json' } })));
  } catch (_) {
    // Storage failure must not block a live page whose version is already known.
  }
}

function clientVersionRequest(clientId) {
  return new Request(new URL('/__festapp_client_version__/' + encodeURIComponent(clientId),
    self.location.origin));
}

async function restoreClientVersion(clientId) {
  if (clientVersions.has(clientId)) return true;
  try {
    const cache = await withStorageTimeout(caches.open(CLIENT_VERSION_CACHE_NAME));
    const response = await withStorageTimeout(cache.match(clientVersionRequest(clientId)));
    if (!response) return false;
    const { version } = await withStorageTimeout(response.json());
    // A live report can arrive while the storage read is in progress.
    if (clientVersions.has(clientId)) return true;
    if (typeof version !== 'string' || !version) return false;
    clientVersions.set(clientId, version);
    if (version !== BUILD_VERSION) clientCacheNames.set(clientId, CACHE_PREFIX + version);
    return true;
  } catch (_) {
    return false;
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
  // Existing Android tabs may resume under a restarted worker, including tabs
  // opened before durable reports shipped. Ask the loaded document directly
  // rather than waiting for an unrelated focus event or polling interval.
  Promise.resolve().then(() => self.clients.get(clientId)).then((client) => {
    client?.postMessage({ type: 'FESTAPP_REPORT_VERSION' });
  }).catch(() => {});
  return promise;
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    await precacheAtomically();
    if (await requiresEmergencyCutover() ||
        await requiresLegacyWebRecovery() ||
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
      await restoreClientVersion(client.id);
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

async function repairCurrentAppShell(expectedVersion) {
  if (expectedVersion !== BUILD_VERSION) return { ok: false, reason: 'wrong-worker' };
  try {
    const response = await fetch('/festapp-version.json?shell-repair=' +
      encodeURIComponent(BUILD_VERSION), { cache: 'no-store' });
    if (!response.ok) return { ok: false, reason: 'network-unavailable' };
    const manifest = await response.json();
    if (manifest.version !== BUILD_VERSION ||
        '/' + manifest.main !== FLUTTER_MAIN) {
      return { ok: false, reason: 'version-changed' };
    }
    // Cache.addAll commits the complete batch only after every download succeeds.
    // Preserve auth, application data and every other generation's offline shell.
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(CORE_URLS.map((url) => new Request(
      new URL(url, self.location.origin), { cache: 'reload' })));
    return { ok: true, version: BUILD_VERSION };
  } catch (_) {
    return { ok: false, reason: 'repair-failed' };
  }
}

self.addEventListener('message', (event) => {
  if (event.data?.type === 'FESTAPP_REPAIR_APP_SHELL' && event.source?.id) {
    event.waitUntil(repairCurrentAppShell(event.data.version).then((result) => {
      event.ports?.[0]?.postMessage(result);
    }));
    return;
  }
  if (event.data?.type === 'FESTAPP_QUERY_BUILD_VERSION') {
    event.ports?.[0]?.postMessage({ version: BUILD_VERSION });
    return;
  }
  if (event.data?.type === 'FESTAPP_SCANNER_SHELL_STATUS') {
    event.waitUntil((async () => {
      const cache = await caches.open(CACHE_NAME);
      const present = await Promise.all(CORE_URLS.map((url) => cache.match(url)));
      event.ports?.[0]?.postMessage({
        version: BUILD_VERSION,
        ready: present.every(Boolean),
      });
    })());
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
    const persistedVersion = recordClientVersion(event.source.id, event.data.version);
    if (event.data.version === BUILD_VERSION) {
      clientCacheNames.delete(event.source.id);
      if (event.source.id === cutoverClientId) cutoverClientId = null;
    } else {
      clientCacheNames.set(
        event.source.id,
        CACHE_PREFIX + event.data.version,
      );
    }
    event.waitUntil(Promise.all([persistedVersion, scheduleShellReconcile({ apply: true })]));
  }
});

function beginActivationNavigation(client) {
  // The browser owns the navigation once requested. Its controlled fetches
  // cannot finish until activate completes, so including navigate()'s result
  // in this event's waitUntil would deadlock WebKit. Handle rejection without
  // deleting the cached shell or holding activation open.
  try {
    client.navigate(client.url).catch(() => {});
  } catch (_) {}
}

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
    const legacyWebRecovery = await requiresLegacyWebRecovery();
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
        await recordClientVersion(client.id, BUILD_VERSION);
        beginActivationNavigation(client);
      }
    } else {
      for (const client of windowClients) {
        client.postMessage({ type: 'FESTAPP_REPORT_VERSION' });
      }
      if (legacyWebRecovery) {
        await Promise.all(windowClients.map(async (client) => {
          // The presence of a broken cache does not make every tab broken.
          // Preserve reporting modern pages and their in-progress form edits.
          if (!await restoreClientVersion(client.id)) {
            await waitForClientVersion(client.id);
          }
          const version = clientVersions.get(client.id);
          if (version && !LEGACY_WEB_RECOVERY_CACHE_NAMES.has(CACHE_PREFIX + version)) return;
          // A full navigation binds the new document to this fully installed
          // shell before any module request. No cookies or app data change.
          beginActivationNavigation(client);
        }));
      }
    }
    await scheduleShellReconcile({ apply: true });
  })());
});

function cachedNavigationTarget(pathname) {
  if (resolveScannerRoute(pathname)) return WEB_CLIENT_ENTRY;
  if ((pathname === '/pro-poradatele' || pathname === '/pro-poradatele/') &&
      STANDALONE_DOCUMENT_PATHS.has('/pro-poradatele')) {
    return '/pro-poradatele';
  }
  const normalizedPath = pathname.endsWith('/') ? pathname : pathname + '/';
  if (STANDALONE_DOCUMENT_PATHS.has(normalizedPath)) {
    return normalizedPath;
  }
  const unitPath = pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
  const unitCatalogue = unitPath.startsWith('/unit/') && /^[1-9][0-9]*$/.test(unitPath.slice(6));
  if (pathname === '/' || (ORGANIZER_HOMEPAGE && pathname === '/events') || pathname === '/order' || unitCatalogue || pathname.startsWith('/form/')) {
    return WEB_CLIENT_ENTRY;
  }
  return FLUTTER_ENTRY;
}

function isFlutterExecutable(pathname) {
  return pathname === FLUTTER_MAIN || pathname === '/main.dart.js' ||
    /^\\/main\\.dart\\.(?:[0-9][0-9A-Za-z.+-]*\\.)?js_\\d+\\.part\\.js$/.test(pathname) ||
    pathname === '/flutter.js' ||
    pathname === '/flutter_bootstrap.js';
}

async function navigateToInstalledShell(clientId) {
  try {
    const client = clientId ? await self.clients.get(clientId) : null;
    if (client) await client.navigate(client.url);
  } catch (_) {
    // A rejected navigation must not mix executable generations. The next
    // manual navigation can still use the fully installed current shell.
  }
}

function isFlutterBootstrapExecutable(pathname) {
  return pathname === FLUTTER_MAIN || pathname === '/main.dart.js' ||
    pathname === '/flutter.js' ||
    pathname === '/flutter_bootstrap.js';
}

async function recoverCurrentExecutable(request, cache, allowNewerBootstrap) {
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
      const latestResponse = await fetch(request, { cache: 'no-store' });
      return latestResponse.ok ? latestResponse : Response.error();
    }

    const response = await fetch(request, { cache: 'no-store' });
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
  if (url.origin === self.location.origin && request.mode === 'navigate' &&
      url.pathname.startsWith('/form/') &&
      ['order_id', 'offer_id', 'token', 'waitlist'].some(key => url.searchParams.has(key))) {
    event.respondWith(new Response('Tento odkaz již není podporován.', { status: 410,
      headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' } }));
    return;
  }
  // Cache only font resources the application actually requests. This covers
  // Google Fonts stylesheets/binaries and Flutter's demand-loaded Noto Color
  // Emoji shards without downloading either provider's unused catalog.
  if (url.origin === 'https://fonts.googleapis.com' ||
      url.origin === 'https://fonts.gstatic.com') {
    event.respondWith((async () => {
      const cache = await caches.open(FONT_CACHE_NAME);
      const cached = await cache.match(request);
      if (cached) return cached;
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

  // A marketing document is independent from the version-pinned offline app.
  // Serve it from the network; keep the installed catalogue usable offline.
  if (ORGANIZER_HOMEPAGE) {
    if (request.mode === 'navigate') {
      let target = null;
      if (url.pathname === '/pro-poradatele' || url.pathname === '/pro-poradatele/') target = new URL('/' + url.search, url);
      else if (['/', '/events', '/events/'].includes(url.pathname) && url.searchParams.get('create') === '1') {
        target = new URL('/login' + url.search, url); target.searchParams.delete('create');
      } else if (url.pathname === '/events/' || (url.pathname === '/' && url.searchParams.has('q'))) target = new URL('/events' + url.search, url);
      if (target) { event.respondWith(Promise.resolve(Response.redirect(target.href, 308))); return; }
      if (url.pathname === '/') {
        event.respondWith((async () => {
          const clientId = event.resultingClientId || event.clientId;
          if (clientId) { clientCacheNames.delete(clientId); await recordClientVersion(clientId, BUILD_VERSION); }
          try { return await fetch(request, {cache:'no-store'}); }
          catch (_) { const cache = await caches.open(CACHE_NAME); return (await cache.match(WEB_CLIENT_ENTRY)) || Response.error(); }
        })());
        return;
      }
    }
    if (url.pathname.startsWith('/organizers-media/') || /^\\/web-assets\\/landing-[^/]+\\.js$/.test(url.pathname)) {
      event.respondWith(fetch(request));
      return;
    }
  }

  if (request.mode === 'navigate' && !IS_APP_SUPPORTED) {
    const redirect = unsupportedOccasionAppRedirect(url.pathname);
    if (redirect) {
      event.respondWith(Response.redirect(new URL(redirect, url).toString(), 302));
      return;
    }
  }

  // Google handoffs are online proofs. Never cache them or substitute a
  // different platform's shell, even when an older shell is available offline.
  if (url.pathname === '/google-auth' || url.pathname === '/app/google-auth' ||
      url.pathname === '/settings/mcp-connect' ||
      ['/stripe/connect/callback','/app/stripe/connect/callback','/stripe/pay','/app/stripe/pay','/stripe/return','/app/stripe/return'].includes(url.pathname)) {
    const callbackClient = event.resultingClientId || event.clientId;
    if (request.mode === 'navigate' && callbackClient) {
      clientCacheNames.delete(callbackClient);
      event.waitUntil(recordClientVersion(callbackClient, BUILD_VERSION));
    }
    event.respondWith(fetch(request, { cache: 'no-store' }));
    return;
  }

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
    event.respondWith((async () => {
      try {
        return await fetch(request);
      } catch (_) {
        const cache = await caches.open(CACHE_NAME);
        return (await cache.match('/festapp-version.json')) || Response.error();
      }
    })());
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
      await recordClientVersion(clientId, BUILD_VERSION);
    } else if (clientId && !await restoreClientVersion(clientId)) {
      const reported = await waitForClientVersion(clientId);
      if (!reported) return Response.error();
    }
    const selectedCacheName = clientCacheNames.get(clientId) || CACHE_NAME;
    const cache = await caches.open(selectedCacheName);
    // The domain root belongs to the configured client, even when a prior
    // Flutter navigation left a stale document under / or /index.html.
    if (request.mode === 'navigate' && url.pathname === '/') {
      const home = await cache.match(cachedNavigationTarget('/'));
      if (home) return home;
      return fetch(request, { cache: 'no-store' });
    }
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;

    if (request.mode === 'navigate') {
      const exactIndex = await cache.match(url.pathname.replace(/\\/$/, '') + '/index.html');
      if (exactIndex) return exactIndex;
      const entry = await cache.match(cachedNavigationTarget(url.pathname));
      if (entry) return entry;
    }


    // Lazy web imports belong to the same immutable graph as their entry
    // module. When an older tab lacks a chunk, its old deployment may already
    // be gone. Re-enter the fully installed shell at the requested form URL;
    // never leave the failed import behind an otherwise interactive catalogue.
    if (selectedCacheName !== CACHE_NAME &&
        /^\\/web-assets\\/.+\\.m?js$/.test(url.pathname)) {
      await navigateToInstalledShell(clientId);
      return Response.error();
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
        await navigateToInstalledShell(clientId);
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
    let response;
    try {
      response = await fetch(request);
    } catch (_) {
      return Response.error();
    }
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
