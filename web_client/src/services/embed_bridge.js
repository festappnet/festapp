import { isEmbed, applyEmbedContext } from './embed_context.js';

const namespace = 'festapp-embed';
const validId = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value);
const viewport = value => Number.isFinite(value) && value >= 240 && value <= 4000;

// The only wildcard message is a public, data-free readiness announcement.
export class EmbedBridge {
    constructor(win = window) { this.win = win; }
    start() {
        if (!isEmbed(this.win.location) || this.win.parent === this.win) return;
        applyEmbedContext();
        this.onMessage = event => {
            const data = event.data;
            if (event.source !== this.win.parent || !/^https?:\/\//.test(event.origin) ||
                data?.namespace !== namespace || data.protocol !== 1 || !validId(data.instance)) return;
            if (this.origin && (event.origin !== this.origin || data.instance !== this.instance)) return;
            if (data.type === 'init' && viewport(data.viewportHeight)) {
                this.origin = event.origin; this.instance = data.instance;
                this.setViewport(data.viewportHeight);
                this.height = null;
                this.measure();
            } else if (data.type === 'viewport' && this.origin && viewport(data.viewportHeight)) {
                this.setViewport(data.viewportHeight);
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
    setViewport(height) {
        this.win.document.documentElement.style.setProperty('--embed-viewport', `${height}px`);
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
            const body = this.win.document.body;
            const dialogBottom = [...body.querySelectorAll('dialog[open], .flatpickr-calendar.open')]
                .reduce((bottom, node) => Math.max(bottom, node.getBoundingClientRect().bottom + this.win.scrollY), 0);
            const height = Math.max(240, Math.ceil(body.getBoundingClientRect().height), Math.ceil(dialogBottom));
            if (height !== this.height && Number.isFinite(height)) {
                this.height = height;
                this.send('resize', { height: Math.min(20000, height) });
            }
        };
        this.raf = this.win.requestAnimationFrame(flush);
        // Chromium can suspend RAF in an offscreen cross-site iframe. Keep its
        // natural height available before the visitor scrolls it into view.
        this.measureTimer = this.win.setTimeout(flush, 200);
    }
    scrollTo(element) {
        const y = Math.max(0, element.getBoundingClientRect().top + this.win.scrollY);
        this.send('scroll-request', { y });
        element.scrollIntoView({ block: 'start', behavior: 'instant' });
    }
    destroy() {
        this.win.removeEventListener('message', this.onMessage);
        this.win.removeEventListener('resize', this.onResize);
        this.observer?.disconnect();
        this.mutations?.disconnect();
        this.win.clearInterval(this.timer);
        this.win.clearTimeout(this.measureTimer);
        if (this.raf) this.win.cancelAnimationFrame(this.raf);
    }
}

// Presentation steps remain owned by the existing components, never the host.
export function revealEmbedStep(element) {
    if (!isEmbed() || !element) return;
    if (!element.matches('input, button, select, textarea, a[href], [tabindex]')) element.tabIndex = -1;
    element.focus({ preventScroll: true });
    window.dispatchEvent(new CustomEvent('festapp-embed-step', { detail: element }));
}
