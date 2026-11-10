import {installHostConsentLink} from './host_consent_link.js';
import {EmbedChannel} from './channel.js';
import {limits} from './protocol.js';
import {measurementProtocol, campaignContext} from '../components/forms/form_measurement_contract.js';
import {createHostMeasurement, usesHostDataLayer} from './host_measurement.js';
import {createHostPresentation} from './host_presentation.js';
import {projectPrice} from './host_price.js';
import {receiveHostLayout, installHostLayout} from './host_layout.js';

if (!window.__festappEmbedV1) {
    window.__festappEmbedV1 = true;
    // Capture synchronously while the classic embed script is executing.
    try {
        const productOrigin = new URL(document.currentScript.src, document.baseURI).origin;
        installHostConsentLink(window, productOrigin);
    } catch { /* No trusted script origin, no consent link bridge. */ }
    const frames = new Map();
    const currentRecord = (frame, record) => {
        if (frames.get(frame) !== record || !frame.isConnected) return false;
        try { return new URL(frame.src, document.baseURI).origin === record.origin; }
        catch { return false; }
    };
    const disposeRecord = (frame, record) => {
        if (frames.get(frame) !== record) return;
        record.channel.destroy();
        frames.delete(frame);
        measurement.stopHeartbeat(record);
        record.lease = null;
        record.choice?.dispose();
        frame.removeEventListener('load', record.load);
        record.priceLayer?.remove();
    };
    const measurement = createHostMeasurement({frames, currentRecord, disposeRecord, scan:() => scan()});
    window.FestappEmbed = measurement.api;
    const viewportHeight = () => Math.max(limits.legacyMinHeight, Math.min(limits.viewportMax, window.innerHeight));
    const presentation = createHostPresentation(() => refreshThemes());
    // false omits presentation on scroll; null restores the service appearance.
    const send = (frame, record, type, theme = presentation(frame)) => {
        // The element and child must advertise compatible canvas schemes.
        // Resolve this from the host palette, never from the visitor's OS.
        if (theme !== false) frame.style.colorScheme = theme?.colorScheme || 'light dark';
        const viewportOffset = Math.max(0, Math.min(limits.heightMax,
            (window.visualViewport?.offsetTop || 0) - frame.getBoundingClientRect().top));
        const data = {
            minHeight: limits.minHeight, viewportHeight: viewportHeight(), viewportOffset, scrollAlignment: true, autoHeight: frame.dataset.festappHeight !== 'fixed',
            dataLayer: usesHostDataLayer(frame),
            measurementProtocol,
            attribution: campaignContext(Object.fromEntries(new URLSearchParams(window.location.search))),
            hostPrice: frame.parentElement?.hasAttribute('data-festapp-embed-host') === true};
        if (theme !== false) {
            record.theme = JSON.stringify(theme);
            data.theme = theme;
        }
        record.channel.send(type, data);
    };
    const refreshThemes = () => frames.forEach((record, frame) => {
        const theme = presentation(frame);
        if (JSON.stringify(theme) !== record.theme) send(frame, record, 'theme', theme);
    });
    const scan = () => {
        for (const [frame, record] of frames) {
            if (!frame.isConnected) disposeRecord(frame, record);
        }
        document.querySelectorAll('iframe[data-festapp-embed]').forEach(frame => {
            if (frames.has(frame)) {
                const record = frames.get(frame);
                try { if (new URL(frame.src, document.baseURI).origin === record.origin) return; } catch { disposeRecord(frame, record); return; }
                disposeRecord(frame, record);
            }
            let url;
            try { url = new URL(frame.getAttribute('src'), document.baseURI); } catch { return; }
            if (!/^https?:$/.test(url.protocol) || url.origin === 'null') return;
            const record = { origin: url.origin, instance: `f_${crypto.randomUUID()}` };
            record.load = () => {measurement.stopHeartbeat(record);measurement.revoke(frame,record);record.manifest=null;send(frame,record,'init');};
            // Keep the HTML height as the no-script fallback; only automatic embeds shrink.
            if (frame.dataset.festappHeight !== 'fixed') frame.style.height = `${limits.minHeight}px`;
            record.channel = new EmbedChannel({peer:() => frame.contentWindow, destination:'host',
                origin:record.origin, instance:record.instance, current:() => currentRecord(frame, record)});
            frames.set(frame, record);
            frame.addEventListener('load', record.load);
            send(frame, record, 'init');
        });
    };
    window.addEventListener('message', event => {
        for (const [frame, record] of frames) {
            const data = record.channel.receive(event);
            if (!data) continue;
            if (data.type === 'ready') { send(frame, record, 'init'); return; }
            if (measurement.receive(frame, record, data)) return;
            if (data.type === 'price') { projectPrice(frame, record, data); return; }
            receiveHostLayout(frame, record, data);
            return;
        }
    });
    installHostLayout({frames, send});
    let themeRaf;
    new MutationObserver((mutations = []) => {
        scan();
        for (const mutation of mutations) {
            if (['data-festapp-datalayer'].includes(mutation.attributeName) && frames.has(mutation.target)) {
                measurement.syncConsent(mutation.target, frames.get(mutation.target));
                send(mutation.target, frames.get(mutation.target), 'init', false);
            }
        }
        if (!themeRaf) themeRaf = requestAnimationFrame(() => { themeRaf = null; refreshThemes(); });
    }).observe(document.documentElement, { childList: true, subtree: true, attributes: true,
        attributeFilter: ['class', 'style', 'src', 'data-festapp-datalayer'] });
    document.fonts?.ready.then(refreshThemes);
    scan();
}
