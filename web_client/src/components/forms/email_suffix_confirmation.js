import { isValidEmail } from '../../logic/email_address.js';
import { classifyEmailDomainSuffix } from '../../logic/email_domain_suffix.js';
import { FormStrings } from './form_strings.js';

// One map per session, separate from payload and blocking validation errors.
export class EmailSuffixConfirmation {
    static eligible(input) {
        if (input.type !== 'email' || input.disabled || input.readOnly) return false;
        const view = input.ownerDocument.defaultView;
        for (let node = input; node; node = node.parentElement) {
            if (node.hidden || view.getComputedStyle(node).display === 'none' || view.getComputedStyle(node).visibility === 'hidden') return false;
        }
        return !input.matches(':disabled');
    }

    static key(input, session) {
        if (input.dataset.subId != null) {
            const ticket = session?.state?.tickets?.[Number(input.dataset.index)];
            return `ticket:${ticket?.id ?? input.dataset.index}:${input.dataset.subId}`;
        }
        return `field:${input.name || input.id}`;
    }

    static refresh(input, states, session, show = false, syntaxValid = input => input.validity.valid && isValidEmail(input.value)) {
        const key = this.key(input, session);
        let state = states.get(key);
        if (!state) { state = { value: input.value, confirmed: false, visible: false }; states.set(key, state); }
        if (state.value !== input.value) { state.value = input.value; state.confirmed = false; }
        if (show) state.visible = true;
        const result = classifyEmailDomainSuffix(input.value);
        const needsConfirmation = this.eligible(input) && input.value.trim() !== '' && syntaxValid(input) && result.status === 'unrecognizedSuffix' && !state.confirmed;
        let warning = input.parentElement.querySelector('[data-email-suffix-warning]');
        if (!warning) {
            warning = input.ownerDocument.createElement('div');
            warning.dataset.emailSuffixWarning = '';
            warning.id = `${input.id || input.name}-suffix-warning`;
            const text = input.ownerDocument.createElement('p');
            text.setAttribute('role', 'status');
            text.setAttribute('aria-live', 'polite');
            const confirm = input.ownerDocument.createElement('button');
            confirm.type = 'button';
            confirm.className = 'btn btn-secondary';
            confirm.textContent = FormStrings.emailSuffixConfirm;
            confirm.addEventListener('click', () => {
                // Re-read the value so a stale UI never confirms a newer value.
                const current = states.get(this.key(input, session));
                if (current?.value !== input.value || !this.eligible(input)) { this.refresh(input, states, session, false, syntaxValid); return; }
                current.confirmed = true;
                this.refresh(input, states, session, false, syntaxValid);
                input.focus();
            });
            warning.append(text, confirm);
            input.after(warning);
            const descriptions = new Set((input.getAttribute('aria-describedby') || '').split(/\s+/).filter(Boolean));
            descriptions.add(warning.id);
            input.setAttribute('aria-describedby', [...descriptions].join(' '));
        }
        const visible = needsConfirmation && state.visible;
        if (warning.hidden !== !visible) warning.hidden = !visible;
        const message = visible ? FormStrings.emailSuffixWarning(result.suffix, session?.formModel?.communicationTone === 'informal') : '';
        if (warning.firstElementChild.textContent !== message) warning.firstElementChild.textContent = message;
        return needsConfirmation;
    }

    static install(form, states, session, syntaxValid) {
        const refreshAll = () => form.querySelectorAll('input[type="email"]').forEach(input => this.refresh(input, states, session, false, syntaxValid));
        for (const event of ['input', 'change', 'blur']) form.addEventListener(event, e => {
            if (e.target.type === 'email') this.refresh(e.target, states, session, event === 'blur', syntaxValid);
        }, event === 'blur');
        refreshAll();
        // Ticket widgets can replace controls while the enclosing session survives.
        const Observer = form.ownerDocument.defaultView.MutationObserver;
        const observer = new Observer(refreshAll);
        observer.observe(form, { childList: true, subtree: true });
        return () => observer.disconnect();
    }

    static validate(form, states, session, syntaxValid) {
        for (const input of form.querySelectorAll('input[type="email"]')) {
            if (this.refresh(input, states, session, true, syntaxValid)) {
                const warning = input.parentElement.querySelector('[data-email-suffix-warning]');
                warning.scrollIntoView?.({ block: 'center', behavior: 'smooth' });
                warning.querySelector('button').focus();
                return false;
            }
        }
        return true;
    }
}
