import { TextFieldBuilder } from './text_field_builder.js';
import { RadioFieldBuilder } from './radio_field_builder.js';
import { CheckBoxFieldBuilder } from './check_box_field_builder.js';
import { TicketFieldBuilder } from './ticket_field_builder.js';
import { DateFieldBuilder } from './date_field_builder.js';
import { IdDocumentFieldBuilder } from './id_document_field_builder.js';
import { formFieldTitle } from '../form_field_labels.js';
import { FormStrings } from '../form_strings.js';

export class FormFieldBuilder {

    static createFormField(field, formModel, session) {
        const waitingProduct = formModel.registrationMode === 'waitlist' &&
            (['product_type', 'spot'].includes(field.type) || field.productTypeId || field.data?.product_dependent);
        if (waitingProduct) field = { ...field, isRequired: false, value: null, data: { ...field.data, default_value: null } };
        // Auto-Title Logic
        field.title = formFieldTitle(field);

        let fieldComponent = null;

        switch (field.type) {
            case 'text':
            case 'name':
            case 'surname':
            case 'city':
            case 'email':
            case 'phone':
            case 'birth_year':
            case 'note':
            case 'address': 
            case 'nationality': 
                fieldComponent = TextFieldBuilder.create(field, formModel);
                break;
            case 'id_document': 
                fieldComponent = IdDocumentFieldBuilder.create(field, formModel);
                break;
            case 'sex':
                 if (!field.options || field.options.length === 0) {
                     field.options = [
                         { id: 'male', title: FormStrings.maleLabel },
                         { id: 'female', title: FormStrings.femaleLabel }
                     ];
                     if (!field.isRequired) {
                         field.options.unshift({ id: '', title: FormStrings.notSpecifiedLabel });
                     }
                }
                fieldComponent = RadioFieldBuilder.create(field, formModel);
                break;
            case 'select_one':
                fieldComponent = RadioFieldBuilder.create(field, formModel);
                break;
            case 'select_many':
                fieldComponent = CheckBoxFieldBuilder.create(field, formModel);
                break;
            case 'product_type':
                 if (field.data && field.data.selection_type === 'select_many') {
                     fieldComponent = CheckBoxFieldBuilder.create(field, formModel);
                 } else {
                     fieldComponent = RadioFieldBuilder.create(field, formModel);
                 }
                 break;
            case 'spot':
                // Simple fallback: If options exist, use Radio, else Text (hidden id?)
                // Usually spots are handled via UI map, but for basic data flow:
                if (field.options && field.options.length > 0) {
                    fieldComponent = RadioFieldBuilder.create(field, formModel);
                } else {
                    fieldComponent = TextFieldBuilder.create(field, formModel);
                }
                break;
            case 'ticket':
                fieldComponent = TicketFieldBuilder.create(field, formModel, session);
                break;
            case 'birth_date':
                fieldComponent = DateFieldBuilder.create(field, formModel);
                break;
            default:
                console.warn(`Field type ${field.type} not supported yet.`);
                if (['text', 'string'].includes(field.type)) {
                     fieldComponent = TextFieldBuilder.create(field, formModel);
                }
                break;
        }

        if (!fieldComponent) return document.createElement('div');

        if (waitingProduct) {
            const disabled = document.createElement('fieldset');
            disabled.disabled = true;
            disabled.className = 'waitlist-product-options';
            disabled.setAttribute('aria-describedby', 'waitlist-product-reason');
            fieldComponent.querySelectorAll('input,select,textarea,button').forEach(input => {
                input.disabled = true;
                input.required = false;
                if ('checked' in input) input.checked = false;
            });
            fieldComponent.querySelectorAll('.btn-clear-selection').forEach(button => button.remove());
            disabled.appendChild(fieldComponent);
            fieldComponent = disabled;
        }
        const isCard = FormFieldBuilder.isCardDesign(formModel, field);
        
        if (isCard) {
            if (fieldComponent.dataset.skipCardWrapping === 'true') {
                return fieldComponent;
            }
            return FormFieldBuilder.wrapInCard(field, fieldComponent);
        }
        
        return fieldComponent;
    }

    static isCardDesign(formModel, field) {
        if (formModel.isCardDesign) return true;
        if (field.description && field.description.trim().length > 0) return true;
        
        // Check for option descriptions in potential list fields
        if (['select_one', 'select_many', 'sex'].includes(field.type)) {
            if (field.options && field.options.some(opt => opt.description && opt.description.trim().length > 0)) {
                return true;
            }
        }
        
        return false;
    }

    static wrapInCard(field, contentElement) {
        const card = document.createElement('div');
        card.className = 'form-field-card'; 
        card.appendChild(contentElement);
        return card;
    }
}
