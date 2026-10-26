import { sanitizeHtml } from '../../../utils/html.js';
import flatpickr from "flatpickr";
// import 'flatpickr/dist/flatpickr.min.css'; // Commented out for Node.js test runner (JSDOM) compatibility
import { Czech } from "flatpickr/dist/l10n/cs.js";
import { ThemeService } from '../../../services/theme_service.js';
import { FormStrings } from '../form_strings.js';
import { LocalizationService } from '../../../services/localization_service.js';

export class DateFieldBuilder {
    static create(field, formModel) {
        const container = document.createElement('div');
        container.className = 'form-field-container';
        if (field.isHidden) container.style.display = 'none';

        // Label
        const label = document.createElement('label');
        label.className = 'form-field-label';
        label.textContent = FormStrings.fieldBirthDate;
        if (field.isRequired) {
            const star = document.createElement('span');
            star.className = 'required-star';
            star.textContent = ' *';
            label.appendChild(star);
        }
        container.appendChild(label);

        // Description
        if (field.description) {
            const desc = document.createElement('div');
            desc.className = 'form-field-description';
            desc.innerHTML = sanitizeHtml(field.description);
            container.appendChild(desc);
        }

        const wrapper = document.createElement('div');
        wrapper.className = 'input-wrapper';

        // Date format hint
        const hint = document.createElement('div');
        hint.className = 'form-field-hint';
        hint.textContent = FormStrings.birthDateFormatHint;
        wrapper.appendChild(hint);

        // Input
        // Use text type for Flatpickr, but keep name/required
        const input = document.createElement('input');
        input.type = 'text'; // Flatpickr works best with text input
        input.name = field.id.toString();
        input.className = 'form-control flatpickr-input';
        if (field.isRequired) input.required = true;
        input.placeholder = FormStrings.typeHere; // Or date pattern
        
        // Autocomplete
        input.autocomplete = 'off'; // Let Flatpickr handle it
        
        wrapper.appendChild(input);

        // Age Validation Logic & Limits (Validation ONLY, no picker restriction)
        const minYear = field.data?.min_year || 0;
        const maxYear = field.data?.max_year || 0;
        const isHard = field.data?.is_hard === true;
        const customMessage = field.data?.message;

        let minDateObj = undefined;
        let maxDateObj = undefined;

        if (minYear > 0 || maxYear > 0) {
            // Determine event date
            let eventDate = new Date();
            if (formModel.start) {
                eventDate = new Date(formModel.start);
            }

            // Calculate range for VALIDATION
            const stripTime = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

            if (maxYear > 0) {
                 const d = new Date(eventDate.getFullYear() - maxYear, eventDate.getMonth(), eventDate.getDate());
                 minDateObj = stripTime(d);
            }
            if (minYear > 0) {
                 const d = new Date(eventDate.getFullYear() - minYear, eventDate.getMonth(), eventDate.getDate());
                 maxDateObj = stripTime(d);
            }
        }

        container.appendChild(wrapper);

        // Message placeholder (for warnings/errors)
        const messageContainer = document.createElement('div');
        messageContainer.className = 'form-field-message'; // Reusing message container name but using error style class if hard
        messageContainer.style.display = 'none';
        messageContainer.style.marginTop = '4px';
        messageContainer.style.fontSize = '0.85em';
        container.appendChild(messageContainer);

        // Native Error placeholder (for standard validation like "required")
        const error = document.createElement('div');
        error.className = 'form-field-error';
        error.style.display = 'none';
        container.appendChild(error);

        // Validation Logic for Age (Custom). Declared before Flatpickr so onChange can call it.
        let validateAge = null;
        if (minYear > 0 || maxYear > 0) {
            validateAge = () => {
                const val = input.value;
                if (!val) {
                    messageContainer.style.display = 'none';
                    input.setCustomValidity("");
                    input.classList.remove('invalid');
                    input.style.borderColor = '';
                    return;
                }

                const selectedDate = new Date(val);
                const checkDate = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate());

                let isOutside = false;
                if (minDateObj && checkDate < minDateObj) isOutside = true;
                if (maxDateObj && checkDate > maxDateObj) isOutside = true;

                if (isOutside) {
                    let msg = '';
                    if (customMessage && customMessage.trim() !== '') {
                        msg = customMessage
                            .replace('{minAge}', minYear)
                            .replace('{maxAge}', maxYear);
                    } else if (isHard) {
                        msg = FormStrings.birthDateError(minYear, maxYear);
                    } else {
                        msg = FormStrings.birthDateWarning(minYear, maxYear);
                    }

                    messageContainer.textContent = msg;
                    messageContainer.style.display = 'block';

                    if (isHard) {
                        messageContainer.style.color = 'var(--red-color)';
                        messageContainer.classList.add('form-field-error');
                        input.setCustomValidity(msg);
                        input.classList.add('invalid');
                    } else {
                        const warnColor = ThemeService.warningColor || '#ed6c02';
                        messageContainer.style.color = warnColor;
                        input.setCustomValidity("");
                        input.classList.remove('invalid');
                        input.style.borderColor = warnColor;
                    }
                } else {
                    messageContainer.style.display = 'none';
                    input.setCustomValidity("");
                    input.classList.remove('invalid');
                    input.style.borderColor = '';
                }
            };
        }

        // Initialize Flatpickr (after validateAge so onChange can reference it)
        const fpInstance = flatpickr(input, {
                dateFormat: 'Y-m-d',
                altInput: true,
                altFormat: LocalizationService.currentLocale === 'cs' ? 'j. n. Y' : 'F j, Y',
                allowInput: true,
                disableMobile: true,
                locale: LocalizationService.currentLocale === 'cs' ? Czech : 'default',
                parseDate: (datestr, format) => {
                    try {
                        const defaultDate = flatpickr.parseDate(datestr, format);
                        if (defaultDate) return defaultDate;
                    } catch (e) { }
                    if (datestr && typeof datestr === 'string') {
                        if (datestr.match(/^\d{1,2}\.\d{1,2}\.\d{4}$/)) {
                            const parts = datestr.split('.');
                            return new Date(`${parts[2]}-${parts[1]}-${parts[0]}`);
                        }
                        if (datestr.match(/^\d{1,2}\. \d{1,2}\. \d{4}$/)) {
                            const parts = datestr.replace(/ /g, '').split('.');
                            return new Date(`${parts[2]}-${parts[1]}-${parts[0]}`);
                        }
                    }
                    return undefined;
                },
                maxDate: maxDateObj || 'today',
                defaultDate: input.value || undefined,
                onChange: () => { if (validateAge) validateAge(); },
                onClose: () => { if (validateAge) validateAge(); },
        });

        if (validateAge) {
            // Initial validation if a value is already set
            if (input.value) validateAge();

            // Listen on original input (Flatpickr propagates) and altInput (user types here on PC)
            input.addEventListener('input', validateAge);
            input.addEventListener('change', validateAge);
            if (fpInstance && fpInstance.altInput) {
                fpInstance.altInput.addEventListener('input', validateAge);
                fpInstance.altInput.addEventListener('blur', validateAge);
            }
        }

        return container;
    }
}
