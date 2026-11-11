import {scannerProductCaption,scannerProductTitle,scannerNotes,scannerTicketStatus} from './scanner_presentation.js';
import { AppConfig } from '../../app_config.js';
import { LocalizationService } from '../../services/localization_service.js';
import { icon } from './scan_icons.js';
import { tr, reasonText, escape as e } from './scan_strings.js';
export function scanResult(c, storageAvailable) {
    const t = c.ticket, state = c.state;
    if (state === 'ready') return `<div class="scan-empty"><span class="scan-empty-icon">${icon('ticket')}</span><h2>${tr('ready')}</h2><p>${tr('choose_input')}</p><div class="scan-steps"><span>1 · ${tr('scan')}</span><span>2 · ${tr('check_ticket')}</span><span>3 · ${tr('confirm')}</span></div></div>`;
    if (state === 'looking_up') return `<div class="scan-lookup" role="status"><span class="scan-spinner" aria-hidden="true"></span><h2>${tr('looking_up')}</h2></div>`;
    let message, tone = 'blocked';
    if (state === 'accepted') { message = tr('accepted'); tone = 'complete'; }
    else if (state === 'pending') { message = tr('pending'); tone = 'pending'; }
    else if (['sending','awaiting_server','persisting'].includes(state)) { message = tr(state); tone = 'pending'; }
    else if (state === 'blocked_schema') message = tr('blocked_schema');
    else if (state === 'blocked_auth') message = tr('blocked_auth');
    else if (['conflict','rejected'].includes(state)) {message = reasonText(c.operation?.receipt?.reason);if(c.operation?.receipt?.reason==='already_used')tone='used';}
    else if (c.error) message = reasonText(c.error);
    else {const status=scannerTicketStatus(t);message=tr(status.key==='valid_short'?'valid':status.key);tone=status.tone;}
    const fields = (t?.fields || []).filter(f => !['holder_name','spot','note'].includes(f.key) && f.default_visible && !(f.key==='note' && t.note) && !(f.hide_empty && (f.value == null || f.value === '')));
    const field = f => `<div><dt>${e(f.label)}</dt><dd>${f.missing ? tr('missing_field') : e(typeof f.value === 'object' ? JSON.stringify(f.value) : f.value)}</dd></div>`;
    const products=(t?.products||[]).filter(p=>!(t.spot && p.type==='spot' && scannerProductTitle(p).trim().toLocaleLowerCase()===p.type_title?.trim().toLocaleLowerCase()));
    const heading=t?.holder_name && t.holder_name!==t.symbol?t.holder_name:t?.purchaser_name||tr('ticket_label');
    const canConfirm = state === 'result' && t?.admission_allowed && storageAvailable && !(t.online_required && (!globalThis.navigator?.onLine || t.source === 'offline')) && !(t.source === 'offline' && t.requires_unpaid_confirmation);
    return `<div class="scan-result ${tone}"><div class="scan-result-status"><span class="scan-result-icon">${icon(tone==='allowed'||tone==='complete'?'check':tone==='pending'?'clock':tone==='used'?'ticket':'alert')}</span><h2 tabindex="-1" data-result-title>${e(message)}</h2></div>
    ${!t && c.scanSymbol ? `<p class="scan-ticket-code">${e(c.scanSymbol)}</p>` : ''}
    ${t ? `${t.source==='offline'?`<p class="scan-origin">${tr('source_offline')}</p>`:''}<h3>${e(heading)}</h3>${t.spot || t.spot_group?.title ? `<p class="scan-seat"><strong>${t.spot_group?.title?`${tr('table')} ${e(t.spot_group.title)}${t.spot?' · ':''}`:''}${t.spot?`${tr('spot')} ${e(t.spot)}`:''}</strong></p>` : ''}${t.purchaser_name && t.purchaser_name!==heading?`<p class="scan-purchaser">${tr('purchaser')}: <strong>${e(t.purchaser_name)}</strong></p>`:''}${t.symbol?`<p class="scan-ticket-code">${icon('ticket')}${e(t.symbol)}</p>`:''}
    ${t.requires_unpaid_confirmation ? `<p class="scan-payment"><strong>${tr('unpaid')}</strong>${t.remaining_amount != null ? `: ${e(t.remaining_amount)}` : ''}</p>` : ''}
    ${t.state === 'used' ? `<p>${e(new Date(t.updated_at).toLocaleString(LocalizationService.currentLocale))}</p>` : ''}
    ${products.length?`<ul class="scan-products">${products.map(p => `<li>${e(scannerProductCaption(p))}</li>`).join('')}</ul>`:''}
    ${scannerNotes(t)}
    <dl>${fields.slice(0,3).map(field).join('')}</dl>
    ${fields.length > 3 ? `<details><summary>${tr('more_fields')} (${Math.max(0,fields.length-3)})</summary><dl>${fields.slice(3).map(field).join('')}</dl></details>` : ''}` : ''}
    ${state === 'result' && AppConfig.isAppSupported && t?.source==='online' && t?.can_reset_password===true && globalThis.navigator?.onLine ? `<details><summary>${tr('reset_password')}</summary><form data-reset><label>${tr('new_password')}<input name="password" type="password" required autocomplete="new-password"></label><button>${tr('reset_password')}</button></form></details>` : ''}
    <div class="scan-actions">${canConfirm ? `${t.requires_unpaid_confirmation ? `<label class="scan-unpaid"><input type="checkbox" data-unpaid>${tr('confirm_unpaid')}</label>` : ''}<button class="scan-primary" data-confirm ${t.requires_unpaid_confirmation ? 'disabled' : ''}>${icon('check')}${tr('confirm')}</button>` : ''}
    <button data-next class="${canConfirm?'':'scan-primary'}" ${['persisting','awaiting_server'].includes(state)?'disabled':''}>${e(tr('next'))}</button>
    ${state==='sending' ? `<button data-retry>${tr('retry')}</button>` : ''}
</div></div>`;
}
