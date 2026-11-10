import {measurementProtocol} from './form_measurement_contract.js';
import {measurementSignals, measurementConsent, measurementHostIdentity, analyticsPayload, attributionContext, measurementId, measurementNamespace, measurementOrigin, sameMeasurementManifest} from './form_measurement_contract.js';

// Mechanical isolated transport. Only the session supplies a grant.
export class FormMeasurementRuntime {
    constructor({win=window, model, campaign=()=>({}), embedded=false, local=false}) {
        Object.assign(this,{win,model,campaign,embedded,local});
        this.onMessage=event=>{
            const data=event.data, grant=this.grant;
            if(!grant || !this.live() || event.source!==this.frame?.contentWindow || event.origin!==this.origin ||
                data?.namespace!==measurementNamespace || data.protocol!==measurementProtocol) return;
            if(!sameMeasurementManifest(data.manifest,grant.manifest)) {const mismatch=grant.onMismatch;this.stop();mismatch();return;}
            if(data.type==='ready' && !this.ready) {this.initialized=this.send('init',{context:this.context,consent:this.consent,hostIdentity:this.hostIdentity});if(this.initialized)this.cleanLinker();}
            else if(data.type==='ack' && data.instance===this.instance && data.generation===grant.generation && !this.ready) {
                this.win.clearTimeout(this.handshake);this.ready=true;grant.onReady();
            }
        };
        win.addEventListener('message',this.onMessage);
    }
    activate(grant) {
        this.stop();
        if(this.disposed || !grant)return;
        const origin=measurementOrigin(grant.runtimeOrigin,this.local);
        if(!origin || origin===this.win.location.origin)return;
        const input={...Object.fromEntries(new URLSearchParams(this.win.location.search)),...this.campaign(),
            form_embedded:this.embedded, page_location:new URL('/form/'+grant.manifest.form_link,this.win.location.origin).href,page_referrer:this.win.document.referrer};
        this.context=attributionContext(input);if(!this.context)return;
        if(this.embedded && grant.host?.origin && this.context.page_referrer && new URL(this.context.page_referrer).hostname===new URL(grant.host.origin).hostname)delete this.context.page_referrer;
        // Entry signals outlive frame recreation: ready removes _gl from the
        // address bar before a later consent update. Never reuse them in a
        // different destination or processing scope of this controller.
        const signalScope=JSON.stringify([origin,grant.manifest.organization,grant.manifest.unit,grant.manifest.form_link,grant.manifest.processing_revision]);
        if(this.signalScope===undefined)this.directSignals=measurementSignals(input);
        else if(this.signalScope!==signalScope)this.directSignals={};
        this.signalScope=signalScope;
        this.consent=measurementConsent(grant.consent);
        if(!this.embedded)Object.assign(this.context,this.signals());
        this.grant=grant;this.hostIdentity=this.embedded?measurementHostIdentity(grant.hostIdentity,this.consent):{};this.origin=origin;this.instance=this.win.crypto.randomUUID();this.until=grant.expiresAt;
        const frame=this.frame=this.win.document.createElement('iframe');
        frame.hidden=true;frame.title='Measurement';frame.referrerPolicy='no-referrer';
        frame.setAttribute('sandbox','allow-scripts allow-same-origin');
        const url=new URL('/runtime',origin);url.searchParams.set('form',grant.manifest.form_link);url.searchParams.set('parent',this.win.location.origin);
        frame.src=url.href;this.win.document.body.append(frame);
        this.handshake=this.win.setTimeout(()=>{const mismatch=this.grant?.onMismatch;this.stop();mismatch?.();},8000);
        this.renew(this.until);
    }
    renew(until) {
        if(!this.grant)return;
        if(!this.frame?.isConnected){const mismatch=this.grant.onMismatch;this.stop();mismatch();return;}
        this.until=until;this.win.clearTimeout(this.expiry);
        this.expiry=this.win.setTimeout(()=>this.stop(),Math.max(0,until-Date.now()));
    }
    cleanLinker() {
        if(this.embedded)return;
        try {const url=new URL(this.win.location.href);url.searchParams.delete('_gl');this.win.history.replaceState(this.win.history.state,'',url);} catch { /* Measurement cannot affect checkout. */ }
    }
    signals() {const signals={...this.directSignals};if(!this.consent.analytics || !this.consent.marketing)delete signals._gl;return signals;}
    updateIdentity(hostIdentity) {
        this.hostIdentity=this.embedded?measurementHostIdentity(hostIdentity,this.consent):{};
        if(this.initialized)this.send('identity',{hostIdentity:this.hostIdentity});
    }
    // A later choice reaches tags as Consent Mode state. It never stops the frame.
    updateConsent(consent,hostIdentity) {
        this.consent=measurementConsent(consent);
        if(this.context){delete this.context._gl;if(!this.embedded)Object.assign(this.context,this.signals());}
        this.hostIdentity=this.embedded?measurementHostIdentity(hostIdentity,this.consent):{};
        if(this.initialized)this.send('consent',{consent:this.consent,hostIdentity:this.hostIdentity,signals:this.embedded?{}:this.signals()});
    }
    live() {return !!this.grant && !this.disposed && this.frame?.isConnected===true && Date.now()<this.until;}
    send(type,extra={}) {
        if(!this.live())return false;
        this.frame.contentWindow?.postMessage({namespace:measurementNamespace,protocol:measurementProtocol,type,instance:this.instance,
            generation:this.grant.generation,manifest:this.grant.manifest,...extra},this.origin);return true;
    }
    track(input) {const payload=analyticsPayload(input);return this.ready===true && measurementId(this.instance) && !!payload && this.send('event',{payload});}
    stop() {
        this.ready=false;this.initialized=false;this.grant=null;this.win.clearTimeout(this.expiry);this.win.clearTimeout(this.handshake);
        this.frame?.remove();this.frame=null;this.instance=null;
    }
    destroy() {this.stop();this.disposed=true;this.win.removeEventListener('message',this.onMessage);}
}
