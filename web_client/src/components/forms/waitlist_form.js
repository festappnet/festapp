import { WaitlistStrings as S } from './waitlist_strings.js';

export function ticketLabel(person, index = 0) {
    return (person.answers?.fields || []).flatMap(field => {
        const canonical = Object.entries(field).filter(([key]) => /^\d+$/.test(key));
        const entries = canonical.length ? canonical : Object.entries(field).filter(([key]) => !key.startsWith('_'));
        return entries.map(([, value]) => value).filter(value => typeof value === 'string' && value.trim());
    }).join(' · ') || `${S.text('person')} ${index + 1}`;
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
    const form = page.host.querySelector('form');
    if (!form) return;
    const section = document.createElement('section');
    section.className = 'form-registration-status';
    section.setAttribute('aria-live', 'polite');
    const capacity = model.capacity;
    if (capacity?.showRemaining && Number.isFinite(capacity.limit) && Number.isFinite(capacity.occupiedPeople)) {
        const occupancy = document.createElement('p');
        occupancy.className = 'form-occupancy';
        occupancy.textContent = S.text('occupancy').replace('{occupied}', capacity.occupiedPeople).replace('{capacity}', capacity.limit);
        section.appendChild(occupancy);
    }
    const message = document.createElement('p');
    message.className = 'waitlist-intro';
    if (model.registrationMode === 'waitlist') {
        const heading = document.createElement('h2');
        heading.textContent = S.title;
        section.appendChild(heading);
        message.textContent = S.explanation;
    }
    section.appendChild(message);
    form.prepend(section);
    const b = model.offerBundle;
    if (!b) return;
    message.textContent = `${S.remaining}: ${b.pendingCount} · ${S.expiresAt}: ${new Date(b.expiresAt).toLocaleString()}. ${S.productAvailability}`;
    const fieldset = document.createElement('fieldset');
    fieldset.className = 'waitlist-people';
    const legend = document.createElement('legend');
    legend.textContent = S.selectPeople;
    fieldset.appendChild(legend);
    section.appendChild(fieldset);
    const eligiblePeople = b.tickets.filter(person => !['admitted', 'withdrawn', 'cancelled'].includes(person.lifecycle));
    for (const [index, person] of b.tickets.entries()) {
        if (['admitted', 'withdrawn', 'cancelled'].includes(person.lifecycle)) continue;
        const label = document.createElement('label');
        label.className = 'waitlist-person-row';
        const input = document.createElement('input');
        input.type = 'checkbox';
        input.className = 'form-check-input';
        input.hidden = eligiblePeople.length === 1;
        input.checked = model.selectedTicketIds.includes(person.id);
        input.disabled = person.lifecycle === 'offered' && !b.slots.some(s => s.ticketId === person.id && s.outcome === 'pending');
        const name = ticketLabel(person, index);
        label.append(input, document.createTextNode(` ${name} ${S.text(person.lifecycle)}`));
        input.onchange = () => {
            if (input.checked && model.selectedTicketIds.length >= session.maxTickets) {
                input.checked = false;
                message.textContent = `${S.selectPeople}: ${session.maxTickets}`;
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
    form.querySelector('.btn-submit').textContent = S.accept;
    form.querySelectorAll('.btn-add-ticket,.btn-remove-ticket').forEach(el => el.hidden = true);
    const decline = document.createElement('button');
    decline.type = 'button'; decline.className = 'btn btn-secondary'; decline.textContent = S.decline;
    decline.disabled = !model.selectedTicketIds.length || !model.selectedTicketIds.every(id => b.slots.some(s => s.ticketId === id && s.outcome === 'pending'));
    decline.onclick = () => page.resolveWaitlist('decline', model.selectedTicketIds);
    if (decline.disabled && model.selectedTicketIds.length) {
        const reason = document.createElement('p'); reason.textContent = S.text('declineAssigned'); section.appendChild(reason);
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
