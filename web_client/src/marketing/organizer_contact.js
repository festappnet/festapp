export function initOrganizerContact(root = document, copy = {}) {
    const form = root.querySelector('[data-organizer-contact]');
    if (!form) return;

    const email = form.elements.namedItem('email');
    const message = form.elements.namedItem('message');
    const button = form.querySelector('button[type="submit"]');
    const status = form.querySelector('[data-contact-status]');
    const win = root.defaultView;
    let pending = false;
    let previous;

    message.addEventListener('input', () => message.setCustomValidity(''));
    form.addEventListener('submit', async event => {
        event.preventDefault();
        if (pending) return;
        const payload = { email: email.value.trim(), message: message.value.trim() };
        if (!payload.message) {
            message.setCustomValidity(copy.required ?? 'Napište prosím zprávu.');
            message.reportValidity();
            return;
        }

        if (previous?.email !== payload.email || previous?.message !== payload.message) {
            previous = { ...payload, id: win.crypto.randomUUID() };
        }
        pending = true;
        email.readOnly = message.readOnly = button.disabled = true;
        status.textContent = copy.pending ?? 'Odesíláme…';
        try {
            const response = await win.fetch(form.action, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(previous),
                signal: win.AbortSignal.timeout(15000),
            });
            if (response.status === 202) {
                form.reset();
                previous = undefined;
                status.textContent = copy.success ?? 'Děkujeme, zprávu jsme přijali.';
            } else if (response.status === 429) {
                status.textContent = copy.rateLimited ?? 'Teď přijímáme příliš mnoho zpráv. Zkuste to prosím za chvíli.';
            } else if (response.status === 400) {
                status.textContent = copy.invalid ?? 'Zkontrolujte prosím e-mail a text zprávy.';
            } else {
                status.textContent = copy.error ?? 'Zprávu se nepodařilo odeslat. Zkuste to prosím znovu.';
            }
        } catch {
            status.textContent = copy.error ?? 'Zprávu se nepodařilo odeslat. Zkuste to prosím znovu.';
        } finally {
            pending = false;
            email.readOnly = message.readOnly = button.disabled = false;
        }
    });

    form.hidden = false;
}
