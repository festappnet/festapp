import {scannerProductCaption,scannerNotes} from './scanner_presentation.js';
import { AppConfig } from '../../app_config.js';
import { LocalizationService } from '../../services/localization_service.js';
import { icon } from './scan_icons.js';
import { tr, reasonText, escape as e } from './scan_strings.js';
export function scanResult(c, storageAvailable) {
    const t = c.ticket, state = c.state;
    if (state === 'ready') return `<div class="scan-empty"><span class="scan-empty-icon">${icon('ticket')}</span><h2>${tr('ready')}</h2><p>${tr('choose_input')}</p><div class="scan-steps"><span>1 · ${tr('scan')}</span><span>2 · ${tr('check_ticket')}</span><span>3 · ${tr('confirm')}</span></div></div>`;
    if (state === 'looking_up') return `<div class="scan-empty" role="status"><span class="scan-spinner"></span><h2>${tr('looking_up')}</h2></div>`;
    let message, tone = 'blocked';
    if (state === 'accepted') { message = tr('accepted'); tone = 'complete'; }
    else if (state === 'pending') { message = tr('pending'); tone = 'pending'; }
    else if (['sending','awaiting_server','persisting'].includes(state)) { message = tr(state); tone = 'pending'; }
    else if (state === 'blocked_schema') message = tr('blocked_schema');
    else if (state === 'blocked_auth') message = tr('blocked_auth');
    else if (['conflict','rejected'].includes(state)) {message = reasonText(c.operation?.receipt?.reason);if(c.operation?.receipt?.reason==='already_used')tone='used';}
    else if (c.error) message = reasonText(c.error);
    else if (t?.state === 'used') {message = tr('already_used');tone='used';}
    else if (t?.requires_unpaid_confirmation) message = tr('unpaid');
    else if (t?.admission_allowed) { message = tr('valid'); tone = 'allowed'; }
    else message = tr('not_allowed');
    const fields = (t?.fields || []).filter(f => !['holder_name','spot','note'].includes(f.key) && f.default_visible && !(f.key==='note' && t.note) && !(f.hide_empty && (f.value == null || f.value === '')));
    const field = f => `<div><dt>${e(f.label)}</dt><dd>${f.missing ? tr('missing_field') : e(typeof f.value === 'object' ? JSON.stringify(f.value) : f.value)}</dd></div>`;
    const canConfirm = state === 'result' && t?.admission_allowed && storageAvailable && !(t.online_required && (!globalThis.navigator?.onLine || t.source === 'offline')) && !(t.source === 'offline' && t.requires_unpaid_confirmation);
    const busy = ['persisting','awaiting_server','looking_up'].includes(state) || (['sending','pending'].includes(state) && !c.offlineReady);
    return `<div class="scan-result ${tone}"><div class="scan-result-status"><span class="scan-result-icon">${icon(tone==='allowed'||tone==='complete'?'check':tone==='pending'?'clock':tone==='used'?'ticket':'alert')}</span><h2 tabindex="-1" data-result-title>${e(message)}</h2></div>
    ${!t && c.inGroup && c.scanSymbol ? `<p class="scan-ticket-code">${e(c.scanSymbol)}</p>` : ''}
    ${t ? `<p class="scan-origin">${tr(t.source === 'offline' ? 'source_offline' : 'source_online')}</p><h3>${e(t.holder_name && t.holder_name!==t.symbol?t.holder_name:tr('ticket_label'))}</h3>${t.purchaser_name?`<p class="scan-purchaser">${tr('purchaser')}: <strong>${e(t.purchaser_name)}</strong></p>`:''}<p class="scan-ticket-code">${icon('ticket')}${e(t.symbol)}</p>
    ${t.requires_unpaid_confirmation ? `<p class="scan-payment"><strong>${tr('unpaid')}</strong>${t.remaining_amount != null ? `: ${e(t.remaining_amount)}` : ''}</p>` : ''}
    ${t.state === 'used' ? `<p>${e(new Date(t.updated_at).toLocaleString(LocalizationService.currentLocale))}</p>` : ''}
    <ul class="scan-products">${t.products.length ? t.products.map(p => `<li>${e(scannerProductCaption(p))}</li>`).join('') : `<li>${tr('no_products')}</li>`}</ul>
    ${!c.inGroup?scannerNotes(t):''}
    ${t.spot ? `<p>${tr('spot')}: ${e(t.spot)}</p>` : ''}<dl>${fields.slice(0,3).map(field).join('')}</dl>
    ${fields.length > 3 ? `<details><summary>${tr('more_fields')} (${Math.max(0,fields.length-3)})</summary><dl>${fields.slice(3).map(field).join('')}</dl></details>` : ''}` : ''}
    ${state === 'result' && AppConfig.isAppSupported && t?.source==='online' && t?.can_reset_password===true && globalThis.navigator?.onLine ? `<details><summary>${tr('reset_password')}</summary><form data-reset><label>${tr('new_password')}<input name="password" type="password" required autocomplete="new-password"></label><button>${tr('reset_password')}</button></form></details>` : ''}
    <div class="scan-actions">${canConfirm ? `${t.requires_unpaid_confirmation ? `<label class="scan-unpaid"><input type="checkbox" data-unpaid>${tr('confirm_unpaid')}</label>` : ''}<button class="${c.inGroup && !t.requires_unpaid_confirmation?'':'scan-primary'}" data-confirm ${t.requires_unpaid_confirmation ? 'disabled' : ''}>${icon('check')}${tr(c.inGroup?'confirm_one':'confirm')}</button>` : ''}
    ${state==='sending' ? `<button data-retry>${tr('retry')}</button>` : ''}
    ${!busy && !c.inGroup ? `<button class="${canConfirm ? '' : 'scan-primary'}" data-next>${tr(canConfirm ? 'back_to_scan' : 'next')}${!canConfirm ? icon('arrow') : ''}</button>` : ''}</div></div>`;
}
