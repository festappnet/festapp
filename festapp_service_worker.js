'use strict';

const BUILD_VERSION = "0.19.93+453";
const CACHE_NAME = "festapp-app-shell-0.19.93+453";
const CACHE_PREFIX = 'festapp-app-shell-';
const FONT_CACHE_NAME = 'festapp-used-fonts-v1';
const OCCASION_MEDIA_CACHE_NAME = 'festapp-occasion-media-v1';
const PRECACHE_URLS = [
  "/.well-known/apple-app-site-association",
  "/.well-known/assetlinks.json",
  "/android-chrome-192x192.png",
  "/android-chrome-512x512.png",
  "/apple-app-site-association",
  "/apple-touch-icon.png",
  "/assets/AssetManifest.bin",
  "/assets/AssetManifest.bin.json",
  "/assets/assets/icons/fstappicon.png",
  "/assets/assets/icons/fstapplogo.dark.svg",
  "/assets/assets/icons/fstapplogo.svg",
  "/assets/assets/translations/cs.json",
  "/assets/assets/translations/de.json",
  "/assets/assets/translations/en.json",
  "/assets/assets/translations/pl.json",
  "/assets/assets/translations/sk.json",
  "/assets/assets/translations/uk.json",
  "/assets/FontManifest.json",
  "/assets/fonts/fallback/Roboto-Regular.ttf",
  "/assets/fonts/Futura%20PT%20Book.ttf",
  "/assets/fonts/Futura%20PT%20Medium.ttf",
  "/assets/fonts/Gill%20Sans%20Bold.otf",
  "/assets/fonts/MaterialIcons-Regular.otf",
  "/assets/icons/fstapplogo.svg",
  "/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf",
  "/assets/packages/flutter_map/lib/assets/flutter_map_logo.png",
  "/assets/packages/fluttertoast/assets/toastify.css",
  "/assets/packages/fluttertoast/assets/toastify.js",
  "/assets/packages/lucide_icons_flutter/assets/build_font/LucideVariable-w100.ttf",
  "/assets/packages/lucide_icons_flutter/assets/build_font/LucideVariable-w200.ttf",
  "/assets/packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf",
  "/assets/packages/lucide_icons_flutter/assets/build_font/LucideVariable-w400.ttf",
  "/assets/packages/lucide_icons_flutter/assets/build_font/LucideVariable-w500.ttf",
  "/assets/packages/lucide_icons_flutter/assets/build_font/LucideVariable-w600.ttf",
  "/assets/packages/lucide_icons_flutter/assets/lucide.ttf",
  "/assets/packages/quill_html_editor/assets/camera_roll_icon.png",
  "/assets/packages/quill_html_editor/assets/delete_column.png",
  "/assets/packages/quill_html_editor/assets/delete_row.png",
  "/assets/packages/quill_html_editor/assets/delete_table.png",
  "/assets/packages/quill_html_editor/assets/edit_table.png",
  "/assets/packages/quill_html_editor/assets/h1_dark.png",
  "/assets/packages/quill_html_editor/assets/h2_dark.png",
  "/assets/packages/quill_html_editor/assets/insert_column_left.png",
  "/assets/packages/quill_html_editor/assets/insert_column_right.png",
  "/assets/packages/quill_html_editor/assets/insert_row_above.png",
  "/assets/packages/quill_html_editor/assets/insert_row_below.png",
  "/assets/packages/quill_html_editor/assets/insert_table.png",
  "/assets/packages/quill_html_editor/assets/scripts/quill_2.0.0_4_min.js",
  "/assets/packages/shadcn_ui/fonts/Geist-Black.otf",
  "/assets/packages/shadcn_ui/fonts/Geist-Bold.otf",
  "/assets/packages/shadcn_ui/fonts/Geist-Light.otf",
  "/assets/packages/shadcn_ui/fonts/Geist-Medium.otf",
  "/assets/packages/shadcn_ui/fonts/Geist-Regular.otf",
  "/assets/packages/shadcn_ui/fonts/Geist-SemiBold.otf",
  "/assets/packages/shadcn_ui/fonts/Geist-Thin.otf",
  "/assets/packages/shadcn_ui/fonts/Geist-UltraBlack.otf",
  "/assets/packages/shadcn_ui/fonts/Geist-UltraLight.otf",
  "/assets/packages/shadcn_ui/fonts/GeistMono-Black.otf",
  "/assets/packages/shadcn_ui/fonts/GeistMono-Bold.otf",
  "/assets/packages/shadcn_ui/fonts/GeistMono-Light.otf",
  "/assets/packages/shadcn_ui/fonts/GeistMono-Medium.otf",
  "/assets/packages/shadcn_ui/fonts/GeistMono-Regular.otf",
  "/assets/packages/shadcn_ui/fonts/GeistMono-SemiBold.otf",
  "/assets/packages/shadcn_ui/fonts/GeistMono-Thin.otf",
  "/assets/packages/shadcn_ui/fonts/GeistMono-UltraBlack.otf",
  "/assets/packages/shadcn_ui/fonts/GeistMono-UltraLight.otf",
  "/assets/packages/timezone/data/latest.tzf",
  "/assets/packages/wakelock_plus/assets/no_sleep.js",
  "/assets/packages/youtube_player_iframe/assets/player.html",
  "/assets/shaders/ink_sparkle.frag",
  "/assets/shaders/stretch_effect.frag",
  "/assets/translations/cs.json",
  "/assets/translations/en.json",
  "/auth_bridge.html",
  "/browserconfig.xml",
  "/canvaskit/canvaskit.js",
  "/canvaskit/canvaskit.wasm",
  "/canvaskit/chromium/canvaskit.js",
  "/canvaskit/chromium/canvaskit.wasm",
  "/canvaskit/skwasm_heavy.js",
  "/canvaskit/skwasm_heavy.wasm",
  "/canvaskit/skwasm.js",
  "/canvaskit/skwasm.wasm",
  "/canvaskit/webparagraph/canvaskit.js",
  "/canvaskit/webparagraph/canvaskit.wasm",
  "/canvaskit/wimp.js",
  "/canvaskit/wimp.wasm",
  "/CNAME",
  "/delete-account/",
  "/favicon-16x16.png",
  "/favicon-32x32.png",
  "/favicon.ico",
  "/festapp_pwa_bridge.js",
  "/festapp_update_prompt.js",
  "/festapp-version.json",
  "/flutter_bootstrap.js",
  "/flutter.html",
  "/flutter.js",
  "/",
  "/main.dart.js",
  "/mstile-150x150.png",
  "/privacy/choices/",
  "/privacy/",
  "/push/OneSignalSDKWorker.js",
  "/robots.txt",
  "/safari-pinned-tab.svg",
  "/site.webmanifest",
  "/sitemap.xml",
  "/support/",
  "/terms/",
  "/version.json",
  "/web-assets/auth_service-Bycevz_n.js",
  "/web-assets/blueprint_selector-BwSLCeip.js",
  "/web-assets/blueprint-DmWIgusI.css",
  "/web-assets/favicon-D3FZdTM-.ico",
  "/web-assets/form_page-DcnKdX9k.js",
  "/web-assets/FuturaPTBook-CllV_rS_.ttf",
  "/web-assets/FuturaPTMedium-Blo3J6Ks.ttf",
  "/web-assets/GillSansBold-BTBG3NhQ.otf",
  "/web-assets/index-BxGoqAKg.js",
  "/web-assets/index-OsApwSkH.css",
  "/web-assets/login_modal-CLR0cuQ7.js",
  "/web-assets/order_preview-BySuSmvr.css",
  "/web-assets/order_preview-RJ97e9a7.js",
  "/web-assets/order_result-CAUj2tPu.js",
  "/web-assets/public_order_strings-DgqgOWWe.js",
  "/web-assets/settings_widget-B60RhvJQ.js",
  "/web-assets/toast-C66ajYTo.js"
];
const CORE_URLS = [
  "/delete-account/",
  "/festapp_pwa_bridge.js",
  "/festapp_update_prompt.js",
  "/festapp-version.json",
  "/flutter_bootstrap.js",
  "/flutter.html",
  "/flutter.js",
  "/",
  "/main.dart.js",
  "/privacy/choices/",
  "/privacy/",
  "/support/",
  "/terms/"
];
const FLUTTER_ENTRY = "/flutter.html";
const WEB_CLIENT_ENTRY = "/";
const FORCED_OCCASION_PATH = null;
const STANDALONE_DOCUMENT_PATHS = new Set([
  "/delete-account/",
  "/privacy/choices/",
  "/privacy/",
  "/support/",
  "/terms/"
]);
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
    if (await requiresEmergencyCutover()) await self.skipWaiting();
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
    /^\/main\.dart\.js_\d+\.part\.js$/.test(pathname) ||
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
  if (url.pathname === '/backend-activation.json') {
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
      const exactIndex = await cache.match(url.pathname.replace(/\/$/, '') + '/index.html');
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
