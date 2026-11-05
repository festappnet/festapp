/* Festapp embed protocol 1. Standalone, deliberately independent of the app. */
(() => {
    if (window.__festappEmbedV1) return;
    window.__festappEmbedV1 = true;
    const namespace = 'festapp-embed';
    const frames = new Map();
    const viewportHeight = () => Math.max(240, Math.min(4000, window.innerHeight));
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
                            externalSheets.set(sheet.href, parsed); refreshThemes();
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
    // Computed sRGB colors and WordPress hex tokens. Unsupported color spaces
    // fall back to a known pair instead of guessing their contrast.
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
        if (!match) return null;
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
            if (!color) continue;
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
            buttonFill = over(fill, backgroundAt(button.parentElement));
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
        return {fontFamily: style.fontFamily, text: style.color, background: cssColor(background), primary: cssColor(primary),
            buttonText: cssColor(foreground), fonts: fontFaces(style.fontFamily)};
    };
    // null omits presentation for frequent scroll-only viewport messages.
    const send = (frame, record, type, theme = presentation(frame)) => {
        const viewportOffset = Math.max(0, Math.min(20000,
            (window.visualViewport?.offsetTop || 0) - frame.getBoundingClientRect().top));
        const data = {namespace, protocol: 1, type, instance: record.instance,
            viewportHeight: viewportHeight(), viewportOffset, scrollAlignment: true, autoHeight: frame.dataset.festappHeight !== 'fixed',
            hostPrice: frame.parentElement?.hasAttribute('data-festapp-embed-host') === true};
        if (theme !== null) {
            record.theme = JSON.stringify(theme);
            data.theme = theme;
        }
        frame.contentWindow?.postMessage(data, record.origin);
    };
    const refreshThemes = () => frames.forEach((record, frame) => {
        const theme = presentation(frame);
        if (JSON.stringify(theme) !== record.theme) send(frame, record, 'theme', theme);
    });
    // The child owns prices and formatting. The host projects only that view,
    // so native sticky positioning never waits for cross-frame scroll messages.
    const projectPrice = (frame, record, data) => {
        const model = data.price;
        const host = frame.parentElement;
        if (!host?.hasAttribute('data-festapp-embed-host')) return;
        if (model !== null && (!model || !Number.isInteger(model.count) || model.count < 1 || model.count > 9999 ||
            typeof model.total !== 'string' || model.total.length > 160 || !Array.isArray(model.lines) ||
            model.lines.length > 16 || !model.lines.every(line => typeof line === 'string' && line.length <= 512))) return;
        if (!record.priceLayer) {
            if (!getComputedStyle(host).position || getComputedStyle(host).position === 'static') host.style.position = 'relative';
            const layer = document.createElement('div');
            layer.dataset.festappEmbedPrice = '';
            layer.style.cssText = 'position:absolute;top:16px;right:16px;bottom:16px;left:16px;pointer-events:none;z-index:30';
            const card = document.createElement('button'); card.type = 'button';
            card.style.cssText = 'position:sticky;top:16px;display:block;width:max-content;max-width:100%;margin-left:auto;pointer-events:auto;border:0;text-align:right;cursor:pointer;box-sizing:border-box';
            card.onclick = () => frame.contentWindow?.postMessage({namespace, protocol:1, type:'price-activate', instance:record.instance},record.origin);
            layer.append(card); host.append(layer); record.priceLayer = layer; record.priceCard = card;
        }
        record.priceLayer.hidden = model === null || data.visible !== true;
        const signature = JSON.stringify({model,appearance:data.appearance});
        if (model && signature !== record.priceSignature) {
            record.priceSignature = signature;
            const card = record.priceCard; card.replaceChildren();
            const styles = ['background-color','color','font-family','font-size','font-weight','padding','border-radius','box-shadow'];
            for (const property of styles) {
                const value = data.appearance?.[property];
                if (typeof value === 'string' && value.length <= 512) card.style.setProperty(property,value);
            }
            const row = document.createElement('span'); row.style.cssText='display:flex;align-items:center;gap:8px';
            const count = document.createElement('span');count.textContent = `${model.count}x`;
            const icon = document.createElementNS('http://www.w3.org/2000/svg','svg');
            icon.setAttribute('viewBox','0 0 24 24');icon.setAttribute('width','24');icon.setAttribute('height','24');icon.setAttribute('aria-hidden','true');
            const path = document.createElementNS('http://www.w3.org/2000/svg','path');path.setAttribute('fill','currentColor');
            path.setAttribute('d','M20 12c0-1.1.9-2 2-2V6c0-1.1-.9-2-2-2H4C2.9 4 2 4.9 2 6v4c1.1 0 2 .9 2 2s-.9 2-2 2v4c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2v-4c-1.1 0-2-.9-2-2zm-4.42 4.8L12 14.5l-3.58 2.3 1.1-4.1-3.2-2.62 4.2-.25L12 6l1.48 3.83 4.2.25-3.2 2.62 1.1 4.1z');icon.append(path);
            const total = document.createElement('span');total.textContent=model.total;
            row.append(count,icon,total);card.append(row);
            for (const text of model.lines) { const line=document.createElement('div');line.textContent=text;card.append(line); }
        }
        frame.contentWindow?.postMessage({namespace,protocol:1,type:'price-ready',instance:record.instance,visible:!record.priceLayer.hidden},record.origin);
    };
    const scan = () => {
        for (const [frame, record] of frames) {
            if (!frame.isConnected) { frame.removeEventListener('load', record.load); record.priceLayer?.remove(); frames.delete(frame); }
        }
        document.querySelectorAll('iframe[data-festapp-embed]').forEach(frame => {
            if (frames.has(frame)) {
                const record = frames.get(frame);
                try { if (new URL(frame.src, document.baseURI).origin === record.origin) return; } catch { return; }
                frame.removeEventListener('load', record.load); record.priceLayer?.remove(); frames.delete(frame);
            }
            let url;
            try { url = new URL(frame.getAttribute('src'), document.baseURI); } catch { return; }
            if (!/^https?:$/.test(url.protocol) || url.origin === 'null') return;
            const record = { origin: url.origin, instance: `f_${crypto.randomUUID()}` };
            record.load = () => send(frame, record, 'init');
            frames.set(frame, record);
            frame.addEventListener('load', record.load);
            send(frame, record, 'init');
        });
    };
    window.addEventListener('message', event => {
        const data = event.data;
        if (data?.namespace !== namespace || data.protocol !== 1) return;
        for (const [frame, record] of frames) {
            if (event.source !== frame.contentWindow || event.origin !== record.origin) continue;
            // Changing src invalidates the original declaration until re-discovered.
            if (new URL(frame.src, document.baseURI).origin !== record.origin) return;
            if (data.type === 'ready') { send(frame, record, 'init'); return; }
            if (data.instance !== record.instance) return;
            if (data.type === 'price') { projectPrice(frame,record,data); return; }
            if (['scroll-save', 'scroll-restore', 'scroll-discard'].includes(data.type) &&
                typeof data.snapshot === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(data.snapshot)) {
                record.scrollSnapshots ??= new Map();
                if(data.type === 'scroll-save' && record.scrollSnapshots.size < 16) {
                    record.scrollSnapshots.set(data.snapshot,{left:window.scrollX,top:window.scrollY});
                } else if(data.type === 'scroll-restore') {
                    const position=record.scrollSnapshots.get(data.snapshot);
                    if(position) {
                        record.scrollSnapshots.delete(data.snapshot);
                        window.scrollTo({...position,behavior:'instant'});
                    }
                } else if (data.type === 'scroll-discard') {
                    record.scrollSnapshots.delete(data.snapshot);
                }
                return;
            }
            if (data.type === 'resize' && frame.dataset.festappHeight !== 'fixed' && Number.isFinite(data.height) && data.height >= 240 && data.height <= 20000) {
                const height = Math.ceil(data.height);
                if (frame.style.height !== `${height}px`) frame.style.height = `${height}px`;
            } else if (data.type === 'scroll-request' && Number.isFinite(data.y) && data.y >= 0 &&
                (data.block === undefined || ['start', 'end', 'nearest'].includes(data.block)) &&
                (data.height === undefined || (Number.isFinite(data.height) && data.height >= 0 && data.height <= 20000)) &&
                data.y <= (data.block === 'end' ? 20000 : Math.min(20000, frame.clientHeight))) {
                const y = Math.min(data.y, frame.clientHeight);
                const viewport = window.visualViewport?.height || window.innerHeight;
                const offset = window.visualViewport?.offsetTop || 0;
                const targetTop = frame.getBoundingClientRect().top + y;
                let top = window.scrollY + targetTop - offset - (data.block === 'end' ? viewport : 0);
                if (data.block === 'nearest') {
                    const height = Math.min(data.height || 0, frame.clientHeight - y);
                    const gap = 16;
                    const visibleTop = targetTop - offset;
                    if (visibleTop >= gap && (visibleTop + height <= viewport - gap || height > viewport - 2 * gap)) return;
                    top = visibleTop < gap || height > viewport - 2 * gap
                        ? window.scrollY + visibleTop - gap
                        : window.scrollY + visibleTop + height - viewport + gap;
                }
                top = Math.max(0, top);
                window.scrollTo({ top, behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
            }
            return;
        }
    });
    let raf;
    window.addEventListener('resize', () => {
        if (raf) return;
        raf = requestAnimationFrame(() => { raf = null; frames.forEach((record, frame) => send(frame, record, 'viewport')); });
    });
    // The page can scroll while a tall iframe itself remains at scrollY=0.
    // Report its visible top without re-reading font styles on every scroll.
    const updateVisibleViewport = event => {
        // Scroll is already synchronized by the browser. Another RAF adds a
        // full frame of lag before the cross-frame message can be painted.
        frames.forEach((record, frame) => {
            if (event?.type === 'resize' || !record.priceLayer) send(frame, record, 'viewport', null);
        });
    };
    window.addEventListener('scroll', updateVisibleViewport, {passive: true, capture: true});
    window.visualViewport?.addEventListener('scroll', updateVisibleViewport, {passive: true});
    window.visualViewport?.addEventListener('resize', updateVisibleViewport, {passive: true});
    let themeRaf;
    new MutationObserver(() => {
        scan();
        if (!themeRaf) themeRaf = requestAnimationFrame(() => { themeRaf = null; refreshThemes(); });
    }).observe(document.documentElement, { childList: true, subtree: true, attributes: true,
        attributeFilter: ['class', 'style', 'src'] });
    document.fonts?.ready.then(refreshThemes);
    scan();
})();
