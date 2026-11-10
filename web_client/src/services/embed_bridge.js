import {isEmbed, applyEmbedContext} from './embed_context.js';
import {EmbedTheme} from './embed_theme.js';
import {EmbedChannel} from '../embed/channel.js';
import {EmbedLayout} from '../embed/layout.js';
import {EmbedMeasurement} from '../embed/measurement.js';

const activeBridges = new WeakMap();

export class EmbedBridge {
    constructor(win = window) {
        this.win = win;
        this.channel = new EmbedChannel({peer:() => win.parent, destination:'child'});
        this.theme = new EmbedTheme(win);
        this.layout = new EmbedLayout(win, this.channel, () => this.syncPrice());
        this.measurement = new EmbedMeasurement(win, this.channel);
    }
    get origin() { return this.channel.origin; }
    set origin(value) { this.channel.origin = value; }
    get instance() { return this.channel.instance; }
    set instance(value) { this.channel.instance = value; }
    get autoHeight() { return this.layout.autoHeight; }
    set autoHeight(value) { this.layout.autoHeight = value; }
    get scrollAlignment() { return this.layout.scrollAlignment; }
    set scrollAlignment(value) { this.layout.scrollAlignment = value; }
    get measurementCampaign() { return this.measurement.measurementCampaign; }
    setInheritStyle(enabled) {
        if (this.destroyed) return;
        this.formInheritStyle = enabled === true;
        this.applyStylePreference();
    }
    applyStylePreference() {
        this.theme.setEnabled(this.formInheritStyle === true);
        this.syncPrice();
    }
    receiveTheme(theme) {
        if (this.destroyed) return;
        this.theme.apply(theme);
        this.syncPrice();
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
    start() {
        if (this.started || this.channel.closed || !isEmbed(this.win.location) || this.win.parent === this.win) return;
        activeBridges.get(this.win)?.destroy();
        activeBridges.set(this.win, this);
        this.started = true;
        applyEmbedContext(this.win.document, this.win.location);
        this.onPrice = event => { this.price = event.detail; this.syncPrice(); };
        this.win.addEventListener('festapp-embed-price', this.onPrice);
        this.onMessage = event => {
            const data = this.channel.receive(event);
            if (!data) return;
            switch (data.type) {
                case 'init':
                    this.applyStylePreference();
                    this.hostPrice = data.hostPrice === true;
                    this.measurement.configure(data);
                    if (data.theme !== undefined) this.receiveTheme(data.theme);
                    this.layout.configure(data);
                    this.syncPrice();
                    break;
                case 'viewport':
                    this.layout.setViewport(data.viewportHeight, data.viewportOffset);
                    if (data.theme !== undefined) this.receiveTheme(data.theme);
                    break;
                case 'price-ready':
                    if (this.hostPrice) this.win.document.documentElement.classList.toggle('festapp-host-price', data.visible === true);
                    break;
                case 'price-activate':
                    if (this.hostPrice) this.win.document.getElementById('floating-price-widget')?.click();
                    break;
                case 'theme': if (data.theme !== undefined) this.receiveTheme(data.theme); break;
                default: this.measurement.receive(data);
            }
        };
        this.win.addEventListener('message', this.onMessage);
        this.layout.start();
        this.onPageHide = () => this.measurement.suspend();
        this.onPageShow = () => { this.measurement.resume(); this.layout.measure(); this.channel.announce(); };
        this.win.addEventListener('pagehide', this.onPageHide);
        this.win.addEventListener('pageshow', this.onPageShow);
        let attempts = 0;
        this.ready = () => {
            this.channel.announce();
            if (++attempts >= 10 || this.origin) this.win.clearInterval(this.timer);
        };
        this.ready();
        this.timer = this.win.setInterval(this.ready, 500);
    }
    send(type, values) { this.channel.send(type, values); }
    setViewport(...args) { return this.layout.setViewport(...args); }
    measure() { return this.layout.measure(); }
    publishHeight() { return this.layout.publishHeight(); }
    scrollTo(...args) { return this.layout.scrollTo(...args); }
    subscribe(...args) { return this.measurement.subscribe(...args); }
    setMeasurementRuntime(...args) { return this.measurement.setMeasurementRuntime(...args); }
    selection(...args) { return this.measurement.selection(...args); }
    connectConsent(...args) { return this.measurement.connectConsent(...args); }
    hostContext(...args) { return this.measurement.hostContext(...args); }
    activate(...args) { return this.measurement.activate(...args); }
    renew(...args) { return this.measurement.renew(...args); }
    updateIdentity(...args) { return this.measurement.updateIdentity(...args); }
    updateConsent(...args) { return this.measurement.updateConsent(...args); }
    stop(...args) { return this.measurement.stop(...args); }
    track(...args) { return this.measurement.track(...args); }
    destroy() {
        if (this.destroyed) return;
        this.destroyed = true;
        if (activeBridges.get(this.win) === this) activeBridges.delete(this.win);
        this.channel.destroy(); this.measurement.destroy(); this.layout.destroy();
        this.win.removeEventListener('message', this.onMessage);
        this.win.removeEventListener('pagehide', this.onPageHide);
        this.win.removeEventListener('pageshow', this.onPageShow);
        this.win.removeEventListener('festapp-embed-price', this.onPrice);
        this.win.clearInterval(this.timer);
        this.win.document.documentElement.classList.remove('festapp-host-price');
        this.theme.destroy();
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
