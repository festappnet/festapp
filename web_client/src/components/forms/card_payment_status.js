import { formatDisplayNumber } from '../../utils/formatters.js';
import { LocalizationService } from '../../services/localization_service.js';
export const cardPaymentText = key => LocalizationService.tr(`CardPayments.${key}`);
const states = new Set(['preparing', 'open', 'pending', 'declined', 'paid', 'expired', 'action_required', 'refund_pending', 'partially_refunded', 'refunded', 'disputed']);
const payable = new Set(['open', 'declined', 'preparing']);
export function formatCardMoney(value, currency, locale = LocalizationService.currentLocale) {
    if (!/^[A-Z]{3}$/.test(currency || '') || value == null || !/^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$/.test(String(value))) return null;
    try { return formatDisplayNumber(Number(value), locale, { style: 'currency', currency }); }
    catch { return null; }
}
export function cardPaymentState(payment) {
    return states.has(payment?.status) ? payment.status : 'unknown';
}
export function canContinueCardPayment(payment) {
    return payment?.method === 'stripe' && payable.has(cardPaymentState(payment)) &&
        payment.admissionState !== 'hold' && payment.admissionState !== 'revoked' &&
        Array.isArray(payment.allowedActions) && payment.allowedActions.includes('pay');
}
/** Presentation only. A safe read DTO never supplies a write capability or Checkout URL.
 * An authorized owner may supply onPay separately, using its privately-held pay scope.
 */
export function renderCardPaymentStatus(host, payment, { onPay, onRefresh, locale = LocalizationService.currentLocale } = {}) {
    host.replaceChildren();
    host.classList.add('card-payment-status');
    host.style.cssText = 'display:flex;flex-direction:column;gap:16px;min-width:0;overflow-wrap:anywhere;text-align:start';
    const style = document.createElement('style');
    style.textContent = `
        .card-payment-status p, .card-payment-status h3 { margin: 0; }
        .card-payment-status button, .card-payment-close {
            font: inherit; color: var(--primary-color); border: 1px solid var(--primary-color);
            background: var(--surface-color); border-radius: var(--radius-sm, 10px);
            padding: 12px 16px; min-height: 44px; max-width: 100%; white-space: normal;
            overflow-wrap: anywhere; cursor: pointer;
        }
        .card-payment-status button:focus-visible, .card-payment-close:focus-visible {
            outline: 2px solid var(--primary-color); outline-offset: 4px;
        }
        .card-payment-status button:disabled { cursor: wait; }
        .card-payment-close { margin-block-start: 24px; }
    `;
    host.append(style);
    const line = (tag, value) => { const el = document.createElement(tag); el.textContent = value; host.append(el); return el; };
    const state = cardPaymentState(payment);
    line('h3', cardPaymentText('title'));
    const status = line('p', cardPaymentText(state)); status.setAttribute('role', 'status'); status.setAttribute('aria-atomic', 'true');
    const money = value => formatCardMoney(value, payment.currency, locale);
    for (const key of ['amount', 'received', 'returned']) {
        const formatted = money(payment?.[key]);
        if (formatted != null) line('p', `${cardPaymentText(key)}: ${formatted}`);
    }
    if (payment?.reservationExpiresAt && ['open', 'declined'].includes(state)) {
        const date = new Date(payment.reservationExpiresAt);
        if (!Number.isNaN(date.getTime())) line('p', `${cardPaymentText('reservation')}: ${date.toLocaleString(locale)}`);
    }
    if (payment?.admissionState === 'hold' && state !== 'disputed') line('p', cardPaymentText('admissionHold'));
    const deliveryLine = state === 'paid' ? line('p', '') : null;
    const updateDelivery = delivery => {
        if (deliveryLine) deliveryLine.textContent = cardPaymentText(['failed', 'suppressed', 'dead', 'invalid_email'].includes(delivery) ? 'emailFailed' : ['accepted', 'delivered'].includes(delivery) ? 'emailAccepted' : delivery === 'not_requested' ? 'emailNotRequested' : 'emailPending');
    };
    updateDelivery(payment?.deliveryState);
    const button = (label, action) => {
        const el = line('button', cardPaymentText(label)); el.type = 'button';
        el.dataset.paymentAction=label;
        el.className = 'btn btn-outline-secondary';
        el.style.cssText = 'min-height:44px;white-space:normal;overflow-wrap:anywhere';
        el.onclick = async () => {
            el.disabled = true;
            let uncertain = false;
            try { await action(); }
            catch { uncertain = label === 'continuePayment'; status.textContent = cardPaymentText('unknown'); }
            finally { if (el.isConnected && !uncertain) el.disabled = false; }
        };
    };
    if (canContinueCardPayment(payment)) {
        if (typeof onPay === 'function') button('continuePayment', onPay);
        else line('p', cardPaymentText('protectedPaymentLink'));
    } else if (payable.has(state)) line('p', cardPaymentText('protectedPaymentLink'));
    if (typeof onRefresh === 'function') button('refresh', onRefresh);
    return { updateDelivery };
}
