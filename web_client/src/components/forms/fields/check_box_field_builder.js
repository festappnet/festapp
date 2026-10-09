import { sanitizeHtml } from '../../../utils/html.js';
import { OptionBuilderHelper } from './option_builder_helper.js';

export class CheckBoxFieldBuilder {
    static create(field, formModel) {
        const container = document.createElement('div');
        container.className = 'form-field-container checkbox-field-container';
        if (field.isHidden) container.style.display = 'none';

        const isCard = OptionBuilderHelper.isCardDesign(field, formModel);

        // Label
        if (!field._hideLabel) {
            container.appendChild(OptionBuilderHelper.buildFieldLabel(field));
        }

        // Description
        if (field.description) {
            container.appendChild(OptionBuilderHelper.buildFieldDescription(field));
        }

        // Options
        const optionsContainer = document.createElement('div');
        optionsContainer.className = 'checkbox-options';

        if (field.options) {
            field.options.forEach(opt => {
                const wrapper = OptionBuilderHelper.buildOptionWrapper(field, opt, formModel, 'checkbox', isCard);
                optionsContainer.appendChild(wrapper);
            });
        }

        container.appendChild(optionsContainer);

        // Single Boolean Checkbox (e.g. Terms & Conditions)
        if (!field.options || field.options.length === 0) {
            const optWrapper = document.createElement('div');
            optWrapper.className = 'form-check single-checkbox';

            const input = document.createElement('input');
            input.type = 'checkbox';
            input.name = field.id.toString();
            input.id = `field_${field.id}`;
            input.className = 'form-check-input';
            if (field.isRequired) input.required = true;

            const optLabel = document.createElement('label');
            optLabel.htmlFor = input.id;
            optLabel.className = 'form-check-label';
            optLabel.textContent = field.title || '';
            if (field.isRequired) {
                const star = document.createElement('span');
                star.className = 'required-star';
                star.textContent = ' *';
                optLabel.appendChild(star);
            }

            optWrapper.appendChild(input);
            optWrapper.appendChild(optLabel);
            container.appendChild(optWrapper);

            if (field.description) {
                const desc = document.createElement('div');
                desc.className = 'form-field-description';
                desc.style.marginLeft = '1.5em';
                desc.innerHTML = sanitizeHtml(field.description);
                container.appendChild(desc);
            }
        }

        // Error message placeholder
        const error = document.createElement('div');
        error.className = 'form-field-error';
        error.style.display = 'none';
        container.appendChild(error);

        return container;
    }
}
