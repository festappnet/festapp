/* Public documents only. This file must run before the application router. */
(() => {
    const script = document.currentScript;
    const token = script?.dataset.analyticsToken;
    const host = script?.dataset.analyticsHost;
    const current = new URL(window.location.href);
    const publicPath = path => path === '/' || path === '/events' ||
        /^\/unit\/[1-9]\d*\/?$/.test(path) || /^\/form\/[^/]+\/?$/.test(path);
    // Capability fragments, previews, auth and embedded checkout are deliberately
    // excluded, including legacy hash routes that the server cannot inspect.
    const publicQuery = key => /^(utm_(source|medium|campaign|term|content)|gclid|fbclid|q|lang)$/.test(key);
    if (!/^[a-f0-9]{32}$/.test(token || '') || current.hostname !== host ||
        current.protocol !== 'https:' || window.self !== window.top ||
        !publicPath(current.pathname) || current.hash ||
        [...current.searchParams.keys()].some(key => !publicQuery(key))) return;

    // The provider includes referrer paths in its payload. Only accept an
    // origin-only external referrer or another public page on this same site.
    // Skip the measurement rather than sending an unknown/private path.
    if (document.referrer) {
        try {
            const referrer = new URL(document.referrer);
            if (!['https:', 'http:'].includes(referrer.protocol) ||
                (referrer.pathname !== '/' &&
                    (referrer.origin !== current.origin || !publicPath(referrer.pathname)))) return;
        } catch { return; }
    }

    // Automatic SPA measurement cannot exclude capability URLs reliably. Keep
    // measured documents at their original pathname and use a document boundary
    // for path changes. Fragment overlays still work without a page reload.
    for (const [method, navigation] of [['pushState', 'assign'], ['replaceState', 'replace']]) {
        const original = window.history[method].bind(window.history);
        window.history[method] = function (state, title, url) {
            if (url != null) {
                const target = new URL(url, window.location.href);
                if (target.origin === current.origin && target.pathname !== current.pathname) {
                    window.location[navigation](target.href);
                    return;
                }
            }
            return original(state, title, url);
        };
    }
    const beacon = document.createElement('script');
    beacon.type = 'module';
    beacon.src = 'https://static.cloudflareinsights.com/beacon.min.js';
    // Zone-backed sites use Cloudflare's built-in same-origin collector. Manual
    // sites retain the provider's external endpoint. Both use the official beacon.
    const send = script.dataset.analyticsCollector === '/cdn-cgi/rum'
        ? { to: '/cdn-cgi/rum' } : undefined;
    beacon.dataset.cfBeacon = JSON.stringify({ token, spa: false, ...(send ? { send } : {}) });
    beacon.referrerPolicy = 'origin';
    document.head.appendChild(beacon);
})();
