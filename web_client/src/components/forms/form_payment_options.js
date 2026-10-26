export function formPaymentOptions(value,surface='web') {
    if(value==null)return {available:['bank'],stripeConfigured:false,reservationSeconds:1860,recipient:null};
    const reasons=new Set(['not_configured','paused','stripe_restricted','model_unverified','recipient_changed','payments_disabled','return_origin_unavailable','currency_unsupported','deposit_unsupported','surcharge_unsupported','fakturoid_unsupported','sale_ending','surface_unverified','organizer_unavailable']);
    const configured=value.configured?.stripe===true;
    const recipient=typeof value.recipient?.connectionId==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value.recipient.connectionId)?{connectionId:value.recipient.connectionId,name:typeof value.recipient.name==='string'?value.recipient.name:null}:null;
    const available=[...new Set(Array.isArray(value.available)?value.available.filter(x=>x==='bank'||x==='stripe'):[])];
    const surfaceAllowed=Array.isArray(value.supportedSurfaces)&&value.supportedSurfaces.includes(surface);
    return {available:available.filter(method=>method!=='stripe'||(recipient&&surfaceAllowed)),stripeConfigured:configured,
        reservationSeconds:Number.isInteger(value.reservationSeconds)&&value.reservationSeconds>0?value.reservationSeconds:1860,recipient,
        unavailableReason:available.includes('stripe')&&!surfaceAllowed?'surface_unverified':reasons.has(value.stripeUnavailableReason)?value.stripeUnavailableReason:'unavailable'};
}
