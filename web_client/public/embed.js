/* Festapp embed protocol 1. Standalone, deliberately independent of the app. */
(() => {
    if (window.__festappEmbedV1) return;
    window.__festappEmbedV1 = true;
    const namespace = 'festapp-embed';
    function isValidEmail(value) {
        if (typeof value !== 'string' || value.length > 254 || /\s/.test(value)) return false;
        const parts = value.split('@');
        if (parts.length !== 2) return false;
        const [local, host] = parts;
        const domain = host.split('.');
        return local.length > 0 && local.length <= 64 &&
            /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+$/.test(local) &&
            !local.startsWith('.') && !local.endsWith('.') && !local.includes('..') &&
            domain.length >= 2 && domain.every(label =>
                /^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(label)) &&
            !/^[0-9]+$/.test(domain.at(-1));
    }

    function normalizeE164Phone(value, {defaultPrefix = null} = {}) {
        if (typeof value !== 'string') return null;
        const trimmed = value.replace(/^[\s\u200B-\u200D\u2060\u180E]+|[\s\u200B-\u200D\u2060\u180E]+$/gu, '');
        if (!trimmed || trimmed.length > 100 || !/^[+\d\s().-]+$/.test(trimmed) || trimmed.includes('(0)')) return null;
        let phone = trimmed.replace(/[\s().-]/g, '').replace(/^00/, '+');
        if (!phone.startsWith('+')) {
            if (/^\d{9}$/.test(phone) && ['+420', '+421'].includes(defaultPrefix)) phone = defaultPrefix + phone;
            else if (/^(420|421)\d{9}$/.test(phone)) phone = '+' + phone;
            else if (/^\+[1-9]\d{0,2}$/.test(defaultPrefix || '')) {
                phone = phone.startsWith(defaultPrefix.slice(1)) && phone.length >= defaultPrefix.length + 6
                    ? '+' + phone : defaultPrefix + phone;
            }
            else return null;
        }
        return /^\+[1-9]\d{7,14}$/.test(phone) ? phone : null;
    }

    const ecommerceEvents = new Set(['view_item', 'add_to_cart', 'remove_from_cart', 'begin_checkout', 'add_payment_info', 'purchase']);
    const currencies = value => typeof value === 'string' && /^[A-Z]{3}$/.test(value);
    const productId = value => typeof value === 'string' && /^product_[1-9]\d{0,15}$/.test(value);
    const orderSymbol = value => typeof value === 'string' && /^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$/.test(value);
    const pageTypes = ['product', 'checkout', 'confirmation'];

    const textValue = (value, limit = 256) => typeof value === 'string' && !/[\u0000-\u001f]/.test(value) ? value.trim().slice(0, limit) : '';
    const money = value => Number.isFinite(value) && value >= 0 && value <= 999999999 ? Math.round((value + Number.EPSILON) * 100) / 100 : null;

    function normalizeUserData(input, {phonePrefix = null} = {}) {
        if (!input || typeof input !== 'object') return null;
        const result = {};
        const email = typeof input.email === 'string' ? input.email.replace(/^[\s\u200B-\u200D\u2060\u180E]+|[\s\u200B-\u200D\u2060\u180E]+$/gu, '').toLowerCase() : '';
        if (isValidEmail(email)) result.email = email;
        const phone = normalizeE164Phone(input.phone_number, {defaultPrefix: phonePrefix});
        if (phone) result.phone_number = phone;
        const address = {};
        for (const key of ['first_name', 'last_name']) {
            const name = textValue(input.address?.[key], 128).normalize('NFC').toLowerCase()
                .replace(/^(?:(?:prof|doc|ing|arch|mgr|bc|mudr|judr|rndr|phdr|pharmdr|mvdr|thdr|paeddr|dr|mr|mrs|ms)\.?\s+)+/u, '')
                .replace(/(?:[,\s]+(?:ph\.?d\.?|csc\.?|dis\.?))+$/u, '').trim().replace(/\s+/g, ' ');
            if (name) address[key] = name;
        }
        const postal = textValue(input.address?.postal_code, 24);
        if (postal && /^[\p{L}\p{N} -]+$/u.test(postal)) address.postal_code = postal;
        const country = textValue(input.address?.country, 256).toUpperCase();
        if (/^[A-Z]{2}$/.test(country)) address.country = country;
        if (Object.keys(address).length) result.address = address;
        return Object.keys(result).length ? result : null;
    }

    // Rebuild at both transport boundaries. Never spread form, order or message data.
    function analyticsPayload(input, {allowUserData = false} = {}) {
        if (!input || typeof input !== 'object') return null;
        const withUserData = payload => {
            const userData = allowUserData ? normalizeUserData(input.user_data) : null;
            if (userData) payload.user_data = userData;
            return payload;
        };
        if (!input.event) {
            if (!pageTypes.includes(input.page_type)) return null;
            const result = {page_type: input.page_type, user_type: 'b2c'};
            if (typeof input.language === 'string' && /^[a-z]{2}$/.test(input.language)) result.language = input.language;
            return result;
        }
        if (input.event === 'page_view' || input.event === 'form_submit_error') return {event: input.event};
        if (input.event === 'generate_lead') {
            if (!['free_registration', 'waitlist'].includes(input.lead_source) || !currencies(input.currency) || input.value !== 0) return null;
            return withUserData({event: 'generate_lead', currency: input.currency, value: 0, lead_source: input.lead_source});
        }
        const source = input.ecommerce;
        if (!ecommerceEvents.has(input.event) || !source || !currencies(source.currency) ||
            !Array.isArray(source.items) || !source.items.length || source.items.length > 200) return null;
        const items = [];
        for (const item of source.items) {
            const price = money(item?.price);
            const name = textValue(item?.item_name);
            if (!item || !productId(item.item_id) || !name || price === null || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 9999) return null;
            items.push({item_id: item.item_id, item_name: name, price, quantity: item.quantity});
        }
        // Integer cents keep values such as 0.10 × 3 stable across both boundaries.
        const ecommerce = {currency: source.currency, items, value: items.reduce((sum, item) => sum + Math.round(item.price * 100) * item.quantity, 0) / 100};
        if (input.event === 'add_payment_info' || input.event === 'purchase') {
            if (!['bank_transfer', 'card', 'free'].includes(source.payment_type)) return null;
            ecommerce.payment_type = source.payment_type;
        }
        if (input.event === 'purchase') {
            if (!orderSymbol(source.transaction_id)) return null;
            ecommerce.transaction_id = source.transaction_id;
        }
        const result = {event: input.event, ecommerce};
        return input.event === 'purchase' ? withUserData(result) : result;
    }
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
    const isTransparent = color => {
        if (!color || color === 'transparent') return true;
        // CSS can serialize transparent white (or any other RGB value), not just
        // rgba(0, 0, 0, 0). Modern color functions separate alpha with a slash.
        const alpha = color.match(/\/\s*([\d.]+%?)\s*\)$/) ||
            color.match(/^(?:rgba|hsla)\([^)]*,\s*([\d.]+%?)\s*\)$/);
        return !!alpha && parseFloat(alpha[1]) === 0;
    };
    const presentation = frame => {
        const container = frame.parentElement;
        const style = getComputedStyle(container);
        let background = 'rgb(255, 255, 255)';
        for (let node = container; node; node = node.parentElement) {
            const color = getComputedStyle(node).backgroundColor;
            if (!isTransparent(color)) { background = color; break; }
        }
        // Checkout projections are output, never a source of website appearance.
        const selector = ':is(button, .wp-element-button, .wp-block-button__link):not([data-festapp-embed-price] *)';
        const button = container.querySelector(selector) || document.querySelector(selector);
        const candidate = button && getComputedStyle(button);
        // Navigation/outline buttons often have no fill; they cannot supply a
        // usable primary/background pair for checkout buttons.
        const buttonStyle = candidate && candidate.opacity !== '0' && candidate.display !== 'none' &&
            candidate.visibility !== 'hidden' && !isTransparent(candidate.backgroundColor) &&
            !isTransparent(candidate.color) ? candidate : null;
        const primary = style.getPropertyValue('--wp--preset--color--primary').trim() || buttonStyle?.backgroundColor || style.color;
        return {fontFamily: style.fontFamily, text: style.color, background, primary,
            buttonText: buttonStyle?.color || background, fonts: fontFaces(style.fontFamily)};
    };
    const send = (frame, record, type, includeTheme = true) => {
        const viewportOffset = Math.max(0, Math.min(20000,
            (window.visualViewport?.offsetTop || 0) - frame.getBoundingClientRect().top));
        const data = {namespace, protocol: 1, type, instance: record.instance,
            viewportHeight: viewportHeight(), viewportOffset, scrollAlignment: true, autoHeight: frame.dataset.festappHeight !== 'fixed',
            dataLayer: frame.hasAttribute('data-festapp-datalayer'),
            dataLayerUserData: frame.hasAttribute('data-festapp-datalayer') && frame.hasAttribute('data-festapp-datalayer-user-data'),
            hostPrice: frame.parentElement?.hasAttribute('data-festapp-embed-host') === true};
        // An explicit choice belongs to this iframe; absent markup uses the
        // saved fallback for already-installed CMS integrations.
        if (frame.dataset.festappStyle === 'inherit') data.inheritStyle = true;
        else if (frame.dataset.festappStyle === 'default') data.inheritStyle = false;
        if (includeTheme) {
            const theme = presentation(frame);
            record.theme = JSON.stringify(theme);
            data.theme = theme;
        }
        frame.contentWindow?.postMessage(data, record.origin);
    };
    const refreshThemes = () => frames.forEach((record, frame) => {
        if (JSON.stringify(presentation(frame)) !== record.theme) send(frame, record, 'theme');
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
            if (data.type === 'analytics') {
                if (frame.hasAttribute('data-festapp-datalayer')) {
                    const payload = analyticsPayload(data.payload, {allowUserData: frame.hasAttribute('data-festapp-datalayer-user-data')});
                    if (!payload) return;
                    window.dataLayer = window.dataLayer || [];
                    if (payload.ecommerce || payload.event === 'generate_lead') window.dataLayer.push({ecommerce: null, user_data: null});
                    window.dataLayer.push(payload);
                    if (['purchase', 'generate_lead'].includes(payload.event)) window.dataLayer.push({user_data: null});
                }
                return;
            }
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
            if (event?.type === 'resize' || !record.priceLayer) send(frame, record, 'viewport', false);
        });
    };
    window.addEventListener('scroll', updateVisibleViewport, {passive: true, capture: true});
    window.visualViewport?.addEventListener('scroll', updateVisibleViewport, {passive: true});
    window.visualViewport?.addEventListener('resize', updateVisibleViewport, {passive: true});
    let themeRaf;
    new MutationObserver((mutations = []) => {
        scan();
        for (const mutation of mutations) {
            if (['data-festapp-datalayer', 'data-festapp-datalayer-user-data'].includes(mutation.attributeName) && frames.has(mutation.target)) {
                send(mutation.target, frames.get(mutation.target), 'init', false);
            }
        }
        if (!themeRaf) themeRaf = requestAnimationFrame(() => { themeRaf = null; refreshThemes(); });
    }).observe(document.documentElement, { childList: true, subtree: true, attributes: true,
        attributeFilter: ['class', 'style', 'src', 'data-festapp-datalayer', 'data-festapp-datalayer-user-data'] });
    document.fonts?.ready.then(refreshThemes);
    scan();
})();
