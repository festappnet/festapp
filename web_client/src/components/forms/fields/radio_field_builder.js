import { FormStrings } from '../form_strings.js';
import { OptionBuilderHelper } from './option_builder_helper.js';

export class RadioFieldBuilder {
    static create(field, formModel) {
        const container = document.createElement('div');
        container.className = 'form-field-container radio-field';

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
        optionsContainer.className = 'radio-options';

        const isCard = OptionBuilderHelper.isCardDesign(field, formModel);

        if (field.options) {
            field.options.forEach(opt => {
                const wrapper = OptionBuilderHelper.buildOptionWrapper(field, opt, formModel, 'radio', isCard);

                // Pre-selected value
                const input = wrapper.querySelector('input');
                const optionValue = (opt.id !== undefined && opt.id !== null) ? opt.id : opt.title;
                if (field.value !== undefined && field.value !== null && String(optionValue) === String(field.value)) {
                    input.checked = true;
                }

                optionsContainer.appendChild(wrapper);
            });
        }

        container.appendChild(optionsContainer);

        // Clear Selection
        const clearBtn = document.createElement('button');
        clearBtn.type = 'button';
        clearBtn.className = 'btn-clear-selection';
        clearBtn.innerText = FormStrings.clearSelection;

        container.addEventListener('change', (e) => {
            if (e.target.name == field.id && e.target.type === 'radio') {
                const anyChecked = container.querySelector(`input[name="${field.id}"]:checked`);
                clearBtn.style.display = anyChecked ? 'inline-block' : 'none';
            }
        });

        const initialChecked = container.querySelector('input:checked');
        if (initialChecked) {
             clearBtn.style.display = 'inline-block';
        }

        clearBtn.onclick = () => {
            const radios = container.querySelectorAll(`input[type="radio"][name="${field.id}"]`);
            radios.forEach(r => r.checked = false);
            clearBtn.style.display = 'none';

            container.setAttribute('name', field.id);
            container.name = String(field.id);
            container.value = null;

            container.dispatchEvent(new Event('input', { bubbles: true }));
            container.dispatchEvent(new Event('change', { bubbles: true }));
        };

        container.appendChild(clearBtn);

        const error = document.createElement('div');
        error.className = 'form-field-error';
        error.style.display = 'none';
        container.appendChild(error);

        return container;
    }
}
