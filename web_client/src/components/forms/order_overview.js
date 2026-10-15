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
export function renderOrderOverview(host, data, onRefresh, onContinue, offerInPage = false) {
    host.replaceChildren(); host.classList.add('order-overview');
    line(host, 'p', overviewText('title')).className = 'overview-eyebrow';
    line(host, 'h1', data.root.title || overviewText('title'));
    line(host, 'p', `${overviewText('orderReference')}: ${data.root.symbol}`).className = 'overview-reference';
    const toolbar = line(host, 'div', ''); toolbar.className = 'overview-toolbar';
    line(toolbar, 'span', `${overviewText('updated')}: ${date(data.serverTime)}`);
    const refresh = line(toolbar, 'button', overviewText('refresh')); refresh.type = 'button'; refresh.onclick = onRefresh;

    const waiting = data.people.some(p => ['waiting', 'offered', 'offer_expired', 'offer_declined', 'offer_cancelled'].includes(p.effectiveLifecycle));
    const activeOffer = data.offers.some(o => o.pendingPlaces > 0);
    const summary = section(host, overviewText('currentStatus'), 'overview-status');
    if (waiting) {
        line(summary, 'p', overviewText(activeOffer ? 'offerReady' : 'waitingExplanation'));
        if (!data.orders.length) line(summary, 'p', overviewText('not_required_yet'));
    }
    for (const order of data.orders) line(summary, 'p', `${order.symbol}: ${overviewText(order.state === 'storno' ? 'cancelled' : order.payment?.status || order.state)}`);
    if (!waiting && !data.orders.length) line(summary, 'p', overviewText('withdrawn'));
    for (const offer of data.offers.filter(o => o.pendingPlaces > 0)) line(summary, 'p', `${overviewText('offeredPlaces')}: ${offer.pendingPlaces} · ${overviewText('validUntil')}: ${date(offer.expiresAt)}`);
    if (onContinue) { const button = line(summary, 'button', overviewText('continue')); button.type = 'button'; button.onclick = onContinue; }
    else if (!offerInPage && activeOffer) line(summary, 'p', overviewText('offerEmail'));

    const people = section(host, overviewText('people'));
    const participants = line(people, 'ul', ''); participants.className = 'overview-people';
    data.people.forEach((person, i) => {
        const row = line(participants, 'li', '');
        line(row, 'span', person.label || `${overviewText('participant')} ${i + 1}`);
        line(row, 'strong', overviewText(person.effectiveLifecycle));
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
                fact(instructions, overviewText('dueNow'), money(payment.dueNow, order.currency));
                fact(instructions, overviewText('dueAt'), payment.dueAt ? date(payment.dueAt) : overviewText('onSite'));
                if (payment.overdue) line(card, 'p', overviewText('overdue'));
                fact(instructions, overviewText('account'), payment.publicAccount);
                fact(instructions, payment.referenceKind, payment.reference);
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
        if (order.items?.length) {
            const details = line(card, 'details', ''); line(details, 'summary', overviewText('items'));
            for (const item of order.items) line(details, 'p', `${item.title || ''}: ${money(item.price, item.currency)}`);
        }
        for (const [i, ticket] of (data.root.hasTickets === false ? [] : order.tickets || []).entries()) line(card, 'p', `${ticket.label || `${overviewText('participant')} ${i + 1}`} - ${overviewText(ticket.displayStatus)}`);
    }
    const history = section(host, overviewText('history'));
    const timeline = line(history, 'ol', ''); timeline.className = 'overview-timeline';
    for (const event of data.timeline || []) {
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
    line(current, 'p', overviewText(waiting ? activeOffer ? 'offerReady' : 'waitingExplanation' : 'statusAbove'));
}

export async function loadOrderOverview(host, commands, scope, onContinue, offerInPage = false) {
    const generation = (host._overviewGeneration || 0) + 1; host._overviewGeneration = generation;
    host.classList.add('order-overview');
    host.replaceChildren(); host.setAttribute('aria-busy', 'true');
    line(host, 'p', overviewText('loading'));
    try {
        const data = await commands.overview(scope);
        if (host._overviewGeneration !== generation) return;
        renderOrderOverview(host, data, () => loadOrderOverview(host, commands, scope, onContinue, offerInPage),
            onContinue && data.offers.some(o => o.pendingPlaces > 0) ? onContinue : null, offerInPage);
    } catch {
        if (host._overviewGeneration !== generation) return;
        host.replaceChildren(); line(host, 'p', overviewText('failed')).setAttribute('role', 'alert');
        const retry = line(host, 'button', overviewText('refresh')); retry.type = 'button';
        retry.onclick = () => loadOrderOverview(host, commands, scope, onContinue, offerInPage);
    } finally { if (host._overviewGeneration === generation) host.removeAttribute('aria-busy'); }
}
