import { WaitlistStrings as S } from './waitlist_strings.js';

export function participantLabel(person) {
    return (person.answers?.fields || []).flatMap(field => {
        const canonical = Object.entries(field).filter(([key]) => /^\d+$/.test(key));
        const entries = canonical.length ? canonical : Object.entries(field).filter(([key]) => !key.startsWith('_'));
        return entries.map(([, value]) => value).filter(value => typeof value === 'string' && value.trim());
    }).join(' · ') || person.id;
}

export function prepareOfferSession(session, model) {
    const bundle = model.offerBundle;
    if (!bundle) return;
    const saved = model.offerDraft;
    session.state.fields = new Map(saved?.fields || (bundle.orderData?.fields || []).flatMap(f => Object.entries(f)));
    const selected = model.selectedPeople || bundle.slots.filter(s => s.outcome === 'pending').map(s => s.participantId);
    model.selectedPeople = selected.slice(0, session.maxTickets);
    session.state.tickets = model.selectedPeople.map(id => {
        const previous = model.personDrafts?.get(id) || saved?.tickets.find(t => t.participantId === id);
        if (previous) return previous;
        const person = bundle.participants.find(p => p.id === id);
        return { participantId: id, id, fields: (person?.answers?.fields || []).flatMap(f =>
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
    section.setAttribute('aria-live', 'polite');
    const message = document.createElement('p');
    section.appendChild(message);
    form.prepend(section);
    if (model.registrationMode === 'waitlist') {
        message.textContent = `${S.title}. ${S.explanation}`;
        form.querySelector('.btn-submit').textContent = S.register;
    } else if (model.capacity?.showRemaining && model.capacity.remainingPublic !== null) {
        message.textContent = `${S.remaining}: ${model.capacity.remainingPublic}`;
    }
    const b = model.offerBundle;
    if (!b) return;
    message.textContent = `${S.remaining}: ${b.pendingCount} · ${S.expiresAt}: ${new Date(b.expiresAt).toLocaleString()}. ${S.productAvailability}`;
    const fieldset = document.createElement('fieldset');
    const legend = document.createElement('legend');
    legend.textContent = S.selectPeople;
    fieldset.appendChild(legend);
    section.appendChild(fieldset);
    for (const person of b.participants) {
        if (['admitted', 'withdrawn', 'cancelled'].includes(person.lifecycle)) continue;
        const label = document.createElement('label');
        label.style.cssText = 'display:block;padding:12px 0';
        const input = document.createElement('input');
        input.type = 'checkbox';
        input.checked = model.selectedPeople.includes(person.id);
        input.disabled = person.lifecycle === 'offered' && !b.slots.some(s => s.participantId === person.id && s.outcome === 'pending');
        const name = participantLabel(person);
        label.append(input, document.createTextNode(` ${name} ${S.text(person.lifecycle)}`));
        input.onchange = () => {
            if (input.checked && model.selectedPeople.length >= session.maxTickets) {
                input.checked = false;
                message.textContent = `${S.selectPeople}: ${session.maxTickets}`;
                return;
            }
            model.personDrafts ||= new Map();
            for (const t of session.state.tickets) model.personDrafts.set(t.participantId, t);
            model.offerDraft = { fields: [...session.state.fields], tickets: session.state.tickets };
            model.selectedPeople = input.checked ? [...model.selectedPeople, person.id] : model.selectedPeople.filter(id => id !== person.id);
            page.renderForm(model, false);
        };
        fieldset.appendChild(label);
    }
    form.querySelector('.btn-submit').textContent = S.accept;
    form.querySelectorAll('.btn-add-ticket,.btn-remove-ticket').forEach(el => el.hidden = true);
    const decline = document.createElement('button');
    decline.type = 'button'; decline.className = 'btn btn-secondary'; decline.textContent = S.decline;
    decline.disabled = !model.selectedPeople.length || !model.selectedPeople.every(id => b.slots.some(s => s.participantId === id && s.outcome === 'pending'));
    decline.onclick = () => page.resolveWaitlist('decline', model.selectedPeople);
    if (decline.disabled && model.selectedPeople.length) {
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
