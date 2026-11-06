import {paymentConnectors} from './payment_connector_registry.js';
export function formPaymentOptions(value,surface='web',registry=paymentConnectors) {
    if(value==null)return {available:['bank'],cardConfigured:false,reservationSeconds:1860,recipient:null,providers:{}};
    const providers=Object.fromEntries(registry.values().map(connector=>[connector.id,connector.availability(value,surface)]));
    const available=[...new Set(Array.isArray(value.available)?value.available.filter(method=>method==='bank'||providers[method]?.available):[])];
    const selected=available.find(method=>method!=='bank');
    const fallback=Object.values(providers).find(provider=>provider.configured);
    return {available,providers,cardConfigured:Object.values(providers).some(provider=>provider.configured),
        reservationSeconds:Number.isInteger(value.reservationSeconds)&&value.reservationSeconds>0?value.reservationSeconds:1860,
        recipient:providers[selected]?.recipient??fallback?.recipient??null,
        unavailableReason:fallback?.unavailableReason??'unavailable'};
}
