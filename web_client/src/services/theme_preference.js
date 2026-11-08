// This classic-script-compatible policy is embedded in both startup shells and
// imported by ThemeService. Startup never waits for another network request.
(function (global) {
    if (global.FestappThemePreference) return;
    function readMode(storage) {
        try {
            const saved = storage?.getItem('theme');
            if (['light', 'dark', 'auto'].includes(saved)) return saved;
            for (const key of ['adaptive_theme_preferences', 'flutter.adaptive_theme_preferences']) {
                try {
                    let legacy = JSON.parse(storage?.getItem(key) ?? 'null');
                    if (typeof legacy === 'string') legacy = JSON.parse(legacy);
                    const mode = {0: 'light', 1: 'dark', 2: 'auto'}[legacy?.theme_mode];
                    if (mode) {
                        try { storage.setItem('theme', mode); } catch { /* Migration is best effort. */ }
                        return mode;
                    }
                } catch { /* Malformed or unavailable legacy data. */ }
            }
        } catch { /* Storage may be denied. */ }
        return 'auto';
    }
    const isDark = (mode, systemDark) => mode === 'dark' || (mode !== 'light' && !!systemDark);
    function paintTheme(dark) {
        const document = global.document;
        if (!document) return;
        const root = document.documentElement;
        const embedded = global.__FESTAPP_CLIENT_RUNTIME__ === 'web' && root.hasAttribute('data-embed-startup');
        const hostScheme = root.dataset.embedTheme === 'host' ? root.dataset.embedColorScheme : null;
        if (['light', 'dark'].includes(hostScheme)) dark = hostScheme === 'dark';
        const mode = dark ? 'dark' : 'light';
        // A scheme mismatch makes browsers replace an iframe's transparent
        // canvas with opaque black/white. The embedded media preference comes
        // from its host; a saved standalone app preference must not override it.
        const canvasScheme = embedded ? 'light dark' : mode;
        const color = document.querySelector('meta[name="theme-color"]');
        if (color) color.dataset.darkColor ||= color.content;
        const background = dark ? color?.dataset.darkColor || '#232529' : color?.dataset.lightColor || '#ffffff';
        root.dataset.startupTheme = mode;
        root.style.colorScheme = canvasScheme;
        root.style.backgroundColor = embedded && !global.__FESTAPP_APP_READY__ ? 'transparent' : background;
        root.style.setProperty('--festapp-startup-background', background);
        root.style.setProperty('--festapp-startup-foreground', dark ? '#bdbdbd' : '#000000');
        if (color) color.content = background;
        const scheme = document.querySelector('meta[name="color-scheme"]');
        if (scheme) scheme.content = canvasScheme;
        if (document.body) {
            document.body.style.colorScheme = mode;
            document.body.classList.toggle('dark-mode', dark);
        }
        for (const logo of document.querySelectorAll('.initial-logo, .startup-brand')) {
            logo.dataset.darkSrc ||= logo.getAttribute('src').replace(/-light\.svg$/, '.svg');
            const source = logo.dataset.darkSrc;
            logo.setAttribute('src', !dark && /(?:loading-animation|loading-logo)\.svg$/.test(source)
                ? source.replace(/\.svg$/, '-light.svg') : source);
            logo.dataset.startupLogoReady = '';
        }
    }
    global.FestappThemePreference = Object.freeze({readMode, isDark, paintTheme});
    if (!global.document || !global.addEventListener) return;
    const system = global.matchMedia?.('(prefers-color-scheme: dark)');
    function applyStartup() {
        if (global.__FESTAPP_APP_READY__) return;
        let storage;
        try { storage = global.localStorage; } catch { /* optional API */ }
        const embedded = global.__FESTAPP_CLIENT_RUNTIME__ === 'web' && global.document.documentElement.hasAttribute('data-embed-startup');
        paintTheme(embedded ? !!system?.matches : isDark(readMode(storage), system?.matches));
    }
    global.applyFestappStartupTheme = applyStartup;
    applyStartup();
    system?.addEventListener('change', applyStartup);
    global.addEventListener('storage', event => {
        if (event.key === 'theme' || event.key === null) applyStartup();
    });
    global.addEventListener('pageshow', applyStartup);
    global.addEventListener('festapp-embed-theme-changed', applyStartup);
})(globalThis);
