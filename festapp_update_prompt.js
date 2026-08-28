(function initFestappUpdatePrompt() {
  if (window.__FESTAPP_LOCAL_DEVELOPMENT__) return;

  const currentVersion = window.__FESTAPP_BUILD_VERSION__;
  const dismissedStorageKey = 'festappDismissedVersion';
  const cutoverStorageKey = 'festappCutoverVersion';
  const cleanRecoveryStorageKey = 'festappCleanRecoveryVersion';
  const startupRecoveryStorageKey = 'festappStartupRecoveryVersion';
  const bannerId = 'festapp-update-banner';
  let checkInFlight = false;

  // Compatibility boundary for installations created before Festapp's worker.
  // Remove after the minimum supported installed version is newer than that
  // migration generation; never add festapp-app-shell-* to this adapter.
  async function clearLegacyFlutterCaches() {
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
          return registration.unregister();
        }));
      }

      if ('caches' in window) {
        const cacheNames = await caches.keys();
        await Promise.all(cacheNames
          .filter(function(cacheName) {
            return cacheName.startsWith('flutter-app-cache');
          })
          .map(function(cacheName) {
            return caches.delete(cacheName);
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
  async function queryWorkerVersion(worker) {
    if (!worker || typeof MessageChannel === 'undefined') return null;
    return new Promise(function(resolve) {
      const channel = new MessageChannel();
      const timeout = window.setTimeout(function() { resolve(null); }, 3000);
      channel.port1.onmessage = function(event) {
        window.clearTimeout(timeout);
        resolve(event.data?.version || null);
      };
      try {
        worker.postMessage({ type: 'FESTAPP_QUERY_BUILD_VERSION' }, [channel.port2]);
      } catch (_) {
        window.clearTimeout(timeout);
        resolve(null);
      }
    });
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
  async function recoverFailedCutover(latestVersion) {
    if (!latestVersion || navigator.onLine === false ||
        sessionStorage.getItem(cleanRecoveryStorageKey) === latestVersion) {
      return false;
    }
    sessionStorage.setItem(cleanRecoveryStorageKey, latestVersion);
    try {
      if ('serviceWorker' in navigator) {
        const registration = await navigator.serviceWorker.getRegistration('/');
        if (registration) await registration.update();
      }
      await clearLegacyFlutterCaches();
      const recoveryUrl = new URL(window.location.href);
      recoveryUrl.searchParams.set('festapp-recovery', latestVersion);
      window.location.replace(recoveryUrl.toString());
      return true;
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
      await clearLegacyFlutterCaches();
      window.location.reload();
      return true;
    } catch (error) {
      console.warn('Festapp deep refresh failed:', error);
      return false;
    }
  }

  function getActiveLanguage() {
    // Prefer the language the user explicitly picked inside the app
    // (Flutter easy_localization → flutter.Locale, web client → locale).
    // Fall back to the browser's navigator.language only if nothing was
    // saved — otherwise a Czech user with English browser settings would
    // see the banner in English.
    try {
      const flutterRaw = localStorage.getItem('flutter.Locale');
      if (flutterRaw) {
        // easy_localization stores e.g. '"cs"', 'cs', or '{"languageCode":"cs"}'
        const trimmed = flutterRaw.replace(/^"+|"+$/g, '');
        try {
          const parsed = JSON.parse(flutterRaw);
          if (parsed && typeof parsed === 'object' && parsed.languageCode) {
            return String(parsed.languageCode).toLowerCase();
          }
        } catch (_) {}
        if (trimmed) return trimmed.toLowerCase();
      }
      const webClient = localStorage.getItem('locale');
      if (webClient) return webClient.toLowerCase();
    } catch (_) {}
    return (navigator.language || '').toLowerCase();
  }

  // One entry per app language (assets/translations); en is the fallback.
  const UPDATE_COPY = {
    cs: {
      'new-version': {
        message: 'Je dostupná nová verze aplikace.',
        reload: 'Načíst',
        later: 'Později',
        loading: 'Načítám...'
      },
      'legacy-cache': {
        message: 'Aplikace je připravená k obnovení.',
        reload: 'Obnovit',
        later: 'Později',
        loading: 'Obnovuji...'
      }
    },
    en: {
      'new-version': {
        message: 'A new version of the app is available.',
        reload: 'Reload',
        later: 'Later',
        loading: 'Reloading...'
      },
      'legacy-cache': {
        message: 'The app is ready to refresh.',
        reload: 'Refresh',
        later: 'Later',
        loading: 'Refreshing...'
      }
    },
    sk: {
      'new-version': {
        message: 'Je dostupná nová verzia aplikácie.',
        reload: 'Načítať',
        later: 'Neskôr',
        loading: 'Načítavam...'
      },
      'legacy-cache': {
        message: 'Aplikácia je pripravená na obnovenie.',
        reload: 'Obnoviť',
        later: 'Neskôr',
        loading: 'Obnovujem...'
      }
    },
    de: {
      'new-version': {
        message: 'Eine neue Version der App ist verfügbar.',
        reload: 'Laden',
        later: 'Später',
        loading: 'Wird geladen...'
      },
      'legacy-cache': {
        message: 'Die App ist bereit zur Aktualisierung.',
        reload: 'Aktualisieren',
        later: 'Später',
        loading: 'Aktualisiere...'
      }
    },
    pl: {
      'new-version': {
        message: 'Dostępna jest nowa wersja aplikacji.',
        reload: 'Załaduj',
        later: 'Później',
        loading: 'Ładowanie...'
      },
      'legacy-cache': {
        message: 'Aplikacja jest gotowa do odświeżenia.',
        reload: 'Odśwież',
        later: 'Później',
        loading: 'Odświeżanie...'
      }
    },
    uk: {
      'new-version': {
        message: 'Доступна нова версія застосунку.',
        reload: 'Завантажити',
        later: 'Пізніше',
        loading: 'Завантаження...'
      },
      'legacy-cache': {
        message: 'Застосунок готовий до оновлення.',
        reload: 'Оновити',
        later: 'Пізніше',
        loading: 'Оновлення...'
      }
    }
  };

  function getUpdateCopy(reason) {
    const language = getActiveLanguage();
    const langKey = Object.keys(UPDATE_COPY).find(function(code) {
      return language.startsWith(code);
    }) || 'en';
    const variant = reason === 'legacy-cache' ? 'legacy-cache' : 'new-version';
    return UPDATE_COPY[langKey][variant];
  }

  function showUpdateBanner(latestVersion, reason) {
    if (document.getElementById(bannerId) ||
        sessionStorage.getItem(dismissedStorageKey) === latestVersion) {
      return;
    }

    const copy = getUpdateCopy(reason);
    const banner = document.createElement('div');
    banner.id = bannerId;
    banner.setAttribute('role', 'status');
    banner.style.position = 'fixed';
    banner.style.left = '16px';
    banner.style.right = '16px';
    banner.style.bottom = '16px';
    banner.style.zIndex = '2147483647';
    banner.style.display = 'flex';
    banner.style.alignItems = 'center';
    banner.style.justifyContent = 'space-between';
    banner.style.gap = '12px';
    banner.style.padding = '12px 14px';
    banner.style.borderRadius = '8px';
    banner.style.boxShadow = '0 10px 30px rgba(0, 0, 0, 0.22)';
    banner.style.background = '#fff';
    banner.style.color = '#202124';
    banner.style.fontFamily = 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
    banner.style.fontSize = '14px';
    banner.style.lineHeight = '1.35';

    const message = document.createElement('div');
    message.textContent = copy.message;
    message.style.minWidth = '0';
    message.style.flex = '1 1 auto';

    const actions = document.createElement('div');
    actions.style.display = 'flex';
    actions.style.gap = '8px';
    actions.style.flex = '0 0 auto';

    const laterButton = document.createElement('button');
    laterButton.type = 'button';
    laterButton.textContent = copy.later;
    laterButton.setAttribute('data-festapp-update-action', 'later');
    laterButton.style.border = '1px solid #dadce0';
    laterButton.style.borderRadius = '6px';
    laterButton.style.background = '#fff';
    laterButton.style.color = '#202124';
    laterButton.style.padding = '8px 10px';
    laterButton.style.cursor = 'pointer';
    laterButton.addEventListener('click', function() {
      sessionStorage.setItem(dismissedStorageKey, latestVersion);
      banner.remove();
    });

    const reloadButton = document.createElement('button');
    reloadButton.type = 'button';
    reloadButton.textContent = copy.reload;
    reloadButton.setAttribute('data-festapp-update-action', 'reload');
    reloadButton.style.border = '1px solid #0000f4';
    reloadButton.style.borderRadius = '6px';
    reloadButton.style.background = '#0000f4';
    reloadButton.style.color = '#fff';
    reloadButton.style.padding = '8px 12px';
    reloadButton.style.cursor = 'pointer';
    reloadButton.addEventListener('click', async function() {
      reloadButton.disabled = true;
      reloadButton.textContent = copy.loading;
      await clearLegacyFlutterCaches();
      // Keep the last working shell until the matching new worker is installed,
      // activated and controlling this tab. If preparation fails, the user can
      // retry without losing the version that still launches offline.
      if (!(await cutOverToVersion(latestVersion))) {
        reloadButton.disabled = false;
        reloadButton.textContent = copy.reload;
      }
    });

    actions.append(laterButton, reloadButton);
    banner.append(message, actions);
    document.body.appendChild(banner);
  }

  async function activateWaitingFestappWorker(expectedVersion) {
    try {
      const ready = await getReadyWorkerForVersion(expectedVersion);
      if (!ready) return false;
      const registration = ready.registration;
      const candidate = ready.worker;
      if (candidate === registration.active &&
          navigator.serviceWorker.controller === candidate) return true;
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
        candidate.postMessage('SKIP_WAITING');
        if (!(await activated)) return false;
        return await controlled;
      }
      return candidate?.state === 'activated' &&
        navigator.serviceWorker.controller === candidate;
    } catch (error) {
      console.warn('Festapp service worker activation failed:', error);
      return false;
    }
  }

  async function cutOverToVersion(latestVersion) {
    if (!latestVersion) return false;
    const ready = await activateWaitingFestappWorker(latestVersion);
    if (!ready) return false;
    sessionStorage.setItem(cutoverStorageKey, latestVersion);
    window.location.reload();
    return true;
  }

  async function recoverStalledStartup(reason) {
    if (window.__FESTAPP_APP_READY__ === true) return false;

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
    await prepareNetworkReload();
    window.location.reload();
    return true;
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
    reportClientVersion();
    if (checkInFlight || !currentVersion || navigator.onLine === false) {
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
      const latestVersion = data && data.version;
      if (!latestVersion) {
        return;
      }
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
        if (activeVersion && activeVersion !== currentVersion &&
            await cutOverToVersion(currentVersion)) return;
        sessionStorage.removeItem(cutoverStorageKey);
        sessionStorage.removeItem(cleanRecoveryStorageKey);
        return;
      }

      if (sessionStorage.getItem(cutoverStorageKey) === latestVersion) {
        await recoverFailedCutover(latestVersion);
        return;
      }

      // Do not advertise a deployment merely because its manifest reached an
      // edge cache. The matching worker proves that the executable core was
      // downloaded and installed as one coherent shell.
      if (!(await getReadyWorkerForVersion(latestVersion))) return;

      // A page still on its loader may already have hit an incomplete stale
      // shell, so recover it automatically. Once Flutter is running, preserve
      // in-progress form edits and let the user choose when to reload.
      if (window.__FESTAPP_APP_READY__ !== true &&
          await cutOverToVersion(latestVersion)) return;
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
  document.addEventListener('visibilitychange', function() {
    if (document.visibilityState === 'visible') {
      reportClientVersion();
      checkVersion();
    }
  });
  window.setInterval(checkVersion, 5 * 60 * 1000);
})();
