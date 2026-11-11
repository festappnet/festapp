// Existing update UI; all navigation is delegated to the controller.
export function createUpdatePresentation({currentVersion, canShow, onReload}) {
  const dismissedStorageKey = 'festappDismissedVersion';
  const bannerId = 'festapp-update-banner';
  function getActiveLanguage() {
    // Prefer the language the user explicitly picked inside the app
    // (Flutter easy_localization → flutter.locale, web client → locale).
    // Fall back to the browser's navigator.language only if nothing was
    // saved — otherwise a Czech user with English browser settings would
    // see the banner in English.
    try {
      const flutterRaw = localStorage.getItem('flutter.locale') ||
        localStorage.getItem('flutter.Locale');
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
        loading: 'Obnovuji...',
        diagnostic: 'Kód pro podporu'
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
        loading: 'Refreshing...',
        diagnostic: 'Support code'
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
        loading: 'Obnovujem...',
        diagnostic: 'Kód pre podporu'
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
        loading: 'Aktualisiere...',
        diagnostic: 'Support-Code'
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
        loading: 'Odświeżanie...',
        diagnostic: 'Kod pomocy'
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
        loading: 'Оновлення...',
        diagnostic: 'Код підтримки'
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
    if (!canShow()) return;
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
    if (reason === 'legacy-cache' && window.__FESTAPP_APP_READY__ !== true) {
      const diagnostic = document.createElement('div');
      diagnostic.setAttribute('data-festapp-startup-diagnostic', 'true');
      const version = String(currentVersion || '')
        .replace(/[^0-9A-Za-z.+-]/g, '').slice(0, 40);
      const candidate = window.getFestappStartupPhase?.();
      const phase = /^S(?:0[0-9]|1[0-3])$/.test(candidate) ? candidate : 'S00';
      diagnostic.textContent = copy.diagnostic + ': ' + version + ' / ' + phase;
      diagnostic.style.fontSize = '12px';
      diagnostic.style.marginTop = '4px';
      message.append(diagnostic);
    }
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
      try {
        await onReload(latestVersion);
      } finally {
        reloadButton.disabled = false;
        reloadButton.textContent = copy.reload;
      }
    });

    actions.append(laterButton, reloadButton);
    banner.append(message, actions);
    document.body.appendChild(banner);
  }

  return showUpdateBanner;
}
