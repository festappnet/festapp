import { isEmbed, applyEmbedContext } from './embed_context.js';
import { EmbedTheme } from './embed_theme.js';

const namespace = 'festapp-embed';
const validId = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value);
const viewport = value => Number.isFinite(value) && value >= 240 && value <= 4000;

// The only wildcard message is a public, data-free readiness announcement.
export class EmbedBridge {
    constructor(win = window) { this.win = win; }
    start() {
        if (!isEmbed(this.win.location) || this.win.parent === this.win) return;
        applyEmbedContext();
        this.theme = new EmbedTheme(this.win);
        this.onPrice = event => { this.price = event.detail; this.syncPrice(); };
        this.win.addEventListener('festapp-embed-price',this.onPrice);
        this.onScrollState=event=>{
            if(event.detail.type === 'scroll-restore') this.publishHeight();
            this.send(event.detail.type,{snapshot:event.detail.snapshot});
        };
        this.win.addEventListener('festapp-embed-scroll-state',this.onScrollState);
        this.onMessage = event => {
            const data = event.data;
            if (event.source !== this.win.parent || !/^https?:\/\//.test(event.origin) ||
                data?.namespace !== namespace || data.protocol !== 1 || !validId(data.instance)) return;
            if (this.origin && (event.origin !== this.origin || data.instance !== this.instance)) return;
            if (data.type === 'init' && viewport(data.viewportHeight)) {
                this.origin = event.origin; this.instance = data.instance;
                this.autoHeight = data.autoHeight !== false;
                this.scrollAlignment = data.scrollAlignment === true;
                this.hostPrice = data.hostPrice === true;
                this.syncPrice();
                this.setViewport(data.viewportHeight, data.viewportOffset);
                if (data.theme !== undefined) { this.theme.apply(data.theme); this.syncPrice(); }
                this.height = null;
                this.measure();
            } else if (data.type === 'viewport' && this.origin && viewport(data.viewportHeight)) {
                this.setViewport(data.viewportHeight, data.viewportOffset);
                if (data.theme !== undefined) { this.theme.apply(data.theme); this.syncPrice(); }
            } else if (data.type === 'price-ready' && this.origin && this.hostPrice) {
                const root=this.win.document.documentElement;
                if(root.classList.contains('festapp-host-price') !== (data.visible === true)) root.classList.toggle('festapp-host-price',data.visible === true);
            } else if (data.type === 'price-activate' && this.origin && this.hostPrice) {
                this.win.document.getElementById('floating-price-widget')?.click();
            } else if (data.type === 'theme' && this.origin && data.theme !== undefined) {
                this.theme.apply(data.theme);
                this.syncPrice();
            }
        };
        this.win.addEventListener('message', this.onMessage);
        this.onResize = () => this.measure();
        this.win.addEventListener('resize', this.onResize);
        this.observer = new this.win.ResizeObserver(() => this.measure());
        this.observer.observe(this.win.document.body);
        this.mutations = new this.win.MutationObserver(() => this.measure());
        this.mutations.observe(this.win.document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'open'] });
        let attempts = 0;
        this.ready = () => {
            if (!this.origin) this.win.parent.postMessage({ namespace, protocol: 1, type: 'ready' }, '*');
            if (++attempts >= 10 || this.origin) this.win.clearInterval(this.timer);
        };
        this.ready();
        this.timer = this.win.setInterval(this.ready, 500);
    }
    setViewport(height, offset = 0) {
        const style = this.win.document.documentElement.style;
        style.setProperty('--embed-viewport', `${height}px`);
        if (Number.isFinite(offset) && offset >= 0 && offset <= 20000) {
            style.setProperty('--embed-visible-top', `${offset}px`);
        }
    }
    send(type, values) {
        if (this.origin) this.win.parent.postMessage({ namespace, protocol: 1, instance: this.instance, type, ...values }, this.origin);
    }
    measure() {
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
    syncPrice() {
        if (!this.origin || !this.hostPrice) return;
        const widget=this.win.document.getElementById('floating-price-widget');
        const visible=Boolean(widget && this.win.getComputedStyle(widget).display !== 'none');
        const appearance={};
        if(widget) {
            const style=this.win.getComputedStyle(widget);
            for(const property of ['background-color','color','font-family','font-size','font-weight','padding','border-radius','box-shadow']) appearance[property]=style.getPropertyValue(property);
        }
        this.send('price', {price:this.price?.price || null,appearance,visible});
    }
    publishHeight() {
        this.syncPrice();
        const body = this.win.document.body;
        const dialogBottom = [...body.querySelectorAll('dialog[open], .flatpickr-calendar.open')]
            .reduce((bottom, node) => Math.max(bottom, node.getBoundingClientRect().bottom + this.win.scrollY), 0);
        const height = Math.max(240, Math.ceil(body.getBoundingClientRect().height), Math.ceil(dialogBottom));
        if (height !== this.height && Number.isFinite(height)) {
            this.height = height;
            this.send('resize', { height: Math.min(20000, height) });
        }
    }
    scrollTo(element, { block = 'start' } = {}) {
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
        const height = Math.min(20000, Math.max(0, rect.height || rect.bottom - rect.top));
        const y = Math.max(0, (block === 'end' ? rect.bottom : rect.top) + this.win.scrollY);
        if (this.origin && this.autoHeight !== false && this.height <= 20000) {
            // scrollIntoView also scrolls ancestor frames. Only the host may
            // move the page for a naturally sized embed.
            this.send('scroll-request', { y: Math.min(20000, y), height, block });
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
        this.win.removeEventListener('message', this.onMessage);
        this.win.removeEventListener('resize', this.onResize);
        this.win.removeEventListener('festapp-embed-price',this.onPrice);
        this.win.removeEventListener('festapp-embed-scroll-state',this.onScrollState);
        this.win.document.documentElement.classList.remove('festapp-host-price');
        this.theme?.destroy();
        this.observer?.disconnect();
        this.mutations?.disconnect();
        this.win.clearInterval(this.timer);
        this.win.clearTimeout(this.measureTimer);
        if (this.raf) this.win.cancelAnimationFrame(this.raf);
    }
}

// Presentation steps remain owned by the existing components, never the host.
export function revealEmbedStep(element, { block = 'start' } = {}) {
    if (!isEmbed() || !element) return;
    if (!element.matches('input, button, select, textarea, a[href], [tabindex]')) element.tabIndex = -1;
    element.focus({ preventScroll: true });
    window.dispatchEvent(new CustomEvent('festapp-embed-step', { detail: { element, block } }));
}

// Publish the existing widget's view, never order state or price calculations.
export function publishEmbedPrice(price = null) {
    if (!isEmbed()) return;
    window.dispatchEvent(new CustomEvent('festapp-embed-price',{detail:{price}}));
}

// Overlay lifecycle owns restoration; focus and a new checkout step are separate.
export function preserveCheckoutScroll(win = window) {
    const position={left:win.scrollX,top:win.scrollY};
    const restoration=win.history.scrollRestoration;
    win.history.scrollRestoration='manual';
    const snapshot=`s_${win.crypto.randomUUID()}`;
    const notify=type=>{
        if(isEmbed(win.location)) win.dispatchEvent(new win.CustomEvent('festapp-embed-scroll-state',{detail:{type,snapshot}}));
    };
    notify('scroll-save');
    let restored=false;
    return ({restore = true} = {})=>{
        if(restored)return;
        restored=true;
        if (restore) win.scrollTo({...position,behavior:'instant'});
        notify(restore ? 'scroll-restore' : 'scroll-discard');
        win.history.scrollRestoration=restoration;
    };
}
