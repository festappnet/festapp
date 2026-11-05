import { LocalizationService } from '../../services/localization_service.js';
import { SupabaseService } from '../../services/supabase_service.js';
import { EmailSuffixConfirmation } from './email_suffix_confirmation.js';
export const saleOpeningText = key => LocalizationService.tr(`SaleOpening.${key}`);
export function consumeSaleOpeningLocation(location, history, doc = document) {
    if (globalThis.window?.location === location && window.__festappSaleOpeningLink) {
        const captured = JSON.parse(window.__festappSaleOpeningLink); delete window.__festappSaleOpeningLink; return captured;
    }
    const p = new URLSearchParams(location.hash.slice(1));
    if (!p.has('sale_opening')) return null;
    const meta = doc.createElement('meta'); meta.name = 'referrer'; meta.content = 'no-referrer'; doc.head.appendChild(meta);
    history.replaceState(history.state, '', location.pathname + location.search);
    const operation = p.get('sale_opening'), token = p.get('token');
    return operation === 'unsubscribe' && /^[a-f0-9]{64}$/.test(token || '') && p.getAll('token').length === 1
        ? { operation, token } : { operation: 'invalid' };
}
export async function saleOpeningCommand(operation, payload, client = SupabaseService.getClient()) {
    if (operation === 'subscribe') {
        const {data: config, error: configError} = await client.functions.invoke('sale-opening-notifications', {body: {operation: 'protection'}});
        if (configError || !config?.ok || !config?.siteKey || !globalThis.window?.FestappSaleOpeningProtection) throw new Error('failed');
        const botToken = await window.FestappSaleOpeningProtection.verify(config.siteKey, payload.formLink, payload.email);
        payload = {...payload, botToken};
    }
    const {data, error} = await client.functions.invoke('sale-opening-notifications', {body: {operation, ...payload}});
    if (error || data?.ok !== true) {
        let reason = data?.error;
        try { if (error?.context?.json) reason = (await error.context.json())?.error; } catch { /* controlled generic status */ }
        throw new Error(reason === 'invalid_link' ? 'invalid' : error?.context?.status === 429 ? 'tryLater' : 'failed');
    }
    return data;
}
export function renderSaleOpening(container, model, {preview = false, scope = null, command = saleOpeningCommand} = {}) {
    const doc = container.ownerDocument;
    const section = doc.createElement('section'); section.className = 'sale-opening-notification';
    const status = doc.createElement('p'); status.className = 'sale-opening-status'; status.setAttribute('role', 'status'); status.setAttribute('aria-live','polite');
    if (scope?.operation === 'invalid') { status.textContent = saleOpeningText('invalid'); section.append(status); container.append(section); return; }
    const form = doc.createElement('form'); form.className = 'sale-opening-form';
    const button = doc.createElement('button'); button.type = 'submit'; button.className = 'btn btn-primary';
    button.textContent = saleOpeningText(scope?.operation || 'notifyShort'); button.disabled = preview;
    let input; const suffixStates = new Map();
    if (!scope) {
        const field = doc.createElement('div'); field.className = 'sale-opening-email';
        input = doc.createElement('input'); input.type = 'email'; input.autocomplete = 'email'; input.name = 'sale-opening-email';
        input.required = true; input.maxLength = 320; input.disabled = preview; input.className = 'form-control';
        input.placeholder = saleOpeningText('email'); input.setAttribute('aria-label', saleOpeningText('email'));
        field.append(input); form.append(field);
    }
    form.append(button);
    form.addEventListener('submit', async event => {
        event.preventDefault(); if (preview || button.disabled) return;
        if (input && (!form.reportValidity() || !EmailSuffixConfirmation.validate(form, suffixStates))) return;
        const submittedEmail = input?.value.trim().toLowerCase();
        button.disabled = true; status.textContent = '';
        try {
            const result = await command(scope?.operation || 'subscribe', scope ? {token: scope.token} : {formLink: model.link, email: submittedEmail, lang: LocalizationService.currentLocale});
            form.hidden = true; status.textContent = scope ? saleOpeningText('unsubscribed') : saleOpeningText('subscribed').replace('{email}', () => submittedEmail);
        } catch (error) { status.textContent = saleOpeningText(['tryLater','invalid'].includes(error.message) ? error.message : 'failed'); button.disabled = false; }
    });
    section.append(form, status); container.append(section);
}
