import { sanitizeHtml } from '../../../utils/html.js';
import flatpickr from "flatpickr";
// import 'flatpickr/dist/flatpickr.min.css'; // Commented out for Node.js test runner (JSDOM) compatibility
import { Czech } from "flatpickr/dist/l10n/cs.js";
import { LocalizationService } from '../../../services/localization_service.js';
import { FormStrings } from '../form_strings.js';
import { TextFieldBuilder } from './text_field_builder.js';
import { CommonStrings } from '../../shared/common_strings.js';
import { DateFieldBuilder } from './date_field_builder.js';
import { FormFieldBuilder } from './form_field_builder.js';
import { IdDocumentConstants } from '../constants/id_document_constants.js';

export class IdDocumentFieldBuilder {
    static create(field, formModel) {
        // Check if we should split into cards (Card Design Mode)
        const isCardDesign = formModel.isCardDesign;

        // -- Common Element Builders --
        
        // ID Section
        const idLabel = document.createElement('label');
        idLabel.className = 'form-field-label';
        idLabel.textContent = field.title;
        if (field.isRequired) {
            const star = document.createElement('span');
            star.className = 'required-star';
            star.textContent = ' *';
            idLabel.appendChild(star);
        }

        const idWrapper = document.createElement('div');
        idWrapper.className = 'input-wrapper';
        const idInput = document.createElement('input');
        idInput.type = 'text';
        idInput.name = field.id.toString();
        idInput.className = 'form-control';
        if (field.isRequired) idInput.required = true;
        const isInformal = formModel?.communicationTone === 'informal';
        idInput.placeholder = isInformal ? FormStrings.typeHere_informal : FormStrings.typeHere;
        idWrapper.appendChild(idInput);

        const idDesc = field.description ? document.createElement('div') : null;
        if (idDesc) {
            idDesc.className = 'form-field-description';
            idDesc.innerHTML = sanitizeHtml(field.description);
        }

        // Expiry Section
        const showExpiry = field.showExpiryDate || field.show_expiry_date || field.data?.showExpiryDate || field.data?.show_expiry_date;
        let expiryElements = null;

        if (showExpiry) {
            const expiryLabel = document.createElement('label');
            expiryLabel.className = 'form-field-label';
            const customLabel = field.expiryDateLabel || field.expiry_date_label || field.data?.expiryDateLabel || field.data?.expiry_date_label;
            expiryLabel.textContent = (customLabel && customLabel.trim() !== '') ? customLabel : FormStrings.expiryDate;
            
            const expiryWrapper = document.createElement('div');
            expiryWrapper.className = 'input-wrapper';
            const expiryInput = document.createElement('input');
            expiryInput.type = 'text';
            // Use Constant
            expiryInput.name = field.id.toString() + IdDocumentConstants.EXPIRY_SUFFIX;
            expiryInput.className = 'form-control flatpickr-input';
            if (field.isRequired) {
                expiryInput.required = true;
                expiryInput.dataset.required = 'true';
            }
            expiryInput.placeholder = LocalizationService.currentLocale === 'cs' ? 'D. M. RRRR' : 'YYYY-MM-DD';
            expiryInput.autocomplete = 'off'; // Let Flatpickr handle it
            expiryWrapper.appendChild(expiryInput);

            const errorContainer = document.createElement('div');
            errorContainer.className = 'form-field-error';
            errorContainer.style.display = 'none';

            // Flatpickr Init
            const validateExpiry = (date) => {
                if (!date) {
                    errorContainer.style.display = 'none';
                    expiryInput.setCustomValidity("");
                    expiryInput.classList.remove('invalid');
                    return;
                }
                const today = new Date();
                today.setHours(0, 0, 0, 0);
                if (date < today) {
                    const msg = FormStrings.expiryDatePastError;
                    errorContainer.textContent = msg;
                    errorContainer.style.display = 'block';
                    expiryInput.setCustomValidity(msg);
                    expiryInput.classList.add('invalid');
                } else {
                    errorContainer.style.display = 'none';
                    expiryInput.setCustomValidity("");
                    expiryInput.classList.remove('invalid');
                }
            };
                
            flatpickr(expiryInput, {
                dateFormat: 'Y-m-d',
                altInput: true,
                altFormat: LocalizationService.currentLocale === 'cs' ? 'j. n. Y' : 'F j, Y',
                allowInput: true,
                minDate: 'today',
                disableMobile: true, // Force custom picker (User Requirement: Same as Birthdate)
                locale: LocalizationService.currentLocale === 'cs' ? Czech : 'default',
                parseDate: (datestr, format) => {
                    // Custom parser to allow more flexible input (e.g. "1.1.2000" -> "1. 1. 2000")
                    try {
                        // 1. Try default parsing first
                        const defaultDate = flatpickr.parseDate(datestr, format);
                        if (defaultDate) return defaultDate;
                    } catch (e) { }

                    // 2. Try simple fallback for common formats if default failed
                    if (datestr && typeof datestr === 'string') {
                         // Fix common "lazy" input: "1.1.2000" -> "2000-01-01"
                        if (datestr.match(/^\d{1,2}\.\d{1,2}\.\d{4}$/)) {
                            const parts = datestr.split('.');
                            return new Date(`${parts[2]}-${parts[1]}-${parts[0]}`);
                        }
                        // "1. 1. 2000" check handled by default parser usually, but just in case
                        if (datestr.match(/^\d{1,2}\. \d{1,2}\. \d{4}$/)) {
                            const parts = datestr.replace(/ /g, '').split('.');
                            return new Date(`${parts[2]}-${parts[1]}-${parts[0]}`);
                        }
                    }
                    return undefined;
                },
                onChange: function(selectedDates) {
                    validateExpiry(selectedDates[0]);
                }
            });

            expiryElements = { label: expiryLabel, wrapper: expiryWrapper, error: errorContainer };
        }


        // -- Layout Construction --

        // Layout: Standard (Single container) ensuring both fields are in one block
        // FormFieldBuilder will wrap this in a card if isCardDesign is true.
        const container = document.createElement('div');
        container.className = 'form-field-container';
        if (field.isHidden) container.style.display = 'none';

        container.appendChild(idLabel);
        if (idDesc) container.appendChild(idDesc);
        container.appendChild(idWrapper);

        if (showExpiry && expiryElements) {
            const spacer = document.createElement('div');
            spacer.style.height = '8px';
            container.appendChild(spacer);

            container.appendChild(expiryElements.label);
            container.appendChild(expiryElements.wrapper);
            container.appendChild(expiryElements.error);
        }

        return container;
    }
}
