// Presentation-only consumer. The bridge owns origin/instance checks; this module
// accepts bounded values, never host CSS, markup, scripts or purchase settings.
export class EmbedTheme {
    constructor(win) {
        this.win = win;
        this.fonts = new Map();
    }
    apply(theme) {
        const root = this.win.document.documentElement;
        const properties = {fontFamily: ['font-family', 'font-family'], text: ['text', 'color'],
            background: ['background', 'color'], primary: ['primary', 'color'], buttonText: ['button-text', 'color']};
        if (theme !== null && (typeof theme !== 'object' || !theme ||
            !Object.entries(properties).every(([key, [, property]]) =>
                typeof theme[key] === 'string' && theme[key].length <= 512 &&
                this.win.CSS?.supports(property, theme[key])))) return;
        if (theme === null) {
            delete root.dataset.embedTheme;
            for (const [name] of Object.values(properties)) root.style.removeProperty(`--embed-${name}`);
            this.clearFonts();
            return;
        }
        root.dataset.embedTheme = 'host';
        for (const [key, [name]] of Object.entries(properties)) root.style.setProperty(`--embed-${name}`, theme[key]);
        const requested = new Set();
        if (Array.isArray(theme.fonts) && theme.fonts.length <= 32 && this.win.FontFace && this.win.document.fonts) {
            for (const font of theme.fonts) {
                if (!font || typeof font.family !== 'string' || font.family.length > 256 ||
                    !Array.isArray(font.urls) || !font.urls.length || font.urls.length > 4 ||
                    !font.urls.every(value => {
                        if (typeof value !== 'string' || value.length > 4096) return false;
                        try { const url = new URL(value); return /^https?:$/.test(url.protocol) && !url.username && !url.password; } catch { return false; }
                    })) continue;
                const descriptors = {};
                if (!['weight', 'style', 'stretch', 'unicodeRange'].every(key => {
                    if (typeof font[key] !== 'string' || font[key].length > 512) return false;
                    descriptors[key] = font[key]; return true;
                })) continue;
                const key = JSON.stringify(font);
                requested.add(key);
                if (this.fonts.has(key)) continue;
                try {
                    const face = new this.win.FontFace(font.family, font.urls.map(url => `url(${JSON.stringify(url)})`).join(', '), {...descriptors, display: 'swap'});
                    this.fonts.set(key, face);
                    this.win.document.fonts.add(face);
                    // Font loading/CORS failure preserves the supplied font-family fallback.
                    face.load().catch(() => {});
                } catch { /* Invalid descriptors do not affect checkout. */ }
            }
        }
        for (const [key, face] of this.fonts) {
            if (!requested.has(key)) { this.win.document.fonts.delete(face); this.fonts.delete(key); }
        }
    }
    clearFonts() {
        for (const face of this.fonts.values()) this.win.document.fonts.delete(face);
        this.fonts.clear();
    }
    destroy() { this.apply(null); }
}
