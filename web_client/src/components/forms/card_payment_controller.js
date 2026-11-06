import {SupabaseService} from '../../services/supabase_service.js';
import {paymentConnectors} from './payment_connector_registry.js';

/** Owns the separate payment capability. Safe overview DTOs cannot create it. */
export class CardPaymentController {
    static fromResult(result,options={}) {
        const access=result?.payment_access;
        if(access?.kind && access.kind !== 'pay')return null;
        const token=access?.token;
        const connector=(options.registry??paymentConnectors).get(result?.payment?.method);
        if(!connector||typeof token!=='string'||!/^[a-f0-9]{64}$/.test(token))return null;
        try{
            const url=new URL(result.payment_access.url);
            if(url.protocol!=='https:'||url.username||url.password||url.search||!url.pathname.endsWith(connector.payPath)||url.hash!==`#pay=${token}`)return null;
            return new CardPaymentController(token,url,result.payment,options);
        }catch{return null;}
    }
    constructor(token,url,payment,{invoke,onPayment=()=>{},navigate=url=>window.location.assign(url),remember,registry=paymentConnectors}={}) {
        Object.assign(this,{token,url,payment,onPayment,navigate,remember,busy:false,disposed:false});
        this.connector=registry.get(payment?.method);
        if(!this.connector)throw new Error('payment_connector_unavailable');
        this.invoke=invoke??(async body=>{
            const {data,error}=await SupabaseService.getClient().functions.invoke('payment-checkout',{body:{...body,provider:this.connector.id}});
            if(error)throw new Error('payment_unavailable');
            return data;
        });
        this.resume=()=>{if(typeof document==='undefined'||document.visibilityState==='visible')this.refresh().catch(()=>{});};
        if(typeof window!=='undefined')window.addEventListener('pageshow',this.resume);
        if(typeof document!=='undefined')document.addEventListener('visibilitychange',this.resume);
    }
    async _request(action) {
        if(this.busy||this.disposed)return null;
        this.busy=true;
        try{
            const result=await this.invoke({token:this.token,action});
            if(this.disposed)return null;
            if(result?.payment?.method!==this.connector.id)throw new Error('payment_unavailable');
            this.payment=result.payment;this.onPayment(this.payment);return result;
        }catch(error){
            if(!this.disposed){this.payment={...this.payment,status:'unknown',allowedActions:['refresh']};this.onPayment(this.payment);}
            throw error;
        }finally{this.busy=false;}
    }
    async refresh(){await this._request('status');}
    async continue(){const result=await this._request('prepare');if(result?.checkoutUrl)this.openPrepared(result.checkoutUrl);}
    openPrepared(value) {
        if(this.disposed||this.payment?.status!=='open')return;
        const target=this.connector.validateCheckoutUrl(value);
        if(this.remember)this.remember(this.token,this.url);
        else if(this.url.origin===window.location.origin){
            window.history.replaceState({...window.history.state,[this.connector.historyKey]:{provider:this.connector.id,kind:'pay',token:this.token}},'',this.url.pathname);
        }
        this.navigate(target);
    }
    dispose(){this.disposed=true;this.token=null;if(typeof window!=='undefined')window.removeEventListener('pageshow',this.resume);if(typeof document!=='undefined')document.removeEventListener('visibilitychange',this.resume);}
}
