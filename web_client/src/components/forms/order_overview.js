import { renderPaymentDetails } from './payment_details.js';
import { presentPayment } from '../../../../supabase/functions/_shared/paymentPresentation.ts';
import { formLinkFromPath, replaceResolvedPublicLink } from '../../services/public_link.js';
import { LocalizationService } from '../../services/localization_service.js';
export const overviewText = key => LocalizationService.tr(`OrderOverview.${key}`);
export function parseOrderFragment(fragment) {
    if (!fragment?.startsWith('#order?')) return null;
    return parseOrderLocation({ search: fragment.slice(6) });
}
export function parseOrderLocation(location) {
    const params = new URLSearchParams(location.search || '');
    if (params.get('waitlist') === '1') return null;
    if (!params.has('order_id') && !params.has('token')) return parseOrderFragment(location.hash);
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
export function renderOrderOverview(host, data, onContinue, offerInPage = false) {
    host.replaceChildren(); host.classList.add('order-overview');
    line(host, 'p', overviewText('title')).className = 'overview-eyebrow';
    line(host, 'h1', data.root.title || overviewText('title'));
    line(host, 'p', `${overviewText('orderReference')}: ${data.root.symbol}`).className = 'overview-reference';
    const toolbar = line(host, 'div', ''); toolbar.className = 'overview-toolbar';
    line(toolbar, 'span', `${overviewText('updated')}: ${date(data.serverTime)}`).className = 'overview-updated';

    const waiting = data.people.some(p => ['waiting', 'offered', 'offer_expired', 'offer_declined', 'offer_cancelled'].includes(p.effectiveLifecycle));
    const activeOffer = data.offers.some(o => o.pendingPlaces > 0);
    const summary = section(host, overviewText('currentStatus'), 'overview-status');
    if (waiting) {
        line(summary, 'p', overviewText(activeOffer ? 'offerReady' : 'waitingExplanation'));
        if (!data.orders.length) line(summary, 'p', overviewText('not_required_yet'));
    }
    for (const order of data.orders) line(summary, 'p', `${overviewText('orderReference')} ${order.symbol}: ${overviewText(order.state === 'storno' ? 'cancelled' : order.payment?.status || order.state)}`);
    if (!waiting && !data.orders.length) line(summary, 'p', overviewText('withdrawn'));
    for (const offer of data.offers.filter(o => o.pendingPlaces > 0)) line(summary, 'p', `${overviewText('offeredPlaces')}: ${offer.pendingPlaces} · ${overviewText('validUntil')}: ${date(offer.expiresAt)}`);
    if (onContinue) { const button = line(summary, 'button', overviewText('continue')); button.type = 'button'; button.onclick = onContinue; }
    else if (!offerInPage && activeOffer) line(summary, 'p', overviewText('offerEmail'));

    const itemLabel = overviewText(data.root.hasTickets ? 'ticket' : 'registration');
    const people = section(host, overviewText(data.root.hasTickets ? 'tickets' : 'registrations'));
    const participants = line(people, 'ul', ''); participants.className = 'overview-people';
    data.people.forEach((person, i) => {
        const row = line(participants, 'li', '');
        const content = line(row, 'div', '');
        line(content, 'strong', person.label || `${itemLabel} ${i + 1}`);
        const order = data.orders.find(order => order.id === person.currentOrderId);
        const ticket = order?.tickets?.find(ticket => ticket.id === person.id);
        const items = (order?.items || []).filter(item => String(item.ticketId) === String(person.id));
        if (items.length) {
            const products = line(content, 'ul', ''); products.className = 'overview-ticket-items';
            for (const item of items) line(products, 'li', `${item.title || ''}: ${money(item.price, item.currency || order.currency)}`);
        }
        // Payment belongs to the whole order; individual admissions only show
        // waitlist outcomes or their actual usage/cancellation state.
        const status = ticket?.displayStatus === 'cancelled' || (data.root.hasTickets && ['used', 'unused'].includes(ticket?.displayStatus)) ? ticket.displayStatus : null;
        if (status) line(row, 'span', overviewText(status));
        else if (person.effectiveLifecycle !== 'admitted' && !ticket) line(row, 'span', overviewText(person.effectiveLifecycle));
    });
    for (const order of data.orders) {
        const card = section(host, `${overviewText('orderReference')} ${order.symbol}`, 'order-overview-card');
        const amounts = line(card, 'dl', ''); amounts.className = 'overview-amounts';
        fact(amounts, overviewText('total'), money(order.total, order.currency));
        const payment = order.payment;
        if (payment) {
            fact(amounts, overviewText('received'), money(payment.received, order.currency));
            fact(amounts, overviewText('totalOutstanding'), money(payment.totalOutstanding, order.currency));
            for (const key of ['returned', 'overpaid']) if (payment[key] > 0) fact(amounts, overviewText(key), money(payment[key], order.currency));
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
                } else {
                    fact(instructions, overviewText('dueNow'), money(payment.dueNow, order.currency));
                    fact(instructions, overviewText('account'), payment.publicAccount);
                    fact(instructions, payment.referenceKind, payment.reference);
                }
                fact(instructions, overviewText('dueAt'), payment.dueAt ? date(payment.dueAt) : overviewText('onSite'));
                if (payment.overdue) line(card, 'p', overviewText('overdue'));
            }
            const transactions = payment.transactions || [];
            line(card, 'h3', `${overviewText('transactions')} (${transactions.filter(t => t.kind === 'payment_received').length})`);
            if (!transactions.length) line(card, 'p', overviewText('noTransactions'));
            else {
                const list = line(card, 'ul', ''); list.className = 'overview-transactions';
                for (const transaction of transactions) {
                    const row = line(list, 'li', '');
                    const description = line(row, 'span', overviewText(transaction.kind));
                    line(description, 'small', transaction.date ? new Date(`${transaction.date}T12:00:00`).toLocaleDateString(LocalizationService.currentLocale, { dateStyle: 'medium' }) : overviewText('dateUnknown'));
                    line(row, 'strong', money(transaction.amount, transaction.currency));
                }
            }
        }

    }
    const history = section(host, overviewText('history'));
    const timeline = line(history, 'ol', ''); timeline.className = 'overview-timeline';
    for (const event of data.timeline || []) {
        if (data.root.hasTickets && event.kind === 'registration_received') continue;
        const entry = line(timeline, 'li', '');
        line(entry, 'strong', overviewText(event.kind));
        const time = line(entry, 'time', date(event.at)); time.dateTime = event.at;
        if (event.previousState && event.previousState !== event.state) line(entry, 'p', `${overviewText(event.previousState)} → ${overviewText(event.state)}`);
        if (event.previousTotal != null) line(entry, 'p', `${overviewText('previousTotal')}: ${money(event.previousTotal, event.currency)} → ${overviewText('newTotal')}: ${money(event.total, event.currency)}`);
        if (event.itemsChanged) {
            const changes = line(entry, 'details', ''); line(changes, 'summary', overviewText('itemsChanged'));
            for (const [key, prefix] of [['itemsBefore', '−'], ['itemsAfter', '+']]) for (const item of event[key] || []) line(changes, 'p', `${prefix} ${item.title || ''}: ${money(item.price, event.currency)}`);
        }
        if (event.detailsChanged) line(entry, 'p', overviewText('detailsChanged'));
        if (event.symbol && event.symbol !== data.root.symbol) line(entry, 'small', `${overviewText('orderReference')} ${event.symbol}`);
    }
    const current = line(timeline, 'li', ''); current.className = 'overview-timeline-current';
    line(current, 'strong', overviewText('currentStatus'));
    if (waiting) line(current, 'p', overviewText(activeOffer ? 'offerReady' : 'waitingExplanation'));
    for (const order of data.orders) line(current, 'p', `${data.orders.length > 1 ? `${overviewText('orderReference')} ${order.symbol}: ` : ''}${overviewText(order.state === 'storno' ? 'cancelled' : order.payment?.status || order.state)}`);
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
        replaceResolvedPublicLink('form', formLinkFromPath(window.location.pathname), data.root?.formLink);
        const snapshot = JSON.stringify({ ...data, serverTime: null });
        // Keep expanded details and keyboard focus stable when nothing changed.
        // A focused control may be in use: defer replacing it until the next poll.
        if (snapshot !== host._overviewSnapshot && (!background || !host.contains(host.ownerDocument.activeElement))) {
            const opened = [...host.querySelectorAll('details')].map(detail => detail.open);
            renderOrderOverview(host, data,
                onContinue && data.offers.some(o => o.pendingPlaces > 0) ? onContinue : null, offerInPage);
            [...host.querySelectorAll('details')].forEach((detail, i) => { if (i < opened.length) detail.open = opened[i]; });
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
