import {queryWorkerBuildVersion} from './worker_shell.js';
import {createUpdatePresentation} from './update_banner.js';
import {pageContext} from './page_context.js';
import {installRuntimeState} from './runtime_state.js';

export function initFestappUpdatePrompt() {
  if (window.__FESTAPP_LOCAL_DEVELOPMENT__) return;
  const runtime = installRuntimeState(window);
  const embedded = () => pageContext(window.location) === 'public-embed';
  let cutoverInFlight = false;
  const allowed = reason => runtime.allowed(reason);
  function navigate(reason, destination) {
    return runtime.navigate(reason, () => {
      if (destination) window.location.replace(destination);
      else window.location.reload();
    });
  }

  const currentVersion = window.__FESTAPP_BUILD_VERSION__;
  const dismissedStorageKey = 'festappDismissedVersion';
  const cutoverStorageKey = 'festappCutoverVersion';
  const cleanRecoveryStorageKey = 'festappCleanRecoveryVersion';
  const startupRecoveryStorageKey = 'festappStartupRecoveryVersion';
  const runtimeRecoveryStorageKey = 'festappRuntimeRecoveryVersion';
  const bannerId = 'festapp-update-banner';
  let checkInFlight = false;
  let lastVersionCheckAt = null;
  let runtimeRecoveryInFlight = false;

  // Compatibility boundary for installations created before Festapp's worker.
  // Remove after the minimum supported installed version is newer than that
  // migration generation; never add festapp-app-shell-* to this adapter.
  async function clearLegacyFlutterCaches(reason = 'legacy-migration') {
    try {
      if ('serviceWorker' in navigator) {
        const registrations = await navigator.serviceWorker.getRegistrations();
        const flutterRegistrations = registrations.filter(function(registration) {
          const scriptUrl = registration.active?.scriptURL ||
            registration.waiting?.scriptURL ||
            registration.installing?.scriptURL ||
            '';
          return scriptUrl.includes('flutter_service_worker.js');
        });

        await Promise.all(flutterRegistrations.map(function(registration) {
          if (allowed(reason)) return registration.unregister();
        }));
      }

      if ('caches' in window) {
        const cacheNames = await caches.keys();
        await Promise.all(cacheNames
          .filter(function(cacheName) {
            return cacheName.startsWith('flutter-app-cache');
          })
          .map(function(cacheName) {
            if (allowed(reason)) return caches.delete(cacheName);
          }));
      }
    } catch (error) {
      console.warn('Legacy Flutter cache cleanup failed:', error);
    }
  }

  // Refresh the registration without unregistering the worker or deleting its
  // caches. Both are origin-wide operations and could strand another open tab
  // that is still executing the previous build.
  async function prepareNetworkReload() {
    try {
      if ('serviceWorker' in navigator) {
        const registration = await navigator.serviceWorker.getRegistration('/');
        if (registration) await registration.update();
      }
    } catch (error) {
      console.warn('Festapp network reload preparation failed:', error);
    }
  }

  // The manifest can reach an edge before the matching executable shell. A
  // worker version handshake proves that the coherent shell was installed.
  async function networkBuildVersion() {
    try {
      const response = await fetch('/festapp-version.json?refresh=' + Date.now(), {
        cache: 'no-store', headers: { 'cache-control': 'no-cache' }
      });
      return response.ok ? (await response.json()).version : null;
    } catch (_) {
      return null;
    }
  }

  async function repairActiveAppShell(version) {
    const worker = navigator.serviceWorker?.controller;
    if (!worker || typeof MessageChannel === 'undefined') return false;
    return new Promise(function(resolve) {
      const channel = new MessageChannel();
      const timeout = window.setTimeout(function() { finish(false); }, 120000);
      function finish(ok) {
        window.clearTimeout(timeout);
        channel.port1.close?.();
        resolve(ok);
      }
      channel.port1.onmessage = function(event) {
        finish(event.data?.ok === true && event.data?.version === version);
      };
      try {
        worker.postMessage({ type: 'FESTAPP_REPAIR_APP_SHELL', version: version, runtime: window.__FESTAPP_CLIENT_RUNTIME__ || 'flutter' },
          [channel.port2]);
      } catch (_) {
        finish(false);
      }
    });
  }

  function queryWorkerVersion(worker) {
    return queryWorkerBuildVersion(worker, window.__FESTAPP_CLIENT_RUNTIME__ || 'flutter', window);
  }

  async function waitUntilInstalled(worker) {
    if (!worker) return null;
    if (worker.state === 'installed' || worker.state === 'activated') return worker;
    return new Promise(function(resolve) {
      const timeout = window.setTimeout(function() { resolve(null); }, 120000);
      worker.addEventListener('statechange', function onStateChange() {
        if (worker.state !== 'installed' && worker.state !== 'activated' &&
            worker.state !== 'redundant') return;
        window.clearTimeout(timeout);
        worker.removeEventListener('statechange', onStateChange);
        resolve(worker.state === 'redundant' ? null : worker);
      });
    });
  }

  async function getReadyWorkerForVersion(expectedVersion) {
    if (!('serviceWorker' in navigator)) return null;
    try {
      const registration = await navigator.serviceWorker.getRegistration('/');
      if (!registration) return null;
      await registration.update();
      const candidate = await waitUntilInstalled(
        registration.waiting || registration.installing,
      );
      if (candidate && await queryWorkerVersion(candidate) === expectedVersion) {
        return { registration: registration, worker: candidate };
      }
      if (registration.active &&
          await queryWorkerVersion(registration.active) === expectedVersion) {
        return { registration: registration, worker: registration.active };
      }
    } catch (error) {
      console.warn('Festapp update preparation failed:', error);
    }
    return null;
  }

  // If the user accepted a version but the old HTML returned, the normal
  // cutover has failed. Perform one clean, cache-busted restart and never
  // offer the same update banner again from that stale page.
  async function recoverFailedCutover(latestVersion, onlyIfStalled = false) {
    const reason = onlyIfStalled ? 'startup' : 'background';
    if (!allowed(reason)) return false;
    if (cutoverInFlight || !latestVersion || navigator.onLine === false ||
        sessionStorage.getItem(cleanRecoveryStorageKey) === latestVersion) {
      return false;
    }
    sessionStorage.setItem(cleanRecoveryStorageKey, latestVersion);
    try {
      if ('serviceWorker' in navigator) {
        const registration = await navigator.serviceWorker.getRegistration('/');
        if (registration) await registration.update();
      }
      await clearLegacyFlutterCaches(reason);
      if (onlyIfStalled && window.__FESTAPP_APP_READY__ === true) return false;
      const recoveryUrl = new URL(window.location.href);
      recoveryUrl.searchParams.set('festapp-recovery', latestVersion);
      return navigate(reason, recoveryUrl.toString());
    } catch (error) {
      console.error('Festapp clean update recovery failed:', error);
      return false;
    }
  }

  // Detects the obsolete Flutter-generated worker/cache. Current builds use
  // festapp_service_worker.js; it must never be removed by this migration.
  async function hasStaleFlutterServiceWorker() {
    try {
      if ('serviceWorker' in navigator) {
        const registrations = await navigator.serviceWorker.getRegistrations();
        const hasFlutterSw = registrations.some(function(registration) {
          const scriptUrl = registration.active?.scriptURL ||
            registration.waiting?.scriptURL ||
            registration.installing?.scriptURL ||
            '';
          return scriptUrl.includes('flutter_service_worker.js');
        });
        if (hasFlutterSw) {
          return true;
        }
      }

      if ('caches' in window) {
        const cacheNames = await caches.keys();
        if (cacheNames.some(function(cacheName) {
          return cacheName.startsWith('flutter-app-cache');
        })) {
          return true;
        }
      }
    } catch (error) {
      console.warn('Festapp stale service worker check failed:', error);
    }
    return false;
  }

  // "Deep refresh": evict only the obsolete worker/cache and reload once so
  // the new Festapp worker can take ownership of the installation.
  //
  // Guarded per app version via sessionStorage: after eviction the reload is
  // handled by the current Festapp worker, and the guard prevents a loop even
  // if the obsolete registration does not disappear immediately.
  async function deepRefreshIfStale() {
    const guardKey = 'festappDeepRefreshedVersion';
    try {
      if (sessionStorage.getItem(guardKey) === (currentVersion || '1')) {
        return false;
      }
      if (!(await hasStaleFlutterServiceWorker())) {
        return false;
      }
      sessionStorage.setItem(guardKey, currentVersion || '1');
      await clearLegacyFlutterCaches('explicit-update');
      return navigate('legacy-migration');
    } catch (error) {
      console.warn('Festapp deep refresh failed:', error);
      return false;
    }
  }

  const showUpdateBanner = createUpdatePresentation({currentVersion,
    canShow: () => !embedded(),
    onReload: async latestVersion => {
      await clearLegacyFlutterCaches('explicit-update');
      // Keep the last working shell until the matching new worker is installed,
      // activated and controlling this tab. If preparation fails, the user can
      // retry without losing the version that still launches offline.
      const targetVersion = await networkBuildVersion() || latestVersion;
        if (await cutOverToVersion(targetVersion,
            window.__FESTAPP_APP_READY__ !== true && targetVersion === currentVersion)) return;
        // Explicit user reload must not silently stall on a broken registration.
        // Leave cached shells intact for other open/offline tabs; only the next
        // navigation bypasses the obsolete registration.
        if (navigator.onLine !== false && await networkBuildVersion()) {
          const registration = await navigator.serviceWorker?.getRegistration('/');
          if (!allowed('explicit-update')) return;
          if (registration) await registration.unregister();
          const destination = new URL(window.location.href);
          destination.searchParams.set('festapp-recovery', targetVersion);
          navigate('explicit-update', destination.toString());
        }
    }
  });

  async function activateWaitingFestappWorker(expectedVersion, reason) {
    try {
      const ready = await getReadyWorkerForVersion(expectedVersion);
      if (!ready) return false;
      // Installation may finish after the first usable frame. A background
      // update must yield before replacing the now-interactive controller.
      if (!allowed(reason)) {
        showUpdateBanner(expectedVersion, 'new-version');
        return false;
      }
      const registration = ready.registration;
      const candidate = ready.worker;
      if (candidate === registration.active && candidate.state === 'activated') return true;
      if (candidate && candidate.state === 'installed') {
        // `activated` can be observed just before this page's controller is
        // replaced. Reloading in that gap lets the previous worker handle the
        // navigation and serve the previous shell again, leaving the cutover
        // guard set even though the tab never reached the new build.
        const controlled = new Promise(function(resolve) {
          if (navigator.serviceWorker.controller === candidate) {
            resolve(true);
            return;
          }
          const timeout = window.setTimeout(function() {
            navigator.serviceWorker.removeEventListener('controllerchange', onControllerChange);
            resolve(false);
          }, 15000);
          function onControllerChange() {
            window.clearTimeout(timeout);
            navigator.serviceWorker.removeEventListener('controllerchange', onControllerChange);
            resolve(true);
          }
          navigator.serviceWorker.addEventListener('controllerchange', onControllerChange);
        });
        const activated = new Promise(function(resolve) {
          const timeout = window.setTimeout(function() { resolve(false); }, 15000);
          candidate.addEventListener('statechange', function onStateChange() {
            if (candidate.state !== 'activated' && candidate.state !== 'redundant') return;
            window.clearTimeout(timeout);
            candidate.removeEventListener('statechange', onStateChange);
            resolve(candidate.state === 'activated');
          });
        });
        if (!allowed(reason)) return false;
        candidate.postMessage('SKIP_WAITING');
        if (!(await activated)) return false;
        return await controlled;
      }
      return candidate?.state === 'activated' && candidate === registration.active;
    } catch (error) {
      console.warn('Festapp service worker activation failed:', error);
      return false;
    }
  }

  async function cutOverToVersion(latestVersion, repair = false, onlyIfStalled = false, reason = onlyIfStalled ? 'startup' : 'explicit-update') {
    if (!latestVersion || cutoverInFlight || !allowed(reason)) return false;
    cutoverInFlight = true;
    try {
      if (!(await activateWaitingFestappWorker(latestVersion, reason)) || !allowed(reason)) return false;
      if (repair && !(await repairActiveAppShell(latestVersion))) return false;
      if (!allowed(reason)) return false;
      sessionStorage.setItem(cutoverStorageKey, latestVersion);
      return navigate(reason);
    } finally { cutoverInFlight = false; }
  }

  async function recoverStalledStartup(reason) {
    if (!allowed('startup')) return false;

    // Never destroy the only available offline shell. Recovery needs the
    // network so that the next navigation can fetch one coherent build.
    if (navigator.onLine === false) {
      showUpdateBanner(currentVersion, 'legacy-cache');
      return false;
    }

    if (sessionStorage.getItem(startupRecoveryStorageKey) === currentVersion) {
      console.error('Festapp startup remained stalled after recovery:', reason);
      showUpdateBanner(currentVersion, 'legacy-cache');
      return false;
    }

    console.warn('Festapp startup stalled; retrying from the network:', reason);
    sessionStorage.setItem(startupRecoveryStorageKey, currentVersion || '1');
    const targetVersion = await networkBuildVersion() || currentVersion;
    const recovered = await cutOverToVersion(targetVersion, targetVersion === currentVersion, true);
    if (!recovered && window.__FESTAPP_APP_READY__ !== true) showUpdateBanner(targetVersion, 'legacy-cache');
    return recovered;
  }

  function isDartDispatchRuntimeFailure(event) {
    const candidates = [
      event?.message,
      event?.error?.message,
      event?.reason?.message,
      event?.reason,
    ];
    return candidates.some(function(candidate) {
      const message = typeof candidate === 'string' ? candidate : '';
      return message.includes('Cannot define property ___dart_dispatch_record') &&
        message.includes('object is not extensible');
    });
  }

  async function recoverCorruptRuntime(reason) {
    if (runtimeRecoveryInFlight) return false;
    runtimeRecoveryInFlight = true;

    if (navigator.onLine === false ||
        sessionStorage.getItem(runtimeRecoveryStorageKey) === currentVersion) {
      showUpdateBanner(currentVersion, 'legacy-cache');
      return false;
    }

    console.warn('Festapp Dart runtime is inconsistent; loading a coherent app shell:', reason);
    sessionStorage.setItem(runtimeRecoveryStorageKey, currentVersion || '1');
    if (await cutOverToVersion(currentVersion, false, false, 'corrupt-runtime')) return true;
    await prepareNetworkReload();
    return navigate('corrupt-runtime');
  }

  function scheduleStartupRecovery() {
    window.setTimeout(function checkStartup() {
      if (window.__FESTAPP_APP_READY__ === true) return;
      if (document.visibilityState !== 'visible') {
        document.addEventListener('visibilitychange', function retryWhenVisible() {
          if (document.visibilityState !== 'visible') return;
          document.removeEventListener('visibilitychange', retryWhenVisible);
          recoverStalledStartup('resume-timeout');
        });
        return;
      }
      recoverStalledStartup('timeout');
    }, 20000);
  }

  async function checkVersion() {
    // Keep startup recovery, but never interrupt an interactive embedded form.
    reportClientVersion();
    if (!allowed('background')) return;
    if (checkInFlight || !currentVersion || navigator.onLine === false) {
      return;
    }
    // Focus, visibility and the startup timer can arrive separately, after a
    // fast response has already completed. Reuse that recent network truth.
    if (lastVersionCheckAt !== null && Date.now() - lastVersionCheckAt < 30000) {
      return;
    }
    checkInFlight = true;

    try {
      const response = await fetch('/festapp-version.json?t=' + Date.now(), {
        cache: 'no-store',
        headers: {
          'cache-control': 'no-cache',
          'pragma': 'no-cache'
        }
      });

      if (!response.ok) {
        return;
      }

      const data = await response.json();
      if (!allowed('background')) return;
      const latestVersion = data && data.version;
      if (!latestVersion) {
        return;
      }
      lastVersionCheckAt = Date.now();
      if (latestVersion === currentVersion) {
        // A network navigation can already serve the new HTML while the tab is
        // still controlled by the previous worker. In that mixed state the
        // document and manifest agree, so the normal "new version" branch
        // cannot detect that main.dart.js is still coming from the old shell.
        // Activate the already-installed worker for this document before the
        // stale runtime can keep using another tenant's compiled configuration.
        const registration = 'serviceWorker' in navigator
          ? await navigator.serviceWorker.getRegistration('/')
          : null;
        const activeVersion = await queryWorkerVersion(registration?.active);
        if (!allowed('background')) return;
        if (activeVersion && activeVersion !== currentVersion) {
          // Once the app is interactive, an automatic controller cutover can
          // race with a tap and reload the tab after navigation has begun. Keep
          // the working page intact and let the user choose when to refresh.
          // Startup still cuts over automatically before the first usable frame.
          if (window.__FESTAPP_APP_READY__ === true) {
            if (await getReadyWorkerForVersion(currentVersion)) {
              showUpdateBanner(currentVersion, 'legacy-cache');
            }
            return;
          }
          if (await cutOverToVersion(currentVersion, false, true)) return;
        }
        sessionStorage.removeItem(cutoverStorageKey);
        sessionStorage.removeItem(cleanRecoveryStorageKey);
        return;
      }

      if (sessionStorage.getItem(cutoverStorageKey) === latestVersion) {
        await recoverFailedCutover(latestVersion, embedded());
        return;
      }

      // Inform an interactive app immediately. Installing a worker can stall
      // or fail; it must not hide the update indefinitely. The explicit reload
      // action still verifies and activates the coherent shell before cutover.
      if (window.__FESTAPP_APP_READY__ === true) {
        showUpdateBanner(latestVersion, 'new-version');
        return;
      }
      if (!(await getReadyWorkerForVersion(latestVersion))) {
        showUpdateBanner(latestVersion, 'new-version');
        return;
      }

      // A page still on its loader may already have hit an incomplete stale
      // shell, so recover it automatically. Once Flutter is running, preserve
      // in-progress form edits and let the user choose when to reload.
      if (window.__FESTAPP_APP_READY__ !== true &&
          await cutOverToVersion(latestVersion, false, true)) return;
      showUpdateBanner(latestVersion, 'new-version');
    } catch (error) {
      console.warn('Festapp version check failed:', error);
    } finally {
      checkInFlight = false;
    }
  }

  window.clearLegacyFlutterCaches = clearLegacyFlutterCaches;
  window.prepareFestappNetworkReload = prepareNetworkReload;
  window.deepRefreshIfStale = deepRefreshIfStale;
  window.cutOverToVersion = cutOverToVersion;
  window.recoverFailedFestappCutover = recoverFailedCutover;
  window.recoverFestappStartup = recoverStalledStartup;
  function reportClientVersion() {
    navigator.serviceWorker?.controller?.postMessage({
      type: 'FESTAPP_CLIENT_VERSION',
      version: currentVersion,
    });
  }
  if ('serviceWorker' in navigator) {
    if (navigator.serviceWorker.ready) {
      navigator.serviceWorker.ready.then(reportClientVersion).catch(function() {});
    }
    navigator.serviceWorker.addEventListener('message', function(event) {
      if (event.data?.type === 'FESTAPP_REPORT_VERSION') reportClientVersion();
    });
    navigator.serviceWorker.addEventListener('controllerchange', reportClientVersion);
  }
  window.addEventListener('festapp-app-ready', function() {
    sessionStorage.removeItem(startupRecoveryStorageKey);
    reportClientVersion();
  });
  window.addEventListener('load', function() {
    // Self-heal first: if a stale build is cached this triggers a one-time
    // hard reload, so skip the (now moot) passive version check for this load.
    deepRefreshIfStale().then(function(reloading) {
      if (!reloading) {
        window.setTimeout(checkVersion, 3000);
        scheduleStartupRecovery();
      }
    });
  });
  window.addEventListener('focus', function() {
    reportClientVersion();
    checkVersion();
  });
  window.addEventListener('festapp-update-available', function(event) {
    const detail = event.detail || {};
    showUpdateBanner(detail.version || currentVersion, detail.reason);
  });
  window.addEventListener('error', function(event) {
    if (isDartDispatchRuntimeFailure(event)) {
      recoverCorruptRuntime('dart-dispatch-error');
    }
  });
  window.addEventListener('unhandledrejection', function(event) {
    if (isDartDispatchRuntimeFailure(event)) {
      recoverCorruptRuntime('dart-dispatch-rejection');
    }
  });
  document.addEventListener('visibilitychange', function() {
    if (document.visibilityState === 'visible') {
      reportClientVersion();
      checkVersion();
    }
  });
  window.setInterval(checkVersion, 5 * 60 * 1000);
}
