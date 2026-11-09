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
export function renderSaleOpening(container, model, {preview = false, scope = null, command = saleOpeningCommand, analytics = null} = {}) {
    const doc = container.ownerDocument;
    const section = doc.createElement('section'); section.className = 'sale-opening-notification';
    const status = doc.createElement('p'); status.className = 'sale-opening-status'; status.setAttribute('role', 'status'); status.setAttribute('aria-live','polite');
    if (scope?.operation === 'invalid') { status.textContent = saleOpeningText('invalid'); section.append(status); container.append(section); return; }
    const form = doc.createElement('form'); form.className = 'sale-opening-form';
    const button = doc.createElement('button'); button.type = 'submit'; button.className = 'btn btn-primary';
    const buttonLabel = saleOpeningText(scope?.operation || 'notifyShort');
    button.textContent = buttonLabel; button.disabled = preview;
    let pending = false, completed = false;
    let input; const suffixStates = new Map();
    if (!scope) {
        const field = doc.createElement('div'); field.className = 'sale-opening-email';
        input = doc.createElement('input'); input.type = 'email'; input.autocomplete = 'email'; input.name = 'sale-opening-email';
        input.required = true; input.maxLength = 320; input.disabled = preview; input.className = 'form-control';
        input.placeholder = saleOpeningText('email'); input.setAttribute('aria-label', saleOpeningText('email'));
        input.addEventListener('input', () => { if (!preview) analytics?.started(); });
        field.append(input); form.append(field);
    }
    form.append(button);
    form.addEventListener('submit', async event => {
        event.preventDefault(); if (preview || pending || completed) return;
        if (input && (!form.reportValidity() || !EmailSuffixConfirmation.validate(form, suffixStates))) return;
        const submittedEmail = input?.value.trim().toLowerCase();
        let measured;
        try { if (!scope) measured=analytics?.captureSaleOpening(submittedEmail); } catch { /* Measurement cannot affect subscription. */ }
        pending = true;
        button.disabled = true;
        if (input) input.disabled = true;
        form.setAttribute('aria-busy', 'true');
        button.textContent = LocalizationService.tr('Common.processing');
        status.textContent = ''; delete status.dataset.state;
        try {
            await command(scope?.operation || 'subscribe', scope ? {token: scope.token} : {formLink: model.link, email: submittedEmail, lang: LocalizationService.currentLocale});
            completed = true;
            status.dataset.state = 'success';
            try { measured?.(); } catch { /* Measurement cannot affect subscription. */ }
            form.hidden = true; status.textContent = scope ? saleOpeningText('unsubscribed') : saleOpeningText('subscribed').replace('{email}', () => submittedEmail);
        } catch (error) {
            status.dataset.state = 'error';
            status.textContent = saleOpeningText(['tryLater','invalid'].includes(error.message) ? error.message : 'failed');
        } finally {
            pending = false;
            form.removeAttribute('aria-busy');
            button.textContent = buttonLabel;
            button.disabled = completed;
            if (input) input.disabled = completed;
        }
    });
    section.append(form, status); container.append(section);
}
