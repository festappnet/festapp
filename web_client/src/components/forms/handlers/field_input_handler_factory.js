import { StandardInputHandler, IdDocumentInputHandler } from './input_handlers.js';
import { IdDocumentConstants } from '../constants/id_document_constants.js';

export class FieldInputHandlerFactory {
    static _handlers = {
        'default': new StandardInputHandler(),
        'id_document': new IdDocumentInputHandler()
    };

    /**
     * Resolves the correct handler for a given input name/target.
     * @returns { { handler: InputHandler, fieldId: string, context: Object } }
     */
    static getHandler(formModel, target, name) {
        // 1. Check ID Document Suffix
        if (name.endsWith(IdDocumentConstants.EXPIRY_SUFFIX)) {
             const baseId = name.replace(IdDocumentConstants.EXPIRY_SUFFIX, '');
             // Verify validity
             if (formModel.visibleFields.some(f => String(f.id) === baseId)) {
                 return { 
                     handler: this._handlers['id_document'], 
                     fieldId: baseId, 
                     context: { isExpiry: true } 
                 };
             }
        }
        
        // 2. Check direct Field Type
        const field = formModel.visibleFields.find(f => String(f.id) === name);
        if (field) {
            if (field.type === 'id_document') {
                return { 
                    handler: this._handlers['id_document'], 
                    fieldId: name, 
                    context: { isExpiry: false } 
                };
            }
            // Add specific handlers here if needed (product_type etc)
        }

        // 3. Default
        return { 
            handler: this._handlers['default'], 
            fieldId: name, 
            context: {} 
        };
    }
}
