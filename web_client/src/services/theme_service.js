import { browserStorage } from './browser_storage.js';
import { AppConfig } from '../app_config.js';
import { ColorUtils } from '../utils/color_utils.js';

// Read the previous admin preference only while migrating a browser with no
// shared choice yet. New selections always use the canonical `theme` key.
function savedThemeMode() {
    const saved = browserStorage.getItem(AppConfig.Keys.theme);
    if (['light', 'dark', 'auto'].includes(saved)) return saved;
    for (const key of ['adaptive_theme_preferences', 'flutter.adaptive_theme_preferences']) {
        try {
            let legacy = JSON.parse(browserStorage.getItem(key));
            if (typeof legacy === 'string') legacy = JSON.parse(legacy);
            const mode = {0:'light', 1:'dark', 2:'auto'}[legacy?.theme_mode];
            if (mode) { browserStorage.setItem(AppConfig.Keys.theme, mode); return mode; }
        } catch { /* Malformed legacy data must not prevent opening a page. */ }
    }
    return null;
}

export class ThemeService {
    static isDark = false;

    static currentMode = 'auto'; // 'auto', 'light', 'dark'

    static init() {
        // Load saved preference
        const saved = savedThemeMode();
        
        if (saved && (saved === 'light' || saved === 'dark')) {
            ThemeService.currentMode = saved;
            ThemeService.isDark = (saved === 'dark');
        } else {
            ThemeService.currentMode = 'auto';
            ThemeService.isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        }

        // Setup Listener for System Changes (only active if auto, but we can always listen and ignore if manual)
        // Best practice: Always listen, but only apply if mode is auto.
        if (!ThemeService._mediaQueryListener) {
            const mq = window.matchMedia('(prefers-color-scheme: dark)');
            ThemeService._mediaQueryListener = (e) => {
                if (ThemeService._lastFormModel) {
                    ThemeService.applyThemeFromModel(ThemeService._lastFormModel);
                } else if (ThemeService.currentMode === 'auto') {
                    ThemeService.isDark = e.matches;
                    ThemeService.apply();
                }
            };
            mq.addEventListener('change', ThemeService._mediaQueryListener);
            // Other public pages share the same preference. Update an already
            // open homepage/help tab without persisting the event back or
            // disturbing its session or current form.
            const syncPreference = () => {
                ThemeService.init();
                if (ThemeService._lastFormModel) {
                    ThemeService.applyThemeFromModel(ThemeService._lastFormModel);
                }
            };
            window.addEventListener('storage', event => {
                if (event.key === AppConfig.Keys.theme || event.key === null) syncPreference();
            });
            window.addEventListener('pageshow', event => {
                if (event.persisted) syncPreference();
            });
            window.addEventListener('focus', syncPreference);
        }

        ThemeService.apply();
    }

    static clearFormTheme() {
        ThemeService._lastFormModel = null;
        document.getElementById('shared-font-error')?.remove();
        for (const [name, value, priority] of ThemeService._formStyleSnapshot || []) {
            if (value) document.body.style.setProperty(name, value, priority);
            else document.body.style.removeProperty(name);
        }
        if (ThemeService._sharedAppearance === undefined) delete document.body.dataset.sharedAppearance;
        else document.body.dataset.sharedAppearance = ThemeService._sharedAppearance;
        ThemeService._formStyleSnapshot = null;
        ThemeService.init();
    }

    static showFontError(formModel) {
        if (ThemeService._lastFormModel !== formModel || document.getElementById('shared-font-error')) return;
        const message = document.createElement('div');
        message.id = 'shared-font-error'; message.setAttribute('role', 'alert');
        const retry = document.createElement('button');
        retry.textContent = 'Písmo se nepodařilo načíst. Zkusit znovu';
        retry.onclick = () => { message.remove(); ThemeService.applyThemeFromModel(formModel); };
        message.appendChild(retry); document.body.prepend(message);
    }

    static toggle() {
        // Toggle logic rotates: Auto -> Dark -> Light -> Auto? Or just Light/Dark?
        // User asked for explicit switch. 'toggle' might be legacy. 
        // Let's make it simple: if auto/light -> dark. if dark -> light.
        // But better to use setMode directly from UI.
        const newMode = ThemeService.isDark ? 'light' : 'dark';
        ThemeService.setMode(newMode);
    }

    static setMode(mode) {
        ThemeService.currentMode = mode;
        
        if (mode === 'auto') {
            browserStorage.setItem(AppConfig.Keys.theme, 'auto');
            ThemeService.isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        } else {
            ThemeService.isDark = (mode === 'dark');
            browserStorage.setItem(AppConfig.Keys.theme, mode); // 'light' or 'dark'
        }
        
        ThemeService.apply();

        // Critical: If we have a cached form model, we MUST re-apply it because the inline styles
        // (root.style.setProperty) defined in applyThemeFromModel depend on isDark state.
        // Changing the class (apply()) is not enough for the JS-calculated dynamic colors.
        if (ThemeService._lastFormModel) {
            ThemeService.applyThemeFromModel(ThemeService._lastFormModel);
        } else {
            // If no model, we should probably clear the inline styles so that CSS classes take over?
            // For now, let's assume we want to clear key variable overrides if we switch to manual mode without a model.
            // But realistically, _lastFormModel is populated once app loads. 
        }
    }

    static get warningColor() {
        return '#ed6c02';
    }

    static apply() {
        if (ThemeService._lastFormModel) {
            const mode = ThemeService._lastFormModel.themeMode;
            ThemeService.isDark = mode === 'dark' ||
                (mode !== 'light' && !!window.matchMedia?.('(prefers-color-scheme: dark)').matches);
        }
        // Native inputs, checkboxes and select popups must follow the selected
        // application theme, including a manual override of the OS preference.
        document.documentElement.style.colorScheme = ThemeService.isDark ? 'dark' : 'light';
        document.body.style.colorScheme = document.documentElement.style.colorScheme;
        if (ThemeService.isDark) {
            document.body.classList.add('dark-mode');
        } else {
            document.body.classList.remove('dark-mode');
        }
    }


    /**
     * Calculates and applies the theme based on the form model.
     * Replaces the old FormPage.applyTheme logic.
     */
    static applyThemeFromModel(formModel) {
        if (ThemeService._lastFormModel !== formModel) document.getElementById('shared-font-error')?.remove();
        const root = document.body;
        if (!ThemeService._formStyleSnapshot) {
            const properties = ['--background-color', '--btn-secondary-text-color', '--btn-text-color', '--card-bg', '--card-bg-derived', '--countdown-bg', '--countdown-border', '--fab-color', '--fab-text-color', '--font-family-base', '--font-scale', '--form-background', '--input-bg', '--input-border', '--input-font-family', '--input-text', '--label-text-color', '--link-color', '--primary-color', '--secondary-color', '--text-color', '--unselected-widget-border', '--unselected-widget-fill', 'background', 'background-color'];
            ThemeService._formStyleSnapshot = properties.map(name =>
                [name, root.style.getPropertyValue(name), root.style.getPropertyPriority(name)]);
            ThemeService._sharedAppearance = root.dataset.sharedAppearance;
        }
        ThemeService._lastFormModel = formModel;
        ThemeService.apply();

        // Fonts
        let familyName = 'inherit';
        if (formModel.fontFamily) {
            const fontLink = document.createElement('link');
            familyName = formModel.fontFamily.trim();
            fontLink.href = `https://fonts.googleapis.com/css?family=${familyName.replace(/ /g, '+')}:400,500,700&display=swap`;
            fontLink.rel = 'stylesheet';
            if (formModel.backgroundMode) {
                fontLink.onload = async () => {
                    try {
                        if (document.fonts && (await document.fonts.load(`16px "${familyName}"`)).length === 0) throw new Error('font unavailable');
                        document.getElementById('shared-font-error')?.remove();
                    } catch { ThemeService.showFontError(formModel); }
                };
                fontLink.onerror = () => ThemeService.showFontError(formModel);
            }
            document.head.appendChild(fontLink);
            root.style.setProperty('--font-family-base', `"${familyName}", sans-serif`);
            root.style.setProperty('--input-font-family', `"${familyName}", sans-serif`);
            // Reset scale for custom fonts (usually larger inherently)
            root.style.setProperty('--font-scale', '1');
        } else {
             root.style.setProperty('--font-family-base', 'inherit');
             root.style.setProperty('--input-font-family', 'inherit');
             // Revert to default Futura scale (1.2 defined in CSS)
             root.style.removeProperty('--font-scale');
        }

        // --- Smart Color Logic (Strict Flutter Port) ---
        const defaultPrimary = '#4465A6'; 
        // Re-detect isDark because it might have changed or we rely on the service state
        // The service state `ThemeService.isDark` is the source of truth.
        const isDark = ThemeService.isDark;

        // Process Colors
        let primaryHex = formModel.primaryColor || defaultPrimary;
        if (!primaryHex.startsWith('#')) primaryHex = '#' + primaryHex;
        
        // Ensure 6-digit hex for HSL conversions
        let pureHex = primaryHex;
        if (primaryHex.length > 7) {
            pureHex = primaryHex.substring(0, 7);
        }
        
        // Start with the pure hex
        let finalPrimaryHex = pureHex;
        
        // Flutter Logic: Boost Lightness/Saturation for Dark Mode
        if (isDark) {
            let hsl = ColorUtils.hexToHsl(pureHex); // {h, s, l}
            let changed = false;

            // "Boost lightness more aggressively for dark mode to ensure visibility"
            if (hsl.l < 0.75) {
                hsl.l = 0.75;
                changed = true;
                
                // "Also optionally boost saturation if it's very low"
                if (hsl.s < 0.3) {
                    hsl.s = 0.4;
                }
            }
            if (changed) {
                finalPrimaryHex = ColorUtils.hslToHex(hsl.h, hsl.s, hsl.l);
            }
        }
        
        let linkColorHex = finalPrimaryHex;
        if (!isDark) {
             // Light Mode: Ensure link color isn't too bright
             let hsl = ColorUtils.hexToHsl(finalPrimaryHex);
             if (hsl.l > 0.4) {
                 linkColorHex = ColorUtils.hslToHex(hsl.h, hsl.s, 0.4); 
             }
        }
        
        // Helper: Ensure we have secondary
        let secondaryHex = formModel.secondaryColor;
        if (!secondaryHex) {
             const pHsl = ColorUtils.hexToHsl(finalPrimaryHex);
             const targetL = isDark ? 0.85 : 0.9;
             secondaryHex = ColorUtils.hslToHex(pHsl.h, pHsl.s, targetL);
        } else {
             if (!secondaryHex.startsWith('#')) secondaryHex = '#' + secondaryHex;
        }

        // Apply Colors
        root.style.setProperty('--primary-color', finalPrimaryHex);
        root.style.setProperty('--secondary-color', secondaryHex);
        root.style.setProperty('--link-color', linkColorHex);

        // --- Background & Surface Logic (Grey Palette) ---
        const flutterGrey900 = '#212121';
        const flutterGrey800 = '#424242'; 
        const flutterGrey500 = '#9E9E9E'; 
        const flutterGrey400 = '#BDBDBD';
        const flutterGrey600 = '#757575';

        // Scaffold Background
        const baseBg = isDark ? flutterGrey900 : '#ffffff'; 
        const tintOpacity = isDark ? 0.05 : 0.12; 
        
        const blendedBg = ColorUtils.alphaBlend(finalPrimaryHex, tintOpacity, baseBg);
        
        root.style.setProperty('--background-color', blendedBg);
        document.body.style.backgroundColor = blendedBg;

        const explicitBackground = formModel.backgroundMode;
        // Saved colors are accents, not full-strength page paint. Keep the
        // original form tint for both solid and two-color backgrounds.
        const secondaryBg = ColorUtils.alphaBlend(secondaryHex, tintOpacity, baseBg);
        const background = !formModel.primaryColor ? null
            : explicitBackground === 'gradient'
                ? `linear-gradient(135deg, ${blendedBg}, ${formModel.secondaryColor ? secondaryBg : blendedBg})`
                : explicitBackground === 'solid' ? blendedBg : null;
        if (background) {
            root.dataset.sharedAppearance = 'true';
            root.style.setProperty('--form-background', background);
            root.style.background = background;
        } else { delete root.dataset.sharedAppearance; root.style.removeProperty('--form-background'); root.style.background = blendedBg; }

        // Content Colors
        const onPrimary = ThemeService.getBestTextColor(finalPrimaryHex);
        
        root.style.setProperty('--fab-color', finalPrimaryHex);
        root.style.setProperty('--fab-text-color', onPrimary);
        root.style.setProperty('--btn-text-color', onPrimary);

        // Secondary Text Color
        const onSecondary = ThemeService.getBestTextColor(secondaryHex);
        root.style.setProperty('--btn-secondary-text-color', onSecondary);
        
        if (isDark) {
            root.style.setProperty('--text-color', '#ffffff');

            // Card & Input BG
            const surfaceColor = ColorUtils.alphaBlend(finalPrimaryHex, 0.08, flutterGrey800);

            root.style.setProperty('--card-bg', surfaceColor);
            root.style.setProperty('--card-bg-derived', surfaceColor);
            root.style.setProperty('--input-bg', surfaceColor);

            // Borders & Text
            root.style.setProperty('--input-border', flutterGrey500); 
            root.style.setProperty('--input-text', '#ffffff');
            
            // Unselected Widget
            root.style.setProperty('--unselected-widget-fill', flutterGrey400);
            root.style.setProperty('--unselected-widget-border', flutterGrey500);
            root.style.setProperty('--label-text-color', flutterGrey400);

        } else {
            // Light Mode
            root.style.setProperty('--text-color', '#000000');
            
            root.style.setProperty('--card-bg', '#ffffff');
            root.style.setProperty('--card-bg-derived', '#ffffff');
            root.style.setProperty('--input-bg', '#ffffff');
            
            root.style.setProperty('--input-border', '#bdbdbd');
            root.style.setProperty('--input-text', '#000000');
            
            root.style.setProperty('--unselected-widget-fill', flutterGrey600);
            root.style.setProperty('--unselected-widget-border', flutterGrey600);
            root.style.setProperty('--label-text-color', '#616161');
        }

        // --- Countdown Colors ---
        const cdTintOpacity = isDark ? 0.05 : 0.03;
        const cdBaseBg = isDark ? flutterGrey900 : '#ffffff';
        const countdownBg = ColorUtils.alphaBlend(finalPrimaryHex, cdTintOpacity, cdBaseBg);
        
        let countdownBorder = finalPrimaryHex;
        if (countdownBorder.length === 7) {
             countdownBorder += '4D'; // 0.3 opacity
        }

        root.style.setProperty('--countdown-bg', countdownBg);
        root.style.setProperty('--countdown-border', countdownBorder);
    }

    /**
     * Returns optimal text color (black/white) for a given background hex.
     */
    static getBestTextColor(bgHex) {
        if (!bgHex) return '#ffffff';
        const isLight = ColorUtils.isLight(bgHex);
        return isLight ? '#000000' : '#ffffff';
    }
}
