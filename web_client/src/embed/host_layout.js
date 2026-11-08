import {limits} from './protocol.js';
export function receiveHostLayout(frame, record, data) {
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
            if (data.type === 'resize' && frame.dataset.festappHeight !== 'fixed' && Number.isFinite(data.height) && data.height >= limits.minHeight && data.height <= limits.heightMax) {
                const height = Math.ceil(data.height);
                if (frame.style.height !== `${height}px`) frame.style.height = `${height}px`;
            } else if (data.type === 'scroll-request' && Number.isFinite(data.y) && data.y >= 0 &&
                (data.block === undefined || ['start', 'end', 'nearest'].includes(data.block)) &&
                (data.height === undefined || (Number.isFinite(data.height) && data.height >= 0 && data.height <= limits.heightMax)) &&
                data.y <= (data.block === 'end' ? limits.heightMax : Math.min(limits.heightMax, frame.clientHeight))) {
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

}

export function installHostLayout({frames, send}) {
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
}
