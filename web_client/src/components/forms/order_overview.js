import { formLinkFromPath, replaceResolvedPublicLink } from '../../services/public_link.js';
import { LocalizationService } from '../../services/localization_service.js';
import { renderCardPaymentStatus, formatCardMoney } from './card_payment_status.js';
export const overviewText = key => LocalizationService.tr(`OrderOverview.${key}`);
export function parseOrderFragment(fragment) {
    if (!fragment?.startsWith('#order?')) return null;
    const params = new URLSearchParams(fragment.slice(7));
    const token = params.get('token');
    const id = params.get('order_id');
    if (!/^[a-f0-9]{64}$/.test(token || '') || !/^[1-9][0-9]*$/.test(id || '') || !Number.isSafeInteger(Number(id))) throw new Error('INVALID_CAPABILITY');
    return { token, orderId: Number(id) };
}
const line = (parent, tag, text) => {
    const node = document.createElement(tag); node.textContent = text;
    if (tag === 'button') {
        node.className = 'btn btn-outline-secondary';
        node.style.cssText = 'font:inherit;min-height:44px;max-width:100%;white-space:normal;overflow-wrap:anywhere';
    }
    parent.appendChild(node); return node;
};
const money = (value, currency) => value == null ? overviewText('unknown') : `${value} ${currency || ''}`;
export function renderOrderOverview(host, data, onRefresh, onContinue, offerInPage = false) {
    host.replaceChildren();
    host.style.cssText = 'max-width:850px;margin:0 auto;padding:20px;overflow-wrap:anywhere';
    const heading = line(host, 'h1', `${data.root.title || ''} - ${data.root.symbol}`);
    if (!offerInPage) { heading.tabIndex = -1; heading.focus(); }
    line(host, 'p', `${overviewText('updated')}: ${new Date(data.serverTime).toLocaleString()}`);
    const refresh = line(host, 'button', overviewText('refresh')); refresh.type = 'button'; refresh.onclick = onRefresh;
    const people = line(host, 'section', '');
    line(people, 'h2', overviewText('people'));
    for (const person of data.people) line(people, 'p', `${person.label || `#${person.id}`} - ${overviewText(person.effectiveLifecycle)}`);
    for (const offer of data.offers) {
        line(host, 'p', `${overviewText(offer.effectiveStatus)}: ${offer.pendingPlaces} - ${new Date(offer.expiresAt).toLocaleString()}`);
    }
    if (onContinue) { const button = line(host, 'button', overviewText('continue')); button.type = 'button'; button.onclick = onContinue; }
    else if (!offerInPage && data.offers.some(o => o.pendingPlaces > 0)) line(host, 'p', overviewText('offerEmail'));
    for (const order of data.orders) {
        const card = line(host, 'section', ''); card.style.cssText = 'padding:16px;margin:16px 0;border:1px solid #aaa;border-radius:8px';
        line(card, 'h2', order.symbol);
        line(card, 'p', `${overviewText('orderState')}: ${overviewText(order.state)}`);
        line(card, 'p', `${overviewText('total')}: ${order.payment?.method === 'stripe' ? formatCardMoney(order.total, order.currency) ?? overviewText('unknown') : money(order.total, order.currency)}`);
        for (const item of order.items || []) {
            const row = line(card, 'p', `${item.title || ''}: ${money(item.price, item.currency)}`);
            const seating = [[overviewText('table'), item.spotGroupTitle], [overviewText('seat'), item.spotTitle]]
                .filter(([, value]) => value != null && String(value).trim() !== '')
                .map(([label, value]) => `${label}: ${value}`).join(' · ');
            if (seating) { const details = line(row, 'span', seating); details.style.cssText = 'display:block;margin-top:4px;font-weight:600'; }
        }
        const payment = order.payment;
        if (payment?.method === 'stripe') {
            const statusHost = line(card, 'section', '');
            renderCardPaymentStatus(statusHost, { ...payment, currency: order.currency }, { onRefresh });
        } else if (payment) {
            line(card, 'h3', overviewText(payment.status));
            for (const key of ['received', 'totalOutstanding', 'returned', 'overpaid']) {
                line(card, 'p', `${overviewText(key)}: ${money(payment[key], order.currency)}`);
            }
            if (payment.instructionsAvailable) {
                line(card, 'p', `${overviewText('dueNow')}: ${money(payment.dueNow, order.currency)}`);
                line(card, 'p', `${overviewText('dueAt')}: ${payment.dueAt ? new Date(payment.dueAt).toLocaleString() : overviewText('onSite')}`);
                if (payment.overdue) line(card, 'p', overviewText('overdue'));
                line(card, 'p', `${overviewText('account')}: ${payment.publicAccount}`);
                line(card, 'p', `${payment.referenceKind}: ${payment.reference}`);
            }
        }
        for (const ticket of data.root.hasTickets === false ? [] : order.tickets) line(card, 'p', `${ticket.label || `#${ticket.id}`} - ${overviewText(ticket.displayStatus)}`);
    }
}

export async function loadOrderOverview(host, commands, scope, onContinue, offerInPage = false, onIdentity = () => {}) {
    onIdentity(null);
    const generation = (host._overviewGeneration || 0) + 1; host._overviewGeneration = generation;
    host.replaceChildren(); host.setAttribute('aria-busy', 'true');
    line(host, 'p', overviewText('loading'));
    try {
        const data = await commands.overview(scope);
        if (host._overviewGeneration !== generation) return;
        onIdentity(data.organizationIdentity);
        replaceResolvedPublicLink('form', formLinkFromPath(window.location.pathname), data.root?.formLink);
        renderOrderOverview(host, data, () => loadOrderOverview(host, commands, scope, onContinue, offerInPage, onIdentity),
            onContinue && data.offers.some(o => o.pendingPlaces > 0) ? onContinue : null, offerInPage);
        return data;
    } catch {
        if (host._overviewGeneration !== generation) return;
        host.replaceChildren(); line(host, 'p', overviewText('failed')).setAttribute('role', 'alert');
        const retry = line(host, 'button', overviewText('refresh')); retry.type = 'button';
        retry.onclick = () => loadOrderOverview(host, commands, scope, onContinue, offerInPage, onIdentity);
    } finally { if (host._overviewGeneration === generation) host.removeAttribute('aria-busy'); }
}
