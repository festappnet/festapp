export function createHostPresentation(onStylesReady) {
    // The saved form owns appearance; the host only supplies presentation tokens.
    const externalSheets = new Map();
    const fontFamily = value => value.trim().replace(/^["']|["']$/g, '').toLowerCase();
    const fontFaces = (family) => {
        const families = family.split(',').map(fontFamily);
        const faces = [];
        const visited = new Set();
        const read = (sheet, base) => {
            if (!sheet || visited.has(sheet) || faces.length >= 32) return;
            visited.add(sheet);
            let rules;
            try { rules = sheet.cssRules; } catch {
                // Cross-origin CSS is readable only when its owner permits CORS.
                if (sheet.href && !externalSheets.has(sheet.href) && window.CSSStyleSheet && window.fetch) {
                    externalSheets.set(sheet.href, null);
                    window.fetch(sheet.href, {mode: 'cors', credentials: 'omit'})
                        .then(response => { if (!response.ok) throw new Error('Stylesheet unavailable'); return response.text(); })
                        .then(css => {
                            if (css.length > 1000000) return;
                            const parsed = new CSSStyleSheet(); parsed.replaceSync(css);
                            externalSheets.set(sheet.href, parsed); onStylesReady();
                        }).catch(() => {});
                }
                const cached = externalSheets.get(sheet.href);
                if (cached) read(cached, sheet.href);
                return;
            }
            for (const rule of rules) {
                if (faces.length >= 32) break;
                if (rule.type === 5 && families.includes(fontFamily(rule.style.getPropertyValue('font-family')))) {
                    const urls = [];
                    const source = rule.style.getPropertyValue('src');
                    for (const match of source.matchAll(/url\(\s*(?:"([^"\n]+)"|'([^'\n]+)'|([^)'"\s]+))\s*\)/gi)) {
                        try {
                            const url = new URL(match[1] || match[2] || match[3], base);
                            if (/^https?:$/.test(url.protocol) && !url.username && !url.password) urls.push(url.href);
                        } catch { /* Invalid font URL cannot be transferred. */ }
                    }
                    if (urls.length) faces.push({family: rule.style.getPropertyValue('font-family').trim().replace(/^["']|["']$/g, ''), urls: urls.slice(0, 4),
                        weight: rule.style.getPropertyValue('font-weight') || 'normal',
                        style: rule.style.getPropertyValue('font-style') || 'normal',
                        stretch: rule.style.getPropertyValue('font-stretch') || 'normal',
                        unicodeRange: rule.style.getPropertyValue('unicode-range') || 'U+0-10FFFF'});
                } else if (rule.styleSheet) read(rule.styleSheet, rule.href || base);
                else if (rule.cssRules) read(rule, base);
            }
        };
        for (const sheet of document.styleSheets) read(sheet, sheet.href || document.baseURI);
        return faces;
    };
    // Keep common sRGB tokens cheap; let the browser normalize other CSS colors.
    let colorContext;
    const nativeColor = color => {
        if (!color || /\b(?:var|env|currentcolor|inherit|initial|unset|revert|revert-layer)\b/i.test(color)) return null;
        try {
            if (!window.CSS?.supports?.('color', color)) return null;
            if (colorContext === undefined) {
                const canvas = document.createElement('canvas');
                canvas.width = canvas.height = 1;
                colorContext = canvas.getContext('2d', {willReadFrequently: true});
            }
            if (!colorContext) return null;
            // Two sentinels distinguish rejected assignments from real colors.
            colorContext.fillStyle = '#000000';
            colorContext.fillStyle = color;
            const first = colorContext.fillStyle;
            colorContext.fillStyle = '#ffffff';
            colorContext.fillStyle = color;
            if (colorContext.fillStyle !== first) return null;
            colorContext.clearRect(0, 0, 1, 1);
            colorContext.fillRect(0, 0, 1, 1);
            const pixel = colorContext.getImageData(0, 0, 1, 1).data;
            return [pixel[0], pixel[1], pixel[2], pixel[3] / 255];
        } catch { return null; }
    };
    const rgba = value => {
        const color = (value || '').trim().toLowerCase();
        if (color === 'transparent') return [0, 0, 0, 0];
        if (color === 'black') return [0, 0, 0, 1];
        if (color === 'white') return [255, 255, 255, 1];
        if (/^#(?:[\da-f]{3,4}|[\da-f]{6}|[\da-f]{8})$/.test(color)) {
            let hex = color.slice(1);
            if (hex.length < 5) hex = [...hex].map(c => c + c).join('');
            return [0, 2, 4].map(i => parseInt(hex.slice(i, i + 2), 16))
                .concat(hex.length === 8 ? parseInt(hex.slice(6), 16) / 255 : 1);
        }
        const match = color.match(/^rgba?\(([^)]+)\)$/);
        if (!match) return nativeColor(color);
        const parts = match[1].trim().split(/[\s, /]+/);
        if (parts.length < 3 || parts.length > 4 || parts.some(p => !/^[+-]?(?:\d*\.)?\d+%?$/.test(p))) return null;
        return parts.slice(0, 3).map(p => Math.max(0, Math.min(255, parseFloat(p) * (p.endsWith('%') ? 2.55 : 1))))
            .concat(parts[3] === undefined ? 1 : Math.max(0, Math.min(1, parseFloat(parts[3]) / (parts[3].endsWith('%') ? 100 : 1))));
    };
    const over = (front, back) => front.slice(0, 3).map((c, i) => c * front[3] + back[i] * (1 - front[3])).concat(1);
    const cssColor = color => `rgb(${color.slice(0, 3).map(Math.round).join(', ')})`;
    const backgroundAt = node => {
        const layers = [];
        for (; node; node = node.parentElement) {
            const color = rgba(getComputedStyle(node).backgroundColor);
            if (!color) return null;
            if (color[3] === 0) continue;
            layers.push(color);
            if (color[3] === 1) break;
        }
        return layers.reverse().reduce((back, front) => over(front, back), [255, 255, 255, 1]);
    };
    const luminance = color => color.slice(0, 3).reduce((sum, channel, i) => {
        const value = channel / 255;
        return sum + (value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4) * [0.2126, 0.7152, 0.0722][i];
    }, 0);
    const contrast = (a, b) => (Math.max(luminance(a), luminance(b)) + 0.05) / (Math.min(luminance(a), luminance(b)) + 0.05);
    const presentation = frame => {
        const container = frame.parentElement;
        const style = getComputedStyle(container);
        const background = backgroundAt(container);
        if (!background) return null;
        // Checkout projections are output, never a source of website appearance.
        const selector = ':is(button, .wp-element-button, .wp-block-button__link):not([data-festapp-embed-price] *)';
        let buttonFill, buttonText;
        const candidates = new Set([...container.querySelectorAll(selector), ...document.querySelectorAll(selector)]);
        for (const button of candidates) {
            let visible = true;
            for (let node = button; node; node = node.parentElement) {
                const computed = getComputedStyle(node);
                if (node.hidden || computed.opacity === '0' || computed.display === 'none' ||
                    ['hidden', 'collapse'].includes(computed.visibility)) { visible = false; break; }
            }
            if (!visible) continue;
            const computed = getComputedStyle(button);
            const fill = rgba(computed.backgroundColor), text = rgba(computed.color);
            if (!fill || !text || !fill[3] || !text[3]) continue;
            const buttonBackground = backgroundAt(button.parentElement);
            if (!buttonBackground) continue;
            buttonFill = over(fill, buttonBackground);
            buttonText = over(text, buttonFill);
            break;
        }
        const preset = rgba(style.getPropertyValue('--wp--preset--color--primary'));
        const primary = over(preset?.[3] ? preset : buttonFill || rgba(style.color) || [0, 0, 0, 1], background).map(Math.round);
        // A preset owns its fill independently of a sampled button. Keep any
        // foreground only when it remains readable on the actual exported fill.
        let foreground = (buttonText || background).map(Math.round);
        if (contrast(primary, foreground) < 4.5) {
            const black = [0, 0, 0, 1], white = [255, 255, 255, 1];
            foreground = contrast(primary, black) >= contrast(primary, white) ? black : white;
        }
        const declaredScheme = style.colorScheme || 'normal';
        const colorScheme = declaredScheme.includes('dark') && !declaredScheme.includes('light') ? 'dark'
            : declaredScheme.includes('light') && !declaredScheme.includes('dark') ? 'light'
            : luminance(background) < 0.179 ? 'dark' : 'light';
        return {fontFamily: style.fontFamily, text: style.color, background: cssColor(background), colorScheme, primary: cssColor(primary),
            buttonText: cssColor(foreground), fonts: fontFaces(style.fontFamily)};
    };
    return presentation;
}
