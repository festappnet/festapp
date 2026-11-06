import {isCardPaymentMethod, paymentConnectors} from './payment_connector_registry.js';
import {paymentMethodText as text,paymentMethodRecipient,paymentMethodReservation} from './payment_method_strings.js';
export function renderPaymentMethodPicker(host,options,onChanged) {
    host.hidden=false;
    const state={selected:options.available[0]??null};
    const choiceHost=document.createElement('fieldset');choiceHost.style.cssText='border:0;padding:0;min-width:0';
    const legend=document.createElement('legend');legend.textContent=text('title');choiceHost.append(legend);host.append(choiceHost);
    const detail=document.createElement('div');detail.style.cssText='overflow-wrap:anywhere';host.append(detail);
    const line=value=>{const p=document.createElement('p');p.textContent=value;detail.append(p);};
    const changed=()=>{
        detail.replaceChildren();
        if(isCardPaymentMethod(state.selected)){
            const recipient=options.providers[state.selected]?.recipient;
            if(recipient?.name)line(paymentMethodRecipient(recipient.name));
            line(text('fullAmount'));line(paymentMethodReservation(options.reservationSeconds));line(text(paymentConnectors.get(state.selected).hintKey));
        }
        if(options.cardConfigured&&!options.available.some(isCardPaymentMethod))line(text('reason_'+options.unavailableReason));
        if(!options.available.length){line(text('unavailable'));detail.setAttribute('role','alert');}
        const bankOnly=options.available.length===1&&state.selected==='bank';
        choiceHost.hidden=bankOnly;
        host.hidden=bankOnly&&detail.childElementCount===0;
        onChanged(state.selected);
    };
    for(const method of options.available){
        if(options.available.length===1){const p=document.createElement('p');p.textContent=text(paymentConnectors.get(method)?.labelKey ?? method);choiceHost.append(p);continue;}
        const label=document.createElement('label');label.className='deposit-option';label.style.cssText='min-height:44px;display:flex;align-items:center;gap:12px;overflow-wrap:anywhere';
        const radio=document.createElement('input');radio.type='radio';radio.name='payment_method';radio.value=method;radio.checked=state.selected===method;
        radio.addEventListener('change',()=>{state.selected=method;changed();});label.append(radio,document.createTextNode(text(paymentConnectors.get(method)?.labelKey ?? method)));choiceHost.append(label);
    }
    changed();return state;
}
