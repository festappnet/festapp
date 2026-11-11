import {tr,escape as e} from './scan_strings.js';
export const scannerProductTitle=product=>typeof product.short_title==='string'&&product.short_title.trim()?product.short_title.trim():product.title||'';
export function scannerProductCaption(product) {
    const label=product.type==='food'?(product.type_title||tr('dinner')):product.type!=='spot'?product.type_title:null;
    return (label?label+': ':'')+scannerProductTitle(product);
}
export function scannerNotes(ticket,{order=true,individual=true}={}) {
    const notes=[...(order?[[tr('order_note'),ticket?.order_note],[tr('order_internal_note'),ticket?.order_note_hidden]]:[]),...(individual?[[tr('ticket_note'),ticket?.note],[tr('hidden_note'),ticket?.note_hidden]]:[])];
    return notes.filter(([,value])=>typeof value==='string'&&value.trim()).map(([label,value])=>`<span class="scan-visible-note"><span>${e(label)}:</span> ${e(value.trim())}</span>`).join('');
}

// Presentation only. Admission always uses the authoritative lookup and controller.
export function scannerTicketStatus(ticket) {
    if(ticket?.state==='storno')return {key:'ticket_cancelled',tone:'blocked',icon:'alert'};
    if(ticket?.state==='used')return {key:'already_used',tone:'used',icon:'ticket'};
    if(ticket?.order_state==='storno')return {key:'ticket_cancelled',tone:'blocked',icon:'alert'};
    if(ticket?.state==='waitlisted')return {key:'ticket_waitlisted',tone:'pending',icon:'clock'};
    if(ticket?.state==='ordered' || ticket?.requires_unpaid_confirmation)return {key:'unpaid',tone:'pending',icon:'clock'};
    if(ticket?.admission_allowed)return {key:'valid_short',tone:'allowed',icon:'ticket_check'};
    return {key:'not_allowed',tone:'blocked',icon:'alert'};
}
export function scannerSearchPreview(ticket) {
    const status=scannerTicketStatus(ticket);
    const holder=ticket.holder_name && ticket.holder_name!==ticket.symbol?ticket.holder_name:null;
    const heading=holder || ticket.purchaser_name || tr('ticket_label');
    const table=ticket.spot_group?.title;
    const products=(ticket.products||[]).filter(product=>!(ticket.spot && product.type==='spot' && scannerProductTitle(product).trim().toLocaleLowerCase()===product.type_title?.trim().toLocaleLowerCase()));
    return `<span class="scan-search-heading"><strong>${e(heading)}</strong>${ticket.state?`<span class="scan-ticket-status ${status.tone}">${e(tr(status.key))}</span>`:''}</span>
    ${ticket.purchaser_name && ticket.purchaser_name!==heading?`<span class="scan-search-customer">${tr('purchaser')}: ${e(ticket.purchaser_name)}</span>`:''}
    ${table || ticket.spot?`<span class="scan-search-seat">${table?`${/^\d+$/.test(table)?tr('table')+' ':''}${e(table)}`:''}${table && ticket.spot?' · ':''}${ticket.spot?`${tr('spot')} ${e(ticket.spot)}`:''}</span>`:''}
    ${products.length?`<span class="scan-search-products">${products.map(product=>`<span>${e(scannerProductCaption(product))}</span>`).join('')}</span>`:''}
    ${ticket.symbol?`<span class="scan-search-code">${e(ticket.symbol)}</span>`:''}`;
}
