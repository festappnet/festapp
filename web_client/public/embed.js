/* Festapp embed protocol 1. Standalone, deliberately independent of the app. */
(() => {
    if (window.__festappEmbedV1) return;
    window.__festappEmbedV1 = true;
    const namespace = 'festapp-embed';
    const frames = new Map();
    const viewportHeight = () => Math.max(240, Math.min(4000, window.innerHeight));
    const send = (frame, record, type) => frame.contentWindow?.postMessage({
        namespace, protocol: 1, type, instance: record.instance, viewportHeight: viewportHeight(),
    }, record.origin);
    const scan = () => {
        for (const [frame, record] of frames) {
            if (!frame.isConnected) { frame.removeEventListener('load', record.load); frames.delete(frame); }
        }
        document.querySelectorAll('iframe[data-festapp-embed]').forEach(frame => {
            if (frames.has(frame)) return;
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
            if (data.type === 'resize' && Number.isFinite(data.height) && data.height >= 240 && data.height <= 20000) {
                const height = Math.ceil(data.height);
                if (frame.style.height !== `${height}px`) frame.style.height = `${height}px`;
            } else if (data.type === 'scroll-request' && Number.isFinite(data.y) && data.y >= 0 && data.y <= Math.min(20000, frame.clientHeight)) {
                const top = Math.max(0, frame.getBoundingClientRect().top + window.scrollY + data.y);
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
    new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
    scan();
})();
