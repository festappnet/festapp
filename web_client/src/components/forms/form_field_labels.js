import { FormStrings } from './form_strings.js';

// Input fields and checkout use the same localized fallback labels.
export function formFieldTitle(field) {
    if (typeof field.title === 'string' && field.title.trim()) return field.title.trim();
    const type = field.type;
    switch (type) {
        case 'name': return FormStrings.fieldName;
        case 'surname': return FormStrings.fieldSurname;
        case 'email': return FormStrings.fieldEmail;
        case 'phone': return FormStrings.fieldPhone;
        case 'city': return FormStrings.fieldCity;
        case 'birth_year': return FormStrings.fieldBirthYear;
        case 'birth_date': return FormStrings.fieldBirthDate;
        case 'note': return FormStrings.fieldNote;
        case 'address': return FormStrings.fieldAddress;
        case 'nationality': return FormStrings.fieldNationality;
        case 'sex': return FormStrings.sexLabel;

        case 'id_document': return FormStrings.fieldIdDocument;
        default: return '';
    }
}
