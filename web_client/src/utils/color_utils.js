export class ColorUtils {
    /**
     * Parses a color string (Hex, RGB, RGBA) into {r, g, b}
     * Returns null if invalid.
     */
    static parseToRgb(color) {
        if (!color) return null;

        let r = 0, g = 0, b = 0;

        // Handle Hex
        if (color.startsWith('#')) {
            const cleanHex = color.substring(1);
            if (cleanHex.length === 3) {
                r = parseInt(cleanHex[0] + cleanHex[0], 16);
                g = parseInt(cleanHex[1] + cleanHex[1], 16);
                b = parseInt(cleanHex[2] + cleanHex[2], 16);
            } else if (cleanHex.length === 6) {
                r = parseInt(cleanHex.substring(0, 2), 16);
                g = parseInt(cleanHex.substring(2, 4), 16);
                b = parseInt(cleanHex.substring(4, 6), 16);
            } else {
                return null;
            }
        }
        // Handle RGB / RGBA
        else if (color.startsWith('rgb')) {
            const values = color.match(/\d+/g);
            if (values && values.length >= 3) {
                r = parseInt(values[0]);
                g = parseInt(values[1]);
                b = parseInt(values[2]);
            } else {
                return null;
            }
        } else {
             return null;
        }

        return { r, g, b };
    }

    /**
     * Converts a Hex string (e.g. #RRGGBB or #RGB) to HSL object {h, s, l}
     * h: 0-360, s: 0-1, l: 0-1
     */
    static hexToHsl(hex) {
        // Use the new parser, even though method is named hexToHsl
        const rgb = ColorUtils.parseToRgb(hex);
        if (!rgb) return { h: 0, s: 0, l: 0 }; // Fallback

        let { r, g, b } = rgb;
        r /= 255;
        g /= 255;
        b /= 255;
        
        let cmin = Math.min(r, g, b),
            cmax = Math.max(r, g, b),
            delta = cmax - cmin,
            h = 0,
            s = 0,
            l = 0;

        if (delta === 0)
            h = 0;
        else if (cmax === r)
            h = ((g - b) / delta) % 6;
        else if (cmax === g)
            h = (b - r) / delta + 2;
        else
            h = (r - g) / delta + 4;

        h = Math.round(h * 60);

        if (h < 0)
            h += 360;

        l = (cmax + cmin) / 2;
        s = delta === 0 ? 0 : delta / (1 - Math.abs(2 * l - 1));

        return { h, s, l };
    }

    /**
     * Converts HSL object {h, s, l} to Hex string #RRGGBB
     */
    static hslToHex(h, s, l) {
        let c = (1 - Math.abs(2 * l - 1)) * s,
            x = c * (1 - Math.abs(((h / 60) % 2) - 1)),
            m = l - c / 2,
            r = 0,
            g = 0,
            b = 0;

        if (0 <= h && h < 60) {
            r = c; g = x; b = 0;
        } else if (60 <= h && h < 120) {
            r = x; g = c; b = 0;
        } else if (120 <= h && h < 180) {
            r = 0; g = c; b = x;
        } else if (180 <= h && h < 240) {
            r = 0; g = x; b = c;
        } else if (240 <= h && h < 300) {
            r = x; g = 0; b = c;
        } else if (300 <= h && h < 360) {
            r = c; g = 0; b = x;
        }
        r = Math.round((r + m) * 255).toString(16);
        g = Math.round((g + m) * 255).toString(16);
        b = Math.round((b + m) * 255).toString(16);

        if (r.length === 1)
            r = "0" + r;
        if (g.length === 1)
            g = "0" + g;
        if (b.length === 1)
            b = "0" + b;

        return "#" + r + g + b;
    }

    /**
     * Blends a foreground color with transparency over a background color.
     * Returns Hex string.
     * @param {string} fgHex Foreground color (Hex)
     * @param {number} fgOpacity Foreground opacity 0-1
     * @param {string} bgHex Background color (Hex) - assumed opaque
     */
    static alphaBlend(fgHex, fgOpacity, bgHex) {
        const fg = ColorUtils.parseToRgb(fgHex);
        const bg = ColorUtils.parseToRgb(bgHex);

        if (!fg || !bg) return bgHex || '#000000'; // Fallback

        // Blend: result = fg * alpha + bg * (1 - alpha)
        let r = Math.round(fg.r * fgOpacity + bg.r * (1 - fgOpacity));
        let g = Math.round(fg.g * fgOpacity + bg.g * (1 - fgOpacity));
        let b = Math.round(fg.b * fgOpacity + bg.b * (1 - fgOpacity));

        const toHex = (n) => n.toString(16).padStart(2, '0');
        return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
    }
    
    /**
     * Determines if a color is "light" (for choosing black/white text).
     * @param {string} hex 
     * @returns boolean
     */
    static isLight(color) {
         const rgb = ColorUtils.parseToRgb(color);
         if (!rgb) return true; // Fallback to safe "light" assumption
         
         const { r, g, b } = rgb;

         // Perceived brightness formula
         // (R * 299 + G * 587 + B * 114) / 1000
         const brightness = (r * 299 + g * 587 + b * 114) / 1000;
         
         return brightness > 125;
    }
}
