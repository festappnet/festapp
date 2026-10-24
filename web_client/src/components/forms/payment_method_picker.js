import {paymentMethodText as text,paymentMethodRecipient,paymentMethodReservation} from './payment_method_strings.js';
export function renderPaymentMethodPicker(host,options,onChanged) {
    const state={selected:options.available[0]??null};
    host.replaceChildren();
    host.hidden=options.available.length===1&&state.selected==='bank';
    if(host.hidden){onChanged(state.selected);return state;}
    const choiceHost=document.createElement('fieldset');choiceHost.style.cssText='border:0;padding:0;min-width:0';
    const legend=document.createElement('legend');legend.textContent=text('title');choiceHost.append(legend);host.append(choiceHost);
    const detail=document.createElement('div');detail.style.cssText='overflow-wrap:anywhere';host.append(detail);
    const line=value=>{const p=document.createElement('p');p.textContent=value;detail.append(p);};
    const changed=()=>{
        detail.replaceChildren();
        if(state.selected==='stripe'){
            if(options.recipient?.name)line(paymentMethodRecipient(options.recipient.name));
            line(text('fullAmount'));line(paymentMethodReservation(options.reservationSeconds));line(text('stripeHint'));
        }
        if(options.stripeConfigured&&!options.available.includes('stripe'))line(text('reason_'+options.unavailableReason));
        if(!options.available.length){line(text('unavailable'));detail.setAttribute('role','alert');}
        onChanged(state.selected);
    };
    for(const method of options.available){
        if(options.available.length===1){const p=document.createElement('p');p.textContent=text(method);choiceHost.append(p);continue;}
        const label=document.createElement('label');label.className='deposit-option';label.style.cssText='min-height:44px;display:flex;align-items:center;gap:12px;overflow-wrap:anywhere';
        const radio=document.createElement('input');radio.type='radio';radio.name='payment_method';radio.value=method;radio.checked=state.selected===method;
        radio.addEventListener('change',()=>{state.selected=method;changed();});label.append(radio,document.createTextNode(text(method)));choiceHost.append(label);
    }
    changed();return state;
}
