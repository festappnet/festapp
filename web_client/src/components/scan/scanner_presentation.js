import {tr,escape as e} from './scan_strings.js';
export const scannerTicketName=ticket=>ticket?.batch_title?.trim() || (ticket?.holder_name && ticket.holder_name!==ticket.symbol ? ticket.holder_name : '');
export const scannerProductTitle=product=>typeof product.short_title==='string'&&product.short_title.trim()?product.short_title.trim():product.title||'';
export function scannerProductCaption(product) {
    const label=product.type==='food'?(product.type_title||tr('dinner')):product.type!=='spot'?product.type_title:null;
    return (label?label+': ':'')+scannerProductTitle(product);
}
export function scannerNotes(ticket,{order=true,individual=true}={}) {
    const notes=[...(order?[[tr('order_note'),ticket?.order_note],[tr('order_internal_note'),ticket?.order_note_hidden]]:[]),...(individual?[[tr('ticket_note'),ticket?.note],[tr('hidden_note'),ticket?.note_hidden]]:[])];
    return notes.filter(([,value])=>typeof value==='string'&&value.trim()).map(([label,value])=>`<span class="scan-visible-note"><span>${e(label)}:</span> ${e(value.trim())}</span>`).join('');
}
