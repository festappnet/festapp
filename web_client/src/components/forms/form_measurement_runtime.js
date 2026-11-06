import {analyticsPayload, attributionContext, measurementId, measurementNamespace, measurementOrigin} from './form_measurement_contract.js';

// Implements the same small transport seam as EmbedBridge. No funnel, queue,
// configuration scripts or privileged backend client lives in this document.
export class FormMeasurementRuntime {
    constructor({win = window, model, onReady = () => {}, canRun = () => true, campaign = () => ({}), local = false}) {
        this.win = win; this.model = model; this.onReady = onReady; this.local = local;
        this.canRun = canRun;
        this.campaign = campaign;
        this.scope = JSON.stringify([model.data?.analytics?.organization,model.data?.analytics?.unit]);
        this.policyUntil = Date.now() + Math.min(60, Math.max(0, Number(model.data?.analytics?.valid_for_seconds) || 0)) * 1000;
        this.onMessage = event => {
            if (!this.frame || event.source !== this.frame.contentWindow || event.origin !== this.origin ||
                event.data?.namespace !== measurementNamespace || event.data.protocol !== 1) return;
            if (!this.hasLiveFrame()) { this.revokeMeasurement(); return; }
            if (event.data.type === 'ready' && !this.ready) {
                this.send('init', {context: this.context});
            } else if (event.data.type === 'ack' && event.data.instance === this.instance && !this.ready) {
                this.win.clearTimeout(this.handshake);
                this.ready = true;
                this.onReady();
            }
        };
        win.addEventListener('message', this.onMessage);
        this.onContext = () => { if (!this.safeContext()) this.revokeMeasurement(); };
        for (const event of ['hashchange','popstate','storage']) win.addEventListener(event,this.onContext);
    }
    safeContext() { try { return this.canRun() === true; } catch { return false; } }
    setConsent(granted, expiresAt = Date.now() + 60000) {
        if (this.frame && Date.now() >= this.consentUntil) this.revokeMeasurement();
        this.consentUntil = granted === true && Number.isFinite(expiresAt) ? Math.min(expiresAt,Date.now()+60000) : 0;
        if (granted !== true) this.revokeMeasurement();
        else this.updatePolicy();
    }
    updatePolicy(expiresAt) {
        if (Number.isFinite(expiresAt)) this.policyUntil = expiresAt;
        const policy = this.model.data?.analytics;
        // A saved choice belongs to one organizer. A scope move requires a new
        // page/CMP binding, rather than recycling the previous Unit's consent.
        if (JSON.stringify([policy?.organization,policy?.unit]) !== this.scope) { this.destroy(); return; }
        if (this.frame && !this.frame.isConnected) this.revokeMeasurement();
        const origin = measurementOrigin(policy?.runtime_origin, this.local);
        const key = JSON.stringify([origin, policy?.organization, policy?.configuration_revision, policy?.policy_revision, policy?.runtime_revision]);
        if (this.frame && this.key !== key) this.revokeMeasurement();
        if (!origin || origin === this.win.location.origin || policy?.eligible !== true ||
            Date.now() >= Math.min(this.consentUntil || 0, this.policyUntil) || this.win.document.hidden || this.disposed || !this.safeContext()) {
            this.revokeMeasurement(); return;
        }
        if (this.frame) { this.armExpiry(); return; }
        const input = {...Object.fromEntries(new URLSearchParams(this.win.location.search)),...this.campaign()};
        input.page_location = new URL('/form/' + this.model.link,this.win.location.origin).href;
        input.page_referrer = this.win.document.referrer;
        this.context = attributionContext(input);
        if (!this.context) return;
        this.origin = origin; this.key = key; this.ready = false;
        this.instance = this.win.crypto.randomUUID();
        const frame = this.frame = this.win.document.createElement('iframe');
        frame.hidden = true;
        frame.title = 'Measurement';
        frame.referrerPolicy = 'no-referrer';
        frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
        const url = new URL('/runtime', origin);
        url.searchParams.set('form', this.model.link);
        url.searchParams.set('parent', this.win.location.origin);
        frame.src = url.href;
        this.win.document.body.append(frame);
        this.handshake = this.win.setTimeout(() => { if (!this.ready) this.revokeMeasurement(); },8000);
        // The parent owns expiry; tenant code cannot keep its frame alive.
        this.armExpiry();
    }
    armExpiry() {
        this.win.clearTimeout(this.expiry);
        this.expiry = this.win.setTimeout(() => this.revokeMeasurement(),Math.max(0,Math.min(this.consentUntil,this.policyUntil)-Date.now()));
    }
    send(type, extra) {
        if (!this.hasLiveFrame()) return false;
        try {
            const target = this.frame.contentWindow;
            if (!target) return false;
            target.postMessage({namespace: measurementNamespace, protocol: 1,
                instance: this.instance, type, ...extra}, this.origin);
            return true;
        } catch { return false; }
    }
    measurementEpoch() { return this.measurementAllowed() ? this.instance : null; }
    hasLiveFrame() {
        return !this.disposed && this.frame?.isConnected === true && Date.now() < Math.min(this.consentUntil, this.policyUntil) && !this.win.document.hidden && this.safeContext();
    }
    measurementAllowed() {
        return this.ready === true && this.hasLiveFrame();
    }
    track(input) {
        if (!this.measurementAllowed()) return false;
        const payload = analyticsPayload(input);
        if (!payload || !measurementId(this.instance)) return false;
        return this.send('event', {payload});
    }
    revokeMeasurement() {
        this.ready = false;
        this.win.clearTimeout(this.expiry);
        this.win.clearTimeout(this.handshake);
        this.frame?.remove(); this.frame = null; this.instance = null;
    }
    destroy() {
        this.disposed = true; this.consentUntil = 0; this.revokeMeasurement();
        this.win.removeEventListener('message', this.onMessage);
        for (const event of ['hashchange','popstate','storage']) this.win.removeEventListener(event,this.onContext);
    }
}
