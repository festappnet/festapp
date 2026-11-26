import {consentTransportManifest, measurementConsent, measurementManifest, sameMeasurementManifest, analyticsPayload, currentMetaPurchaseRouting} from './form_measurement_contract.js';
import {hasCurrentPurchaseConsent} from './meta_purchase_consent.js';
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
        entryAllowed, authorizedOrderScope=null, onActive=()=>{}, onConsent=()=>{}, allowMetaPurchase=()=>true, clock=()=>Date.now()}) {
        Object.assign(this,{win,model,policySource,consentSource,identitySource,transport,onActive,onConsent,allowMetaPurchase,clock});
        this.authorizedOrderScope=authorizedOrderScope;
        this.entryAllowed=this.orderContextAllowed() || (entryAllowed ?? publicFormLocation(win.location,{entry:true})) && documentEntryAllowed(win);
        this.policyVerification=0; this.contextEpoch=0; this.pendingConversions=new Map(); this.deliveredConversions=new Set();
        this.generation=0; this.state='blocked'; this.consent=measurementConsent(false);
    }
    start() {
        if (this.started || this.disposed) return;
        this.started=true;
        // Hiding keeps the frame, so a tab switch does not run the container again.
        this.visibility=()=>{if (!this.win.document.hidden) this.refresh();};
        this.pagehide=()=>{this.suspended=true; this.invalidate();};
        this.pageshow=()=>{this.suspended=false; this.invalidate(); this.refresh();};
        this.observedIdentity=this.identity();
        this.observedPublicContext=this.publicContext();
        this.contextChanged=()=>this.restartContext();
        this.navigationChanged=()=>{
            const context=this.publicContext();
            if (context && context===this.observedPublicContext && this.identity()===this.observedIdentity) return;
            this.contextChanged();
        };
        this.win.document.addEventListener('visibilitychange',this.visibility);
        this.win.addEventListener('pagehide',this.pagehide); this.win.addEventListener('pageshow',this.pageshow);
        // Consent sources own their storage updates. Other tabs can change unrelated
        // keys without changing the visitor or invalidating an in-flight order fact.
        this.storageChanged=()=>{
            if(this.identity()!==this.observedIdentity)this.contextChanged();
            else this.refresh();
        };
        this.win.addEventListener('storage',this.storageChanged);
        for (const event of ['popstate','hashchange']) this.win.addEventListener(event,this.navigationChanged);
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
    invalidateContext() {
        this.observedIdentity=this.identity();
        this.observedPublicContext=this.publicContext();
        this.contextEpoch++;
        this.pendingConversions.clear();
        this.until=0;
        this.invalidate();
    }
    restartContext() {
        this.invalidateContext();
        return this.refresh();
    }
    publicContext() {
        const {location}=this.win;
        // Only the already allowed public form overlays share a context with
        // the form beneath them. Query, private routes and identity keep their gates.
        return publicFormLocation(location,{link:this.model.link}) ? location.href.split('#')[0] : null;
    }
    // Set only after a successful buyer-capability RPC. Never exported to runtime.
    orderContextAllowed() {
        const scope=this.authorizedOrderScope, loc=this.win.location;
        if(!scope || loc.pathname!=='/order' || loc.hash)return false;
        const q=new URLSearchParams(loc.search);
        if ([...q.keys()].some(key=>!['token','order_id','embed'].includes(key)) ||
            q.getAll('token').length!==1 || q.getAll('order_id').length!==1 ||
            (q.has('embed') && (q.getAll('embed').length!==1 || q.get('embed')!=='1'))) return false;
        let framed=true;
        try {framed=this.win.self!==this.win.top;} catch { /* Restricted frames stay embedded. */ }
        // A private buyer route in a frame must explicitly select host context.
        if (framed && q.get('embed')!=='1') return false;
        return q.get('token')===scope.token && q.get('order_id')===String(scope.orderId) &&
            /^[a-f0-9]{64}$/.test(scope.token) && Number.isSafeInteger(scope.orderId) && scope.orderId>0;
    }
    contextAllowed() {
        try {return !this.disposed && !this.suspended && this.entryAllowed &&
            !this.model.demoSimulation && (this.orderContextAllowed() || publicFormLocation(this.win.location,{link:this.model.link}));} catch {return false;}
    }
    refresh() {
        if (this.disposed) return Promise.resolve();
        const context=this.publicContext();
        if (this.started && context!==this.observedPublicContext) this.invalidateContext();
        if (this.inflight) return this.inflight;
        const generation=this.generation, identity=this.identity();
        const request=Promise.resolve().then(()=>this.policySource()).then(policy=>{
            if (this.disposed || generation!==this.generation || identity!==this.identity() || context!==this.publicContext()) return;
            const manifest=measurementManifest(policy,this.model.link);
            const consentManifest=consentTransportManifest(policy,this.model.link);
            const runtimeChanged=manifest!==(this.manifest ?? null) && !sameMeasurementManifest(manifest,this.manifest);
            const consentChanged=!sameMeasurementManifest(consentManifest,this.consentManifest);
            if (runtimeChanged || consentChanged || (this.grant && this.clock()>=this.until)) this.invalidate();
            this.verifiedIdentity=identity; this.policy=policy; this.model.data.analytics=policy;
            if (runtimeChanged) this.manifest=manifest;
            if (consentChanged) this.consentManifest=consentManifest;
            this.until=this.clock()+Math.min(60,Math.max(0,Number(policy?.valid_for_seconds)||0))*1000;
            if (consentChanged || !this.consentConnected || this.consentStaff!==(policy?.visitor_role==='staff')) this.connectConsent();
            this.win.clearTimeout(this.expiry);
            this.expiry=this.win.setTimeout(()=>{this.invalidate();},Math.max(0,this.until-this.clock()));
            this.transport.renew?.(this.consentDeadline());
            if (!this.suspended) this.onConsent(this.consent);
            this.policyVerification++;
            this.reconcile();
            this.flushConversions();
        }).catch(()=>{
            if (!this.disposed && generation===this.generation) {this.until=0; this.invalidate();}
        }).finally(()=>{if(this.inflight===request)this.inflight=null;});
        this.inflight=request; return request;
    }
    connectConsent() {
        this.consentBinding=null; this.disconnectConsent?.(); this.consentStaff=this.policy?.visitor_role==='staff'; this.consent=measurementConsent(false); this.consentConnected=true;
        const manifest=this.consentManifest; const binding={}; this.consentBinding=binding;
        try {
            this.disconnectConsent=this.consentSource.connect(this.policy,value=>{
                if(this.disposed || this.consentBinding!==binding || manifest!==this.consentManifest) return;
                if(value==null)this.consentConnected=false;
                const leased = value?.leaseId !== undefined || value?.expiresAt !== undefined;
                const validLease = !leased || (typeof value.leaseId === 'string' && value.leaseId.length > 0 &&
                    Number.isFinite(value.expiresAt) && value.expiresAt > this.clock() && value.expiresAt <= this.clock()+60000);
                const next=measurementConsent(validLease ? value : false);
                const changed=next.analytics!==this.consent.analytics || next.marketing!==this.consent.marketing;
                if(value?.leaseId!==this.consent.leaseId) this.invalidate();
                this.consent={...next,purchaseConsent:validLease ? value?.purchaseConsent : null,leaseId:value?.leaseId,expiresAt:validLease ? value?.expiresAt : 0};
                if (validLease && this.grant) this.transport.renew?.(this.consentDeadline());
                if(changed && validLease)this.transport.updateConsent?.(next);
                if (!this.suspended) this.onConsent(this.consent);
                this.reconcile();
            });
        } catch {this.consentConnected=false;this.consent=measurementConsent(false);this.transport.updateConsent?.(this.consent);}
    }
    consentDeadline() { return Math.min(this.until, this.consent.expiresAt ?? Infinity); }
    hasCurrentPolicy() {
        return this.contextAllowed() && this.publicContext()===this.observedPublicContext && this.identity()===this.verifiedIdentity &&
            this.policy?.visitor_role!=='staff' && this.clock()<this.until;
    }
    permitted() {
        const p=this.policy;
        const host=this.transport.hostContext?.() || null;
        const hostAllowed=!host || (Array.isArray(p?.approved_hosts) && p.approved_hosts.includes(host.origin));
        const hostUnchanged=!this.grant || (host?.origin===this.grant.host?.origin && host?.instance===this.grant.host?.instance);
        return hostAllowed && hostUnchanged && this.clock()>=(this.failureUntil||0) && this.hasCurrentPolicy() &&
            (this.identity()==='anonymous' || p?.visitor_role==='visitor') &&
            p?.enabled===true && p.organization_allowed===true && p.runtime_supported===true && p.eligible===true &&
            !!this.manifest &&
            (this.consent.expiresAt === undefined || (Number.isFinite(this.consent.expiresAt) && this.clock()<this.consent.expiresAt && this.consent.expiresAt<=this.clock()+60000));
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
        try {this.transport.activate({...grant,expiresAt:this.consentDeadline(),
            onReady:()=>{if(this.grant===grant && this.permitted() && this.state==='starting'){this.state='active';this.onActive();this.flushConversions();}},
            onMismatch:()=>{if(this.grant===grant){this.failureUntil=this.clock()+20000;this.invalidate();this.refresh();}}});}
        catch {this.invalidate();}
    }
    canSend(payload) {
        return payload.event !== 'meta_purchase' ||
            (this.allowMetaPurchase() && hasCurrentPurchaseConsent(this.consent,this.clock()));
    }
    capture() {
        const grant=this.state==='active' && this.permitted()?this.grant:null;
        return input=>{
            if(!grant || this.grant!==grant || this.state!=='active' || !this.permitted()) return false;
            const wire=analyticsPayload(input);
            const payload=wire && currentMetaPurchaseRouting(wire,this.clock());
            try {return !!payload && this.canSend(payload) && this.transport.track(payload)===true;} catch {return false;}
        };
    }
    // Only immutable conversion facts may cross a grant boundary. Never retain contacts.
    captureConversion() {
        const send=this.capture(), manifest=this.manifest, identity=this.identity();
        const host=this.transport.hostContext?.() || null;
        const selection=this.grant?.selection, epoch=this.contextEpoch;
        const eligible=this.state==='active' && this.permitted();
        return input=>{
            const wire=analyticsPayload(input);
            const payload=wire && currentMetaPurchaseRouting(wire,this.clock());
            if(this.disposed || !eligible || !payload || !['purchase','meta_purchase','generate_lead'].includes(payload.event) || !this.canSend(payload))return false;
            const key=payload.event+':'+(payload.ecommerce?.transaction_id || payload.event_id);
            if(this.deliveredConversions.has(key) || this.pendingConversions.has(key))return true;
            if(send(payload)){this.deliveredConversions.add(key);return true;}
            const {user_data, ...fact}=payload;
            const pending={fact,manifest,identity,host,selection,epoch,verification:this.policyVerification};
            this.pendingConversions.set(key,pending);
            this.refresh();
            return true;
        };
    }
    flushConversions() {
        for(const [key,pending] of this.pendingConversions) {
            const host=this.transport.hostContext?.() || null;
            if(!currentMetaPurchaseRouting(pending.fact,this.clock()) || pending.epoch!==this.contextEpoch || pending.identity!==this.identity() || !sameMeasurementManifest(pending.manifest,this.manifest) ||
                pending.host?.origin!==host?.origin || pending.host?.instance!==host?.instance ||
                (this.grant && pending.selection!==this.grant.selection)) {
                this.pendingConversions.delete(key);continue;
            }
            // Recheck current advertising consent when flushing a Meta companion.
            // General conversions still supply consent as state to the receiving tags.
            if(this.policyVerification>pending.verification && this.record(pending.fact)) {
                this.pendingConversions.delete(key);this.deliveredConversions.add(key);
            }
        }
    }
    record(input) {return this.capture()(input);}
    dispose() {
        if(this.disposed)return;
        this.disposed=true; this.pendingConversions.clear(); this.invalidate(); this.win.clearTimeout(this.expiry); this.consentBinding=null; this.disconnectConsent?.();
        this.unsubscribeIdentity?.();this.unsubscribeTransport?.();this.win.clearInterval(this.timer);
        this.win.document.removeEventListener('visibilitychange',this.visibility);
        this.win.removeEventListener('pagehide',this.pagehide);this.win.removeEventListener('pageshow',this.pageshow);
        this.win.removeEventListener('storage',this.storageChanged);
        for(const event of ['popstate','hashchange'])this.win.removeEventListener(event,this.navigationChanged);
    }
}
