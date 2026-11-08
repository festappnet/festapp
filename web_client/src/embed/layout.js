import {limits, minimumHeight} from './protocol.js';

export class EmbedLayout {
    constructor(win, channel, syncPrice) { Object.assign(this, {win, channel, syncPrice}); }
    get origin() { return this.channel.origin; }
    send(type, values) { this.channel.send(type, values); }
    configure(data) {
        this.autoHeight = data.autoHeight !== false;
        this.minHeight = minimumHeight(data.minHeight);
        this.scrollAlignment = data.scrollAlignment === true;
        this.setViewport(data.viewportHeight, data.viewportOffset);
        this.height = null;
        this.measure();
    }
    start() {
        this.destroyed = false;
        this.onResize = () => this.measure();
        this.win.addEventListener('resize', this.onResize);
        this.onScrollState = event => {
            if (event.detail.type === 'scroll-restore') this.publishHeight();
            this.send(event.detail.type, {snapshot:event.detail.snapshot});
        };
        this.win.addEventListener('festapp-embed-scroll-state', this.onScrollState);
        this.observer = new this.win.ResizeObserver(this.onResize);
        this.observer.observe(this.win.document.body);
        this.mutations = new this.win.MutationObserver(this.onResize);
        this.mutations.observe(this.win.document.body, {childList:true, subtree:true, attributes:true, attributeFilter:['class','open']});
    }
    setViewport(height, offset = 0) {
        if (this.destroyed) return;
        const style = this.win.document.documentElement.style;
        style.setProperty('--embed-viewport', `${height}px`);
        if (Number.isFinite(offset) && offset >= 0 && offset <= limits.heightMax) {
            style.setProperty('--embed-visible-top', `${offset}px`);
        }
    }
    measure() {
        if (this.destroyed) return;
        if (this.raf) return;
        const flush = () => {
            if (this.raf) this.win.cancelAnimationFrame(this.raf);
            this.win.clearTimeout(this.measureTimer);
            this.raf = null;
            this.publishHeight();
        };
        this.raf = this.win.requestAnimationFrame(flush);
        // Chromium can suspend RAF in an offscreen cross-site iframe. Keep its
        // natural height available before the visitor scrolls it into view.
        this.measureTimer = this.win.setTimeout(flush, 200);
    }
    publishHeight() {
        if (this.destroyed) return;
        this.syncPrice();
        const body = this.win.document.body;
        const dialogBottom = [...body.querySelectorAll('dialog[open], .flatpickr-calendar.open')]
            .reduce((bottom, node) => Math.max(bottom, node.getBoundingClientRect().bottom + this.win.scrollY), 0);
        const height = Math.max(this.minHeight ?? limits.legacyMinHeight, Math.ceil(body.getBoundingClientRect().height), Math.ceil(dialogBottom));
        if (height !== this.height && Number.isFinite(height)) {
            this.height = height;
            this.send('resize', { height: Math.min(limits.heightMax, height) });
        }
    }
    scrollTo(element, { block = 'start' } = {}) {
        if (this.destroyed) return;
        if (!element?.isConnected) return;
        // Resize and scroll are sent in order, so the host uses the new layout.
        this.publishHeight();
        // Legacy hosts interpret every offset as start alignment.
        if (this.origin && !this.scrollAlignment && block !== 'start') {
            const reduced = this.win.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
            element.scrollIntoView({block, behavior: reduced ? 'instant' : 'smooth'});
            return;
        }
        const rect = element.getBoundingClientRect();
        const height = Math.min(limits.heightMax, Math.max(0, rect.height || rect.bottom - rect.top));
        const y = Math.max(0, (block === 'end' ? rect.bottom : rect.top) + this.win.scrollY);
        if (this.origin && this.autoHeight !== false && this.height <= limits.heightMax) {
            // scrollIntoView also scrolls ancestor frames. Only the host may
            // move the page for a naturally sized embed.
            this.send('scroll-request', { y: Math.min(limits.heightMax, y), height, block });
            return;
        }

        const reduced = this.win.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
        if (!this.origin) {
            // Without a cooperating host, the browser is the sole scroll
            // owner and can also reveal an iframe outside the parent viewport.
            element.scrollIntoView({block, behavior: reduced ? 'instant' : 'smooth'});
            return;
        }

        // A fixed (or height-capped) iframe owns its inner scroll.
        // Window scrolling stays inside that frame and cannot move ancestors.
        const viewport = this.win.innerHeight;
        const top = rect.top + this.win.scrollY;
        let target = block === 'end' ? y - viewport : y;
        if (block === 'nearest') {
            const gap = 16;
            if (rect.top >= gap && (rect.bottom <= viewport - gap || height > viewport - 2 * gap)) target = this.win.scrollY;
            else target = rect.top < gap || height > viewport - 2 * gap
                ? top - gap : top + height - viewport + gap;
        }
        const maxScroll = Math.max(0, this.win.document.documentElement.scrollHeight - viewport, this.height - viewport);
        target = Math.max(0, Math.min(target, maxScroll));
        if (Math.abs(target - this.win.scrollY) > 1) {
            this.win.scrollTo({top: target, behavior: block === 'end' && !reduced ? 'smooth' : 'instant'});
        }
        if (this.origin) {
            this.send('scroll-request', {y: Math.max(0, top - target), height, block: 'nearest'});
        }
    }
    destroy() {
        this.destroyed = true;
        this.win.removeEventListener('resize', this.onResize);
        this.win.removeEventListener('festapp-embed-scroll-state', this.onScrollState);
        this.observer?.disconnect(); this.mutations?.disconnect();
        this.win.clearTimeout(this.measureTimer);
        if (this.raf) this.win.cancelAnimationFrame(this.raf);
        this.raf = null;
    }
}
