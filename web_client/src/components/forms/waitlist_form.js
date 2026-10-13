import { LocalizationService } from '../../services/localization_service.js';
import { WaitlistStrings as S } from './waitlist_strings.js';

export function ticketLabel(person, index = 0, form = null, total = 1) {
    // Only display name fields, never arbitrary answers (notes or identity documents).
    if (typeof person.displayName === 'string' && person.displayName.trim()) return person.displayName.trim();
    const definitions = (form?.relatedFields || form?.fields || []).flatMap(field =>
        field.type === 'ticket' ? (field.subFields || field.data?.fields || []) :
            (field.isTicketField || field.is_ticket_field ? [field] : []));
    const fields = person.answers?.fields || [];
    const names = ['name', 'surname'].flatMap(type => {
        const definition = definitions.find(field => field.type === type && !field.isHidden && !field.is_hidden);
        const answer = definition ? fields.find(field => field[definition.id] !== undefined || field._subFieldId === definition.id) : null;
        const value = answer?.[definition?.id] ?? answer?.[type] ??
            (!form ? fields.find(field => typeof field[type] === 'string')?.[type] : null);
        return typeof value === 'string' && value.trim() ? [value.trim()] : [];
    });
    return names.join(' ') || (total === 1 ? S.text('yourRegistration', form?.communicationTone || form?.data?.communication_tone) : `${S.text('person')} ${index + 1}`);
}

export function appendWaitlistContext(container, context) {
    if (!context?.occasionTitle && !context?.orderSymbol) return;
    const header = document.createElement('header');
    header.className = 'waitlist-context';
    if (context.occasionTitle) {
        const title = document.createElement('h1'); title.textContent = context.occasionTitle;
        header.appendChild(title);
    }
    if (context.orderSymbol) {
        const symbol = document.createElement('p'); symbol.className = 'waitlist-order-symbol';
        symbol.textContent = `${S.text('registrationSymbol')}: ${context.orderSymbol}`;
        header.appendChild(symbol);
    }
    container.appendChild(header);
}

export function prepareOfferSession(session, model) {
    const bundle = model.offerBundle;
    if (!bundle) return;
    const saved = model.offerDraft;
    session.state.fields = new Map(saved?.fields || (bundle.orderData?.fields || []).flatMap(f => Object.entries(f)));
    const selected = model.selectedTicketIds || bundle.slots.filter(s => s.outcome === 'pending').map(s => s.ticketId);
    model.selectedTicketIds = selected.slice(0, session.maxTickets);
    session.state.tickets = model.selectedTicketIds.map(id => {
        const previous = model.ticketDrafts?.get(id) || saved?.tickets.find(t => t.ticketId === id);
        if (previous) return previous;
        const person = bundle.tickets.find(p => p.id === id);
        return { ticketId: id, id, fields: (person?.answers?.fields || []).flatMap(f =>
            Object.entries(f).flatMap(([key, value]) => {
                const def = session._getTicketSubDef(key);
                return def ? [{ [def.type]: value, [key]: value, _subFieldId: def.id }] : [];
            })) };
    });
    session._syncPayloadFromState();
}

export function renderWaitlistControls(page, model) {
    const session = page.currentSession;
    const tone = model.communicationTone;
    const form = page.host.querySelector('form');
    if (!form) return;
    const section = document.createElement('section');
    section.className = 'form-registration-status';
    section.setAttribute('aria-live', 'polite');
    const capacity = model.capacity;
    if (capacity?.showRemaining && Number.isFinite(capacity.limit) && Number.isFinite(capacity.occupiedPeople)) {
        const occupancy = document.createElement('p');
        occupancy.className = 'form-occupancy';
        occupancy.textContent = S.text('occupancy').replace('{occupied}', capacity.occupiedPeople + (capacity.offeredPlaces ?? 0)).replace('{capacity}', capacity.limit);
        section.appendChild(occupancy);
    }
    const message = document.createElement('p');
    message.className = 'waitlist-intro';
    if (model.registrationMode === 'waitlist') {
        section.classList.add('is-waitlist');
        const heading = document.createElement('strong');
        heading.className = 'waitlist-mode-label';
        heading.textContent = S.text('registrationModeLabel');
        section.appendChild(heading);
        message.textContent = S.text('explanation', tone);
    }
    section.appendChild(message);
    if (section.textContent || model.offerBundle) form.prepend(section);
    const placeProductNotice = () => {
        const group = form.querySelector('.waitlist-product-options');
        if (!group) { form.querySelector('#waitlist-product-reason')?.remove(); return; }
        const reason = form.querySelector('#waitlist-product-reason') || document.createElement('aside');
        reason.id = 'waitlist-product-reason';
        reason.className = 'waitlist-product-notice';
        reason.setAttribute('role', 'note');
        reason.textContent = S.text('productsAfterOffer', tone);
        const target = group.closest('.form-field-card') || group;
        target.before(reason);
    };
    if (model.registrationMode === 'waitlist') {
        placeProductNotice();
        session.addEventListener('state-changed', placeProductNotice);
    }
    const b = model.offerBundle;
    if (!b) return;
    section.classList.add('is-offer');
    const facts = document.createElement('dl');
    facts.className = 'waitlist-offer-facts';
    for (const [label, value] of [
        [S.remaining, b.pendingCount],
        [S.expiresAt, new Intl.DateTimeFormat(LocalizationService.currentLocale, { dateStyle: 'medium', timeStyle: 'short', ...(b.timeZone ? { timeZone: b.timeZone } : {}) }).format(new Date(b.expiresAt))],
    ]) {
        const fact = document.createElement('div');
        const term = document.createElement('dt'); term.textContent = label;
        const detail = document.createElement('dd'); detail.textContent = value;
        fact.append(term, detail); facts.appendChild(fact);
    }
    section.insertBefore(facts, message);
    message.textContent = S.text('productAvailability', tone);
    const fieldset = document.createElement('fieldset');
    fieldset.className = 'waitlist-people';
    const legend = document.createElement('legend');
    legend.textContent = S.text('selectPeople', tone);
    const eligiblePeople = b.tickets.filter(person => !['admitted', 'withdrawn', 'cancelled'].includes(person.lifecycle));
    if (eligiblePeople.length > 1) fieldset.appendChild(legend);
    section.appendChild(fieldset);
    for (const [index, person] of b.tickets.entries()) {
        if (['admitted', 'withdrawn', 'cancelled'].includes(person.lifecycle)) continue;
        const label = document.createElement(eligiblePeople.length === 1 ? 'div' : 'label');
        label.className = 'waitlist-person-row';
        const input = document.createElement('input');
        input.type = 'checkbox';
        input.className = 'form-check-input';
        input.hidden = eligiblePeople.length === 1;
        input.checked = model.selectedTicketIds.includes(person.id);
        input.disabled = person.lifecycle === 'offered' && !b.slots.some(s => s.ticketId === person.id && s.outcome === 'pending');
        const name = ticketLabel(person, index, model, b.tickets.length);
        const personName = document.createElement('strong'); personName.textContent = name;
        const status = document.createElement('span'); status.className = 'waitlist-person-status'; status.textContent = S.text(person.lifecycle);
        if (eligiblePeople.length > 1) label.appendChild(input);
        label.append(personName, status);
        input.onchange = () => {
            if (input.checked && model.selectedTicketIds.length >= session.maxTickets) {
                input.checked = false;
                message.textContent = `${S.text('selectPeople', tone)}: ${session.maxTickets}`;
                return;
            }
            model.ticketDrafts ||= new Map();
            for (const t of session.state.tickets) model.ticketDrafts.set(t.ticketId, t);
            model.offerDraft = { fields: [...session.state.fields], tickets: session.state.tickets };
            model.selectedTicketIds = input.checked ? [...model.selectedTicketIds, person.id] : model.selectedTicketIds.filter(id => id !== person.id);
            page.renderForm(model, false);
        };
        fieldset.appendChild(label);
    }
    form.querySelector('.btn-submit').textContent = S.text(model.selectedTicketIds.length === 1 ? 'acceptOne' : 'accept', tone);
    form.querySelectorAll('.btn-add-ticket,.btn-remove-ticket').forEach(el => el.hidden = true);
    const decline = document.createElement('button');
    decline.type = 'button'; decline.className = 'btn waitlist-decline'; decline.textContent = S.text(model.selectedTicketIds.length === 1 ? 'declineOne' : 'decline', tone);
    decline.disabled = !model.selectedTicketIds.length || !model.selectedTicketIds.every(id => b.slots.some(s => s.ticketId === id && s.outcome === 'pending'));
    decline.onclick = () => page.resolveWaitlist('decline', model.selectedTicketIds);
    if (decline.disabled && model.selectedTicketIds.length) {
        const reason = document.createElement('p'); reason.textContent = S.text('declineAssigned', tone); section.appendChild(reason);
    }
    section.appendChild(decline);
}

// Hydrate the existing input widgets, including compound personal fields.
export function prefillOfferFields(form, session) {
    const setValue = (name, value) => {
        if (value && typeof value === 'object' && !Array.isArray(value)) {
            setValue(name, value.id_document_number ?? '');
            setValue(`${name}_expiry`, value.id_document_expiry_date ?? '');
            return;
        }
        for (const input of form.querySelectorAll('input,select,textarea')) {
            if (input.name !== String(name)) continue;
            if (input.type === 'checkbox' || input.type === 'radio') input.checked = String(value ?? '').split(' | ').includes(input.value);
            else if (input._flatpickr && value) input._flatpickr.setDate(String(value).slice(0, 10), false, 'Y-m-d');
            else input.value = value ?? '';
        }
    };
    for (const [id, value] of session.state.fields) setValue(id, value);
    const ticket = session._getTicketFieldDef();
    session.state.tickets.forEach((person, index) => {
        for (const field of person.fields || []) {
            const def = session._getTicketSubDef(field._subFieldId);
            if (def) setValue(`${ticket.id}_${index}_${def.id}`, field[def.type]);
        }
    });
}
