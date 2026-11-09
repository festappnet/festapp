import {validId} from './protocol.js';
import {measurementProtocol, analyticsPayload, campaignContext, measurementConsent, measurementManifest, sameMeasurementManifest} from '../components/forms/form_measurement_contract.js';

export class EmbedMeasurement {
    constructor(win, channel) { Object.assign(this, {win, channel}); }
    get origin() { return this.channel.origin; }
    get instance() { return this.channel.instance; }
    send(type, values) { this.channel.send(type, values); }
    configure(data) {
        this.dataLayer = data.dataLayer === true;
        this.measurementProtocol = data.measurementProtocol;
        this.measurementCampaign = campaignContext(data.attribution);
        this.requestConsent(); this.measurementChanged?.();
    }
    receive(data) {
        if (this.suspended) return;
            if (data.type === 'measurement-consent' && data.measurement?.protocol===measurementProtocol) {
                const value=data.measurement;
                if(!sameMeasurementManifest(value.manifest,this.measurementManifest))return;
                // The lease proves a live helper. The purposes are only state for tags.
                const granted=validId(value.leaseId);
                const changed=this.leaseId!==value.leaseId;
                if(changed)this.stop();
                this.leaseId=granted?value.leaseId:null;
                this.leaseUntil=granted?Date.now()+Math.min(60000,Math.max(0,Number(value.ttl)||0)):0;
                this.win.clearTimeout(this.leaseTimer);
                this.leaseTimer=this.win.setTimeout(()=>{this.stop();this.consentNotify?.(false);},Math.max(0,this.leaseUntil-Date.now()));
                this.consentNotify?.(granted?{...measurementConsent(value.consent),leaseId:this.leaseId,expiresAt:this.leaseUntil}:false);
            } else if (data.type === 'measurement-ack' && this.grant && data.measurement?.protocol===measurementProtocol &&
                data.measurement.generation===this.grant.generation && data.measurement.leaseId===this.grant.leaseId &&
                sameMeasurementManifest(data.measurement.manifest,this.grant.manifest) && Date.now()<this.leaseUntil) {
                this.hostActive=true;this.grant.onReady();

            }
    }
    subscribe(notify) {
        const binding = this.subscription = {};
        this.measurementChanged = notify;
        return () => { if (this.subscription === binding) this.measurementChanged = null; };
    }
    setMeasurementRuntime(runtime) {this.measurementRuntime=runtime;}
    selection() {return !this.channel.closed && !this.suspended && this.origin && this.measurementProtocol===measurementProtocol ? (this.dataLayer?'host':'runtime') : null;}
    connectConsent(policy,notify) {
        const binding = this.consentBinding = {};
        this.measurementManifest=measurementManifest(policy,policy?.form_link);
        this.consentNotify=notify;this.requestConsent();
        return ()=>{if(this.consentBinding!==binding)return;this.consentNotify=null;this.measurementManifest=null;this.stop();};
    }
    requestConsent() {
        if(this.selection() && this.measurementManifest)this.send('measurement-context',{measurement:{protocol:measurementProtocol,manifest:this.measurementManifest}});
    }
    hostContext() {return this.selection()?{origin:this.origin,instance:this.instance}:null;}
    activate(grant) {
        this.stop();
        if(grant.selection!==this.selection() || grant.host?.origin!==this.origin || grant.host?.instance!==this.instance || !this.leaseId || this.leaseId!==grant.leaseId || Date.now()>=this.leaseUntil)return;
        this.grant=grant;
        if(grant.selection==='runtime')this.measurementRuntime.activate(grant);
        else this.send('measurement-activate',{measurement:{protocol:measurementProtocol,manifest:grant.manifest,generation:grant.generation,leaseId:grant.leaseId}});
    }
    renew(until) {this.measurementRuntime?.renew(Math.min(until,this.leaseUntil||0));}
    updateConsent(consent) {this.measurementRuntime?.updateConsent(consent);}
    stop() {this.grant=null;this.hostActive=false;this.measurementRuntime?.stop();}
    track(input) {
        if(!this.grant || Date.now()>=this.leaseUntil)return false;
        const payload=analyticsPayload(input);if(!payload)return false;
        if(this.grant.selection==='runtime')return this.measurementRuntime.track(payload);
        if(!this.hostActive)return false;
        this.send('analytics',{measurement:{protocol:measurementProtocol,manifest:this.grant.manifest,generation:this.grant.generation,leaseId:this.grant.leaseId},payload});return true;
    }
    suspend() {
        this.suspended = true; this.stop(); this.leaseId = null; this.leaseUntil = 0;
        this.win.clearTimeout(this.leaseTimer); this.consentNotify?.(false);
    }
    resume() { this.suspended = false; this.requestConsent(); }
    destroy() {
        this.suspended = true;
        this.stop(); this.win.clearTimeout(this.leaseTimer);
        this.consentNotify = null; this.measurementChanged = null; this.measurementManifest = null;
    }
}
