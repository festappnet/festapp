import {measurementProtocol} from './form_measurement_contract.js';
import {analyticsPayload, attributionContext, measurementId, measurementNamespace, measurementOrigin, sameMeasurementManifest} from './form_measurement_contract.js';

// Mechanical isolated transport. Only the session supplies a grant.
export class FormMeasurementRuntime {
    constructor({win=window, model, campaign=()=>({}), local=false}) {
        Object.assign(this,{win,model,campaign,local});
        this.onMessage=event=>{
            const data=event.data, grant=this.grant;
            if(!grant || !this.live() || event.source!==this.frame?.contentWindow || event.origin!==this.origin ||
                data?.namespace!==measurementNamespace || data.protocol!==measurementProtocol) return;
            if(!sameMeasurementManifest(data.manifest,grant.manifest)) {const mismatch=grant.onMismatch;this.stop();mismatch();return;}
            if(data.type==='ready' && !this.ready) {this.initialized=this.send('init',{context:this.context,consent:this.consent});}
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
            page_location:new URL('/form/'+grant.manifest.form_link,this.win.location.origin).href,page_referrer:this.win.document.referrer};
        this.context=attributionContext(input);if(!this.context)return;
        this.grant=grant;this.consent=grant.consent;this.origin=origin;this.instance=this.win.crypto.randomUUID();this.until=grant.expiresAt;
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
    // A later choice reaches tags as Consent Mode state. It never stops the frame.
    updateConsent(consent) {this.consent=consent;if(this.initialized)this.send('consent',{consent});}
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
