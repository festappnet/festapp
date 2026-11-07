import {measurementConsent, measurementManifest, sameMeasurementManifest, analyticsPayload} from './form_measurement_contract.js';
import {publicFormLocation, documentEntryAllowed} from '../../utils/public_form_location.js';
import {AppConfig} from '../../app_config.js';
import {browserStorage} from '../../services/browser_storage.js';

export function hasBrowserSession(win) {
    try {
        if (browserStorage.getItem(AppConfig.Keys.auth)) return true;
        for (const storage of [win.localStorage, win.sessionStorage]) for (let i=0;i<storage.length;i++) {
            const key=storage.key(i);
            if ((key===AppConfig.Keys.auth || key==='refresh' || /^sb-.*-auth-token/.test(key)) && storage.getItem(key)) return true;
        }
        return false;
    } catch { return true; }
}

// The only owner of eligibility, role, freshness and grant lifetime.
// Consent is state for the organizer's container, never a condition to run.
// Construction is inert. Sources and transports never decide to grant access.
export class FormMeasurementSession {
    constructor({win=window, model, policySource, consentSource, identitySource, transport,
        entryAllowed, onActive=()=>{}, clock=()=>Date.now()}) {
        Object.assign(this,{win,model,policySource,consentSource,identitySource,transport,onActive,clock});
        this.entryAllowed=(entryAllowed ?? publicFormLocation(win.location,{entry:true})) && documentEntryAllowed(win);
        this.generation=0; this.state='blocked'; this.consent=measurementConsent(false);
    }
    start() {
        if (this.started || this.disposed) return;
        this.started=true;
        // Hiding keeps the frame, so a tab switch does not run the container again.
        this.visibility=()=>{if (!this.win.document.hidden) this.refresh();};
        this.pagehide=()=>{this.suspended=true; this.invalidate();};
        this.pageshow=()=>{this.suspended=false; this.invalidate(); this.refresh();};
        this.contextChanged=()=>{this.invalidate(); this.refresh();};
        this.win.document.addEventListener('visibilitychange',this.visibility);
        this.win.addEventListener('pagehide',this.pagehide); this.win.addEventListener('pageshow',this.pageshow);
        for (const event of ['storage','popstate','hashchange']) this.win.addEventListener(event,this.contextChanged);
        this.unsubscribeIdentity=this.identitySource?.subscribe?.(()=>this.contextChanged());
        this.unsubscribeTransport=this.transport.subscribe?.(()=>this.reconcile());
        this.timer=this.win.setInterval(()=>this.refresh(),20000);
        this.refresh();
    }
    invalidate() {
        this.generation++; this.grant=null; this.inflight=null;
        this.state=this.disposed?'disposed':'blocked';
        this.transport.stop();
    }
    identity() { return this.identitySource?.read?.() ?? (hasBrowserSession(this.win)?'authenticated':'anonymous'); }
    contextAllowed() {
        try {return !this.disposed && !this.suspended && this.entryAllowed &&
            !this.model.demoSimulation && publicFormLocation(this.win.location);} catch {return false;}
    }
    refresh() {
        if (this.disposed) return Promise.resolve();
        if (this.inflight) return this.inflight;
        const generation=this.generation, identity=this.identity();
        const request=Promise.resolve().then(()=>this.policySource()).then(policy=>{
            if (this.disposed || generation!==this.generation || identity!==this.identity()) return;
            const manifest=measurementManifest(policy,this.model.link);
            const changed=!sameMeasurementManifest(manifest,this.manifest);
            if (changed || (this.grant && this.clock()>=this.until)) this.invalidate();
            this.verifiedIdentity=identity; this.policy=policy; this.model.data.analytics=policy; this.manifest=changed?manifest:this.manifest;
            this.until=this.clock()+Math.min(60,Math.max(0,Number(policy?.valid_for_seconds)||0))*1000;
            if (changed || !this.consentConnected || this.consentStaff!==(policy?.visitor_role==='staff')) this.connectConsent();
            this.win.clearTimeout(this.expiry);
            this.expiry=this.win.setTimeout(()=>{this.invalidate();},Math.max(0,this.until-this.clock()));
            this.transport.renew?.(this.until);
            this.reconcile();
        }).catch(()=>{
            if (!this.disposed && generation===this.generation) {this.until=0; this.invalidate();}
        }).finally(()=>{if(this.inflight===request)this.inflight=null;});
        this.inflight=request; return request;
    }
    connectConsent() {
        this.consentBinding=null; this.disconnectConsent?.(); this.consentStaff=this.policy?.visitor_role==='staff'; this.consent=measurementConsent(false); this.consentConnected=true;
        const manifest=this.manifest; const binding={}; this.consentBinding=binding;
        try {
            this.disconnectConsent=this.consentSource.connect(this.policy,value=>{
                if(this.disposed || this.consentBinding!==binding || manifest!==this.manifest) return;
                if(value==null)this.consentConnected=false;
                const next=measurementConsent(value);
                const changed=next.analytics!==this.consent.analytics || next.marketing!==this.consent.marketing;
                if(value?.leaseId!==this.consent.leaseId) this.invalidate();
                this.consent={...next,leaseId:value?.leaseId,expiresAt:value?.expiresAt};
                if(changed)this.transport.updateConsent?.(next);
                this.reconcile();
            });
        } catch {this.consentConnected=false;this.consent=measurementConsent(false);this.transport.updateConsent?.(this.consent);}
    }
    permitted() {
        const p=this.policy;
        const host=this.transport.hostContext?.() || null;
        const hostAllowed=!host || (Array.isArray(p?.approved_hosts) && p.approved_hosts.includes(host.origin));
        const hostUnchanged=!this.grant || (host?.origin===this.grant.host?.origin && host?.instance===this.grant.host?.instance);
        return hostAllowed && hostUnchanged && this.clock()>=(this.failureUntil||0) && this.contextAllowed() && this.identity()===this.verifiedIdentity && p?.visitor_role!=='staff' &&
            (this.identity()==='anonymous' || p?.visitor_role==='visitor') &&
            p?.enabled===true && p.organization_allowed===true && p.runtime_supported===true && p.eligible===true &&
            !!this.manifest && this.clock()<this.until &&
            (!this.consent.expiresAt || this.clock()<this.consent.expiresAt);
    }
    reconcile() {
        if (this.disposed) return;
        // Identity is verified only by the matching policy request, never by a transport.
        if (!this.permitted()) {if(this.grant)this.invalidate(); this.state='blocked'; return;}
        const selection=this.transport.selection ? this.transport.selection() : 'runtime';
        if (!selection) {if(this.grant)this.invalidate(); return;}
        if(this.grant && this.grant.selection!==selection) this.invalidate();
        if(this.grant) return;
        const host=this.transport.hostContext?.() || null;
        const grant=this.grant={host:host?Object.freeze({...host}):null,runtimeOrigin:this.policy.runtime_origin,manifest:this.manifest,generation:this.generation,identity:this.identity(),selection,
            consent:measurementConsent(this.consent),leaseId:this.consent.leaseId};
        this.state='starting';
        try {this.transport.activate({...grant,expiresAt:Math.min(this.until,this.consent.expiresAt||Infinity),
            onReady:()=>{if(this.grant===grant && this.permitted() && this.state==='starting'){this.state='active';this.onActive();}},
            onMismatch:()=>{if(this.grant===grant){this.failureUntil=this.clock()+20000;this.invalidate();this.refresh();}}});}
        catch {this.invalidate();}
    }
    capture() {
        const grant=this.state==='active' && this.permitted()?this.grant:null;
        return input=>{
            if(!grant || this.grant!==grant || this.state!=='active' || !this.permitted()) return false;
            const payload=analyticsPayload(input);
            try {return !!payload && this.transport.track(payload)===true;} catch {return false;}
        };
    }
    record(input) {return this.capture()(input);}
    dispose() {
        if(this.disposed)return;
        this.disposed=true; this.invalidate(); this.win.clearTimeout(this.expiry); this.consentBinding=null; this.disconnectConsent?.();
        this.unsubscribeIdentity?.();this.unsubscribeTransport?.();this.win.clearInterval(this.timer);
        this.win.document.removeEventListener('visibilitychange',this.visibility);
        this.win.removeEventListener('pagehide',this.pagehide);this.win.removeEventListener('pageshow',this.pageshow);
        for(const event of ['storage','popstate','hashchange'])this.win.removeEventListener(event,this.contextChanged);
    }
}
