import { renderOverviewProducts, renderOverviewCustomer, renderOverviewAnswers, renderOverviewChanges } from './order_overview_details.js';
import { renderPaymentDetails } from './payment_details.js';
import { presentPayment } from '../../../../supabase/functions/_shared/paymentPresentation.ts';
import { LocalizationService } from '../../services/localization_service.js';
export const overviewText = key => LocalizationService.tr(`OrderOverview.${key}`);
export function parseOrderLocation(location) {
    if (location.pathname !== '/order' || location.hash) return null;
    const params = new URLSearchParams(location.search || '');
    if (params.get('waitlist') === '1') return null;
    if (!params.has('order_id') && !params.has('token')) return null;
    const token = params.get('token');
    const id = params.get('order_id');
    if (params.getAll('token').length !== 1 || params.getAll('order_id').length !== 1 ||
        !/^[a-f0-9]{64}$/.test(token || '') || !/^[1-9][0-9]*$/.test(id || '') || !Number.isSafeInteger(Number(id))) throw new Error('INVALID_CAPABILITY');
    return { token, orderId: Number(id) };
}
export const orderOverviewSearch = scope => `?${new URLSearchParams({ order_id: String(scope.orderId), token: scope.token })}`;
const line = (parent, tag, text) => {
    const node = document.createElement(tag); node.textContent = text; parent.appendChild(node); return node;
};
const date = value => value ? new Date(value).toLocaleString(LocalizationService.currentLocale, { dateStyle: 'medium', timeStyle: 'short' }) : overviewText('unknown');
const money = (value, currency) => value == null ? overviewText('unknown') : new Intl.NumberFormat(LocalizationService.currentLocale, currency ? { style: 'currency', currency: currency.trim() } : {}).format(value);
function section(host, title, className = '') {
    const element = line(host, 'section', ''); element.className = className;
    line(element, 'h2', title); return element;
}
function fact(list, label, value) {
    const row = line(list, 'div', ''); line(row, 'dt', label); line(row, 'dd', value);
}
function renderOrderState(host, order, includeReference = true, hasTickets = false) {
    const payment = order.payment;
    const state = order.state === 'storno' ? 'cancelled' : payment?.status || order.state;
    const complete = ['fully_paid', 'free'].includes(state);
    const overdue = payment?.instructionsAvailable && payment.overdue && !complete;
    const cancelled = state === 'cancelled';
    const row = line(host, 'div', '');
    row.className = `overview-state-row overview-state-${complete ? 'complete' : cancelled ? 'cancelled' : overdue ? 'overdue' : 'pending'}`;
    const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    icon.setAttribute('viewBox', '0 0 24 24'); icon.setAttribute('aria-hidden', 'true');
    icon.classList.add('overview-state-icon');
    const shape = document.createElementNS(icon.namespaceURI, 'path');
    shape.setAttribute('d', complete ? 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20ZM10 17l-5-5 1.4-1.4L10 14.2l7.6-7.6L19 8Z' : cancelled ? 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20ZM7 6l5 5 5-5 1 1-5 5 5 5-1 1-5-5-5 5-1-1 5-5-5-5Z' : overdue ? 'M1 21h22L12 2ZM11 8h2v7h-2Zm0 9h2v2h-2Z' : 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20ZM11 6h2v6l4 2-1 2-5-3Z');
    shape.setAttribute('fill-rule', 'evenodd'); icon.appendChild(shape); row.appendChild(icon);
    const text = line(row, 'div', '');
    if (includeReference) line(text, 'p', `${overviewText('orderReference')} ${order.symbol}`).className = 'overview-state-reference';
    line(text, 'p', overviewText(state));
    if (payment && (payment.returned > 0 || (cancelled && payment.received > 0))) {
        line(text, 'p', `${overviewText('returned')}: ${money(payment.returned ?? 0, order.currency)}`).className = 'overview-refunded';
    }
    const admissions = (order.tickets || []).filter(ticket => ['used', 'unused'].includes(ticket.displayStatus));
    if (hasTickets && order.state !== 'storno' && admissions.length) {
        const used = admissions.filter(ticket => ticket.displayStatus === 'used').length;
        line(text, 'p', `${overviewText('usedTickets')}: ${used} / ${admissions.length}`).className = 'overview-usage';
    }
    if (payment?.instructionsAvailable && payment.dueAt && !complete && !cancelled) {
        line(text, 'p', `${overviewText(overdue ? 'overdue' : 'withinDeadline')} · ${overviewText('dueAt')}: ${date(payment.dueAt)}`).className = 'overview-state-deadline';
    }
}
export function renderOrderOverview(host, data, onContinue, offerInPage = false) {
    host.replaceChildren(); host.classList.add('order-overview');
    line(host, 'h1', `${overviewText('title')} ${data.root.symbol}`);
    line(host, 'p', data.root.title || '').className = 'overview-event-title';

    const waiting = data.people.some(p => ['waiting', 'offered', 'offer_expired', 'offer_declined', 'offer_cancelled'].includes(p.effectiveLifecycle));
    const activeOffer = data.offers.some(o => o.pendingPlaces > 0);
    const singleOrder = data.orders.length === 1 && !waiting;
    const summary = section(host, singleOrder ? `${overviewText('currentOrderStatus')} ${data.orders[0].symbol}` : overviewText('currentStatus'), 'overview-status');
    if (waiting) {
        line(summary, 'p', overviewText(activeOffer ? 'offerReady' : 'waitingExplanation'));
        if (!data.orders.length) line(summary, 'p', overviewText('not_required_yet'));
    }
    for (const order of data.orders) renderOrderState(summary, order, !singleOrder, data.root.hasTickets);
    if (!waiting && !data.orders.length) line(summary, 'p', overviewText('withdrawn'));
    for (const offer of data.offers.filter(o => o.pendingPlaces > 0)) line(summary, 'p', `${overviewText('offeredPlaces')}: ${offer.pendingPlaces} · ${overviewText('validUntil')}: ${date(offer.expiresAt)}`);
    if (onContinue) { const button = line(summary, 'button', overviewText('continue')); button.type = 'button'; button.onclick = onContinue; }
    else if (!offerInPage && activeOffer) line(summary, 'p', overviewText('offerEmail'));

    line(host, 'p', `${overviewText('updated')}: ${date(data.serverTime)}`).className = 'overview-updated';

    const itemLabel = overviewText(data.root.hasTickets ? 'ticket' : 'registration');
    const renderAdmissions = (card, people, order) => {
        const participants = line(card, 'ul', ''); participants.className = 'overview-people';
        for (const person of people) {
            const row = line(participants, 'li', '');
            const content = line(row, 'div', '');
            const header = line(content, 'div', ''); header.className = 'overview-admission-header';
            const symbol = data.root.hasTickets && person.symbol;
            const index = data.people.indexOf(person) + 1;
            line(header, 'h3', `${itemLabel}${symbol ? ` ${symbol}` : data.people.length > 1 ? ` ${index}` : ''}`);
            const ticket = order?.tickets?.find(ticket => ticket.id === person.id);
            const status = ticket?.displayStatus === 'cancelled' || (data.root.hasTickets && ['used', 'unused'].includes(ticket?.displayStatus)) ? ticket.displayStatus : null;
            if (status) line(header, 'span', overviewText(status)).className = 'overview-admission-status';
            else if (person.effectiveLifecycle !== 'admitted' && !ticket) line(header, 'span', overviewText(person.effectiveLifecycle)).className = 'overview-admission-status';
            if (person.label) line(content, 'p', person.label);
            renderOverviewAnswers(content, person.answers, `ticket:${person.id}`);
            const items = (order?.items || []).filter(item => String(item.ticketId) === String(person.id));
            if (items.length) renderOverviewProducts(content, items, order.currency, money);
        }
    };
    const pendingPeople = data.people.filter(person => !data.orders.some(order => String(order.id) === String(person.currentOrderId)));
    if (pendingPeople.length) {
        const pending = section(host, `${overviewText('orderDetails')} ${data.root.symbol}`, 'order-overview-card');
        renderAdmissions(pending, pendingPeople);
    }
    for (const order of data.orders) {
        const card = section(host, `${overviewText('orderDetails')} ${order.symbol}`, 'order-overview-card');
        renderOverviewCustomer(card, order.answers, `order:${order.id}`);
        renderAdmissions(card, data.people.filter(person => String(person.currentOrderId) === String(order.id)), order);
        const total = line(card, 'dl', ''); total.className = 'overview-order-total';
        fact(total, overviewText('total'), money(order.total, order.currency));
        const payment = order.payment;
        if (payment) {
            if (payment.totalOutstanding > 0 || payment.returned > 0 || payment.overpaid > 0) {
                const amounts = line(card, 'dl', ''); amounts.className = 'overview-amounts';
                fact(amounts, overviewText('received'), money(payment.received, order.currency));
                fact(amounts, overviewText('totalOutstanding'), money(payment.totalOutstanding, order.currency));
                for (const key of ['returned', 'overpaid']) if (payment[key] > 0) fact(amounts, overviewText(key), money(payment[key], order.currency));
            }
            if (payment.instructionsAvailable) {
                const instructions = line(card, 'dl', ''); instructions.className = 'overview-payment-details';
                if (payment.qrPayment && payment.dueNow > 0) {
                    const paymentHost = line(card, 'div', '');
                    let presentation;
                    try { presentation = presentPayment(payment.qrPayment); } catch { /* Manual bank details remain available if QR data is invalid. */ }
                    renderPaymentDetails(paymentHost, {
                        ...payment.qrPayment,
                        payload: presentation?.qrPayload,
                        reference_kind: payment.referenceKind,
                        reference: presentation?.referenceDisplay || payment.reference,
                    }, { occasionTitle: data.root.title, orderSymbol: order.symbol });
                    paymentHost.querySelector('details').dataset.overviewKey = `payment:${order.id}`;
                } else {
                    fact(instructions, overviewText('dueNow'), money(payment.dueNow, order.currency));
                    fact(instructions, overviewText('account'), payment.publicAccount);
                    fact(instructions, payment.referenceKind, payment.reference);
                }
                fact(instructions, overviewText('dueAt'), payment.dueAt ? date(payment.dueAt) : overviewText('onSite'));
                if (payment.overdue) line(card, 'p', overviewText('overdue'));
            }

        }

    }
    const history = section(host, overviewText('history'), 'overview-history-card');
    const timeline = line(history, 'ol', ''); timeline.className = 'overview-timeline';
    for (const event of data.timeline || []) {
        if (event.kind === 'registration_received') continue;
        const entry = line(timeline, 'li', '');
        line(entry, 'strong', overviewText(event.kind === 'order_sent' && !data.root.hasTickets ? 'confirmation_sent' : event.kind));
        const time = line(entry, 'time', date(event.at)); time.dateTime = event.at;
        if (event.amount != null) line(entry, 'p', money(event.amount, event.currency));
        if (event.paymentMethod === 'cash') line(entry, 'p', overviewText('cashPayment'));
        else if (event.paymentMethod === 'bank') {
            line(entry, 'p', `${overviewText('bankPayment')}${event.recipientAccount ? ` · ${overviewText('account')}: ${event.recipientAccount}` : ''}`);
        }
        if (event.previousState && event.previousState !== event.state) line(entry, 'p', `${overviewText(event.previousState)} → ${overviewText(event.state)}`);
        if (event.previousTotal != null) line(entry, 'p', `${overviewText('previousTotal')}: ${money(event.previousTotal, event.currency)} → ${overviewText('newTotal')}: ${money(event.total, event.currency)}`);
        if (event.itemsChanged) renderOverviewChanges(entry, event, itemLabel, data.people, money, data.root.hasTickets);
        if (event.detailsChanged) line(entry, 'p', overviewText('detailsChanged'));
        if (event.symbol && event.symbol !== data.root.symbol) line(entry, 'small', `${overviewText('orderReference')} ${event.symbol}`);
    }
    const current = line(timeline, 'li', ''); current.className = 'overview-timeline-current';
    line(current, 'strong', overviewText('currentStatus'));
    if (waiting) line(current, 'p', overviewText(activeOffer ? 'offerReady' : 'waitingExplanation'));
    for (const order of data.orders) renderOrderState(current, order, data.orders.length > 1, data.root.hasTickets);
    if (!waiting && !data.orders.length) line(current, 'p', overviewText('withdrawn'));
}

export function stopOrderOverview(host) {
    host._overviewRefreshCleanup?.();
    host._overviewGeneration = (host._overviewGeneration || 0) + 1;
}

function scheduleOverviewRefresh(host, refresh) {
    const doc = host.ownerDocument, win = doc.defaultView;
    if (!win || !host.isConnected || !host.classList.contains('order-overview')) return;
    let timer;
    const visible = () => host.isConnected && host.classList.contains('order-overview') && doc.visibilityState === 'visible' && host.getClientRects().length > 0;
    const run = () => { if (visible()) return refresh(); cleanup(); };
    const changed = () => { win.clearTimeout(timer); if (visible()) void run(); };
    const cleanup = () => { win.clearTimeout(timer); doc.removeEventListener('visibilitychange', changed); };
    host._overviewRefreshCleanup = cleanup;
    doc.addEventListener('visibilitychange', changed);
    if (visible()) timer = win.setTimeout(run, 30000);
}

export async function loadOrderOverview(host, commands, scope, onContinue, offerInPage = false, background = false) {
    host._overviewRefreshCleanup?.();
    const generation = (host._overviewGeneration || 0) + 1; host._overviewGeneration = generation;
    host.classList.add('order-overview');
    if (!background) {
        host._overviewSnapshot = null;
        host.replaceChildren(); host.setAttribute('aria-busy', 'true');
        line(host, 'p', overviewText('loading'));
    }
    try {
        const data = await commands.overview(scope);
        if (host._overviewGeneration !== generation) return;
        const snapshot = JSON.stringify({ ...data, serverTime: null });
        // Keep expanded details and keyboard focus stable when nothing changed.
        // A focused control may be in use: defer replacing it until the next poll.
        if (snapshot !== host._overviewSnapshot && (!background || !host.contains(host.ownerDocument.activeElement))) {
            const opened = new Map([...host.querySelectorAll('details[data-overview-key]')].map(detail => [detail.dataset.overviewKey, detail.open]));
            renderOrderOverview(host, data,
                onContinue && data.offers.some(o => o.pendingPlaces > 0) ? onContinue : null, offerInPage);
            host.querySelectorAll('details[data-overview-key]').forEach(detail => { if (opened.has(detail.dataset.overviewKey)) detail.open = opened.get(detail.dataset.overviewKey); });
            host._overviewSnapshot = snapshot;
        }
        const timestamp = host.querySelector('.overview-updated');
        if (timestamp && snapshot === host._overviewSnapshot) timestamp.textContent = `${overviewText('updated')}: ${date(data.serverTime)}`;
        return data;
    } catch {
        if (host._overviewGeneration !== generation) return;
        host._overviewSnapshot = null;
        host.replaceChildren(); line(host, 'p', overviewText('failed')).setAttribute('role', 'alert');
        const retry = line(host, 'button', LocalizationService.tr('Common.retry')); retry.type = 'button';
        retry.onclick = () => loadOrderOverview(host, commands, scope, onContinue, offerInPage);
    } finally {
        if (host._overviewGeneration === generation) {
            host.removeAttribute('aria-busy');
            scheduleOverviewRefresh(host, () => loadOrderOverview(host, commands, scope, onContinue, offerInPage, true));
        }
    }
}
