import { FieldPreviewFactory } from './previews/field_preview_factory.js';
import { formFieldTitle } from './form_field_labels.js';
import { LocalizationService } from '../../services/localization_service.js';
const tr = key => LocalizationService.tr(`OrderOverview.${key}`);
const node = (parent, tag, text, className) => {
    const el = document.createElement(tag); el.textContent = text;
    if (className) el.className = className;
    parent.append(el); return el;
};
export function renderOverviewProducts(host, items, currency, money) {
    const list = node(host, 'ul', '', 'overview-products');
    for (const item of items) {
        const row = node(list, 'li', '');
        const label = node(row, 'span', item.title || '');
        const seating = [[tr('table'), item.spotGroupTitle], [tr('seat'), item.spotTitle]]
            .filter(([, value]) => value != null && String(value).trim() !== '')
            .map(([title, value]) => `${title}: ${value}`).join(' · ');
        if (seating) node(label, 'span', seating, 'overview-product-seating');
        node(row, 'strong', money(item.price, item.currency || currency), 'overview-product-price');
    }
}
export function renderOverviewCustomer(host, answers = [], key) {
    const contactTypes = ['name', 'surname', 'email', 'phone'];
    const contacts = answers.filter(a => contactTypes.includes(a.type) && a.value != null && String(a.value).trim());
    if (contacts.length) {
        const list = node(host, 'dl', '', 'overview-customer');
        const names = contacts.filter(a => ['name', 'surname'].includes(a.type)).sort((a,b) => contactTypes.indexOf(a.type)-contactTypes.indexOf(b.type));
        const rows = [...(names.length ? [{...names[0], value: names.map(a=>a.value).join(' ')}] : []), ...contacts.filter(a=>!['name','surname'].includes(a.type))];
        for (const answer of rows) {
            const row = node(list, 'div', '');
            node(row, 'dt', `${formFieldTitle(answer)}:`);
            const value = node(row, 'dd', '');
            const text = String(answer.value);
            if (answer.type === 'email' || answer.type === 'phone') {
                const link = node(value, 'a', text);
                link.href = answer.type === 'email' ? `mailto:${text}` : `tel:${text.replace(/[^+0-9]/g, '')}`;
            } else node(value, 'strong', text);
        }
    }
    renderOverviewAnswers(host, answers.filter(a => !contactTypes.includes(a.type)), key);
}
export function renderOverviewAnswers(host, answers = [], key) {
    if (!answers.length) return;
    const details = node(host, 'details', '', 'overview-answers');
    details.dataset.overviewKey = `answers:${key}`;
    node(details, 'summary', tr('submittedDetails'));
    const values = node(details, 'dl', '');
    for (const answer of answers) {
        node(values, 'dt', formFieldTitle(answer) || tr('answer'));
        const value = ['id_document', 'birth_date', 'sex'].includes(answer.type)
            ? FieldPreviewFactory.format(answer, answer.value, {}).value
            : Array.isArray(answer.value) ? answer.value.join(', ') : String(answer.value ?? '');
        node(values, 'dd', value);
    }
}
// Compare consecutive historical snapshots, preserving ticket identity and
// duplicate product instances. The email preview uses a different baseline
// (the last sent snapshot), so its current-order diff cannot be reused here.
export function overviewItemChanges(before = [], after = []) {
    const remaining = [...before], pending = [];
    const sameIdentity = (a, b) => String(a.ticketId ?? '') === String(b.ticketId ?? '') && String(a.id ?? '') === String(b.id ?? '');
    for (const item of after) {
        const index = remaining.findIndex(old => sameIdentity(old, item) && old.title === item.title && Number(old.price) === Number(item.price) && old.currency === item.currency);
        if (index >= 0) remaining.splice(index, 1); else pending.push(item);
    }
    const changes = [];
    for (const item of pending) {
        const index = item.id == null ? -1 : remaining.findIndex(old => sameIdentity(old, item));
        if (index >= 0) changes.push({ kind: 'changed', before: remaining.splice(index, 1)[0], after: item });
        else changes.push({ kind: 'added', after: item });
    }
    return [...remaining.map(item => ({ kind: 'removed', before: item })), ...changes];
}
export function renderOverviewChanges(host, event, itemLabel, people, money, hasTickets) {
    const changes = overviewItemChanges(event.itemsBefore, event.itemsAfter);
    if (!changes.length) return;
    const details = node(host, 'details', '', 'overview-changes');
    details.dataset.overviewKey = `changes:${event.symbol || ''}:${event.id || event.at}`;
    node(details, 'summary', tr('itemsChanged'));
    const groups = new Map();
    for (const change of changes) {
        const item = change.after || change.before;
        const key = String(item.ticketId ?? '');
        if (!groups.has(key)) {
            const group = node(details, 'div', '', 'overview-change-group');
            const index = people.findIndex(person => String(person.id) === key);
            const symbol = hasTickets && item.ticketSymbol;
            node(group, 'h4', `${itemLabel}${symbol ? ` ${symbol}` : people.length > 1 && index >= 0 ? ` ${index + 1}` : ''}`);
            groups.set(key, group);
        }
        const row = node(groups.get(key), 'div', '', `overview-change overview-change-${change.kind}`);
        node(row, 'span', tr(change.kind), 'overview-change-label');
        const content = node(row, 'div', '');
        if (change.before) renderOverviewProducts(content, [change.before], event.currency, money);
        if (change.before && change.after) node(content, 'span', tr('changedTo'), 'overview-change-to');
        if (change.after) renderOverviewProducts(content, [change.after], event.currency, money);
    }
}
