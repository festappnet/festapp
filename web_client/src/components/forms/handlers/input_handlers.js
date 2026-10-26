import { IdDocumentConstants } from '../constants/id_document_constants.js';

export class InputHandler {
    /**
     * @param {FormSession} session 
     * @param {HTMLElement} target 
     * @param {HTMLFormElement} form 
     * @param {string} fieldId 
     * @param {Object} context - Extra context (like isExpiry boolean)
     */
    handle(session, target, form, fieldId, context) {
        throw new Error("Method 'handle' must be implemented.");
    }
}

export class StandardInputHandler extends InputHandler {
    handle(session, target, form, fieldId, context) {
        const formModel = session.formModel;
        
        // Find field definition
        const field = formModel.visibleFields.find(f => String(f.id) === fieldId);
        if (!field) return; 

        // Get value(s)
        let val = target.value;
        const type = target.type;
        
        // For Checkboxes/SelectMany, we must read the group state
        if (type === 'checkbox' || field.type === 'select_many') {
            const checked = form.querySelectorAll(`input[name="${fieldId}"]:checked`);
            const vals = Array.from(checked).map(c => c.value);
            val = vals.length > 1 ? vals.join(' | ') : (vals[0] || '');
            
            if (vals.length === 0) val = null;
        }

        // UPDATE STATE
        if (['select_one', 'select_many'].includes(field.type)) {
            session.state.fields.set(String(fieldId), val ?? (field.type === 'select_many' ? [] : ''));
        } else if (val) {
            session.state.fields.set(String(fieldId), val);
        } else {
            session.state.fields.delete(String(fieldId));
        }

        // SYNC & CALC
        // Accessing private/protected methods of session via binding or public API?
        // FormSession methods _syncPayloadFromState and _recalculate are effectively internal public.
        // We assume session instance is passed.
        session._syncPayloadFromState();
        session._recalculate();
    }
}

export class IdDocumentInputHandler extends InputHandler {
    handle(session, target, form, fieldId, context) {
        const isExpiry = context && context.isExpiry;
        
        let current = session.state.fields.get(String(fieldId));
        
        // Ensure structure is object or initialize new
        if (!current || typeof current !== 'object') {
            const existingNum = (typeof current === 'string') ? current : '';
            current = { id_document_number: existingNum }; 
        } else {
            current = { ...current }; // Clone
        }
        
        if (isExpiry) {
            current.id_document_expiry_date = target.value;
        } else {
            current.id_document_number = target.value;
        }
        
        session.state.fields.set(String(fieldId), current);
        session._syncPayloadFromState();
        session._recalculate(); 
    }
}
