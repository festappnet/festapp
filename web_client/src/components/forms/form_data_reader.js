import { DbForms } from './db_forms.js';
import { IdDocumentConstants } from './constants/id_document_constants.js';

export class FormDataReader {

    /**
     * Extracts data from the DOM using standard FormData API.
     * This method is robust and does NOT rely on DOM structure (divs, classes),
     * only on input 'name' attributes.
     */
    static getPayload(form, formModel) {
        const formData = new FormData(form);
        const payload = {
            fields: [],
            ticket: [], // Will be populated by FormSession state, not here
            [DbForms.metaSecret]: formModel.secret, 
            [DbForms.metaForm]: formModel.key
        };

        // Extract Blueprint Secret (if any)
        const blueprintSecret = formData.get('blueprint_secret');
        if (blueprintSecret) {
            payload['secret'] = blueprintSecret; 
        }

        // --- 1. Standard Fields (Non-Ticket) ---
        formModel.relatedFields.forEach(field => {
             if (field.type === 'ticket') return;

             // Special Handling for ID Document (Nested Object)
             if (field.type === 'id_document') {
                 const idVal = formData.get(field.id.toString());
                 // Only add if ID number is present (required or optional but filled)
                 if (idVal && idVal.trim() !== '') {
                     const expiryVal = formData.get(field.id.toString() + IdDocumentConstants.EXPIRY_SUFFIX);
                     
                     const idData = {
                         "id_document_number": idVal,
                         "id_document_expiry_date": (expiryVal && expiryVal.trim() !== '') ? expiryVal : null
                     };

                     let fieldObj = {};
                     fieldObj[field.id.toString()] = idData;
                     payload.fields.push(fieldObj);
                 }
                 return; // Done with this field
             }
             
             // Check if data exists in FormData
             const vals = formData.getAll(field.id.toString());
             // Filter empty strings
             const validVals = vals.filter(v => v !== '');
             
             if (validVals.length > 0) {
                 // Join if multiple (e.g. select_many)
                 const val = validVals.length > 1 ? validVals.join(' | ') : validVals[0];
                 
                 let fieldObj = {};
                 fieldObj[field.id.toString()] = val;
                                  // Attach currency if single value (complex logic for multi-currency items is rare/unsupported on standard fields)
                  if (validVals.length === 1) {
                       const opt = FormDataReader._findOption(field, validVals[0]);
                       if (opt) {
                           const c = opt.currency || opt.currencyCode || opt.currency_code;
                           if (c) fieldObj['currency_code'] = c;
                       }
                  }

                 payload.fields.push(fieldObj);
             }
        });

        // --- 3. Hoist Email ---
        const emailField = formModel.visibleFields.find(f => f.type === 'email');
        if (emailField) {
            const emailEntry = payload.fields.find(f => f[emailField.id.toString()] !== undefined);
            if (emailEntry) {
                payload['email'] = emailEntry[emailField.id.toString()];
            }
        }

        return payload;
    }

    /**
     * Extracts ONLY ticket data from DOM for initial hydration.
     * Use this ONCE on load, then trust FormSession.state.
     */
    static getTicketDataFromDom(form, formModel) {
        const formData = new FormData(form);
        const ticketData = {}; 

        for (const [key, value] of formData.entries()) {
            if (value === '') continue; // Skip empty values early

            const match = key.match(/^(\d+)_(\d+)_(.+)$/);
            if (match) {
                const ticketId = match[1];
                const index = parseInt(match[2], 10);
                const subId = match[3];

                if (!ticketData[ticketId]) ticketData[ticketId] = [];
                if (!ticketData[ticketId][index]) ticketData[ticketId][index] = {};
                
                if (!ticketData[ticketId][index][subId]) ticketData[ticketId][index][subId] = [];
                ticketData[ticketId][index][subId].push(value);
            }
        }

        const initialTickets = [];

        // Now iterate the model to reconstruct objects in correct order/structure
        formModel.visibleFields.forEach(field => {
            if (field.type !== 'ticket') return;

            const ticketsForField = ticketData[field.id.toString()];
            if (!ticketsForField) return;

            Object.keys(ticketsForField).forEach(indexKey => {
                const subFieldsData = ticketsForField[indexKey]; // { subId: [values] }
                const ticketObj = { fields: [] };
                // Preserve the original DOM index so Validator can target the correct input
                ticketObj['_ticketIndex'] = indexKey; 
                
                let hasData = false;

                // We need definitions to know types (spot vs standard)
                const subDefinitions = field.subFields || field.fields || (field.data && field.data.fields) || [];

                subDefinitions.forEach(sub => {
                    const rawVals = subFieldsData[sub.id.toString()];
                    if (!rawVals || rawVals.length === 0) return;

                    hasData = true;

                    // --- Processing Logic Same as Before ---
                    if (sub.type === 'spot') {
                        const val = rawVals[0]; // ID is usually string or number
                        ticketObj['spot'] = val;
                        
                        // Extract Price: Try Option Lookup First (Reliable for Variants)
                        const opt = FormDataReader._findOption(sub, val);
                        if (opt && opt.price !== undefined) {
                            ticketObj['spotPrice'] = parseFloat(opt.price);
                        } else {
                            // Fallback to DOM dataset (legacy/Seat logic)
                             const inputName = `${field.id}_${indexKey}_${sub.id}`;
                             // For Radio, we need the CHECKED one matching value
                             const inputEl = form.querySelector(`input[name="${inputName}"][value="${val}"]`) || 
                                             form.querySelector(`input[name="${inputName}"]`);
                             
                             if (inputEl) {
                                 if (inputEl.dataset.price) {
                                     ticketObj['spotPrice'] = parseFloat(inputEl.dataset.price);
                                 }
                                 if (inputEl.dataset.name) {
                                     ticketObj['spotName'] = inputEl.dataset.name;
                                 }
                             }
                        }
                    }
                    else if (sub.type === 'product_type') {
                        // Product Types (always array of objects)
                        rawVals.forEach(v => {
                             const fObj = FormDataReader._createSubFieldObj(sub, v);
                             
                             // Fallback: If price missing, check DOM dataset
                             if (fObj.price === undefined) {
                                 const inputName = `${field.id}_${indexKey}_${sub.id}`;
                                 const inputEl = form.querySelector(`input[name="${inputName}"][value="${v}"]`) || 
                                                 form.querySelector(`option[value="${v}"]`); // Select?
                                 
                                 if (inputEl && inputEl.dataset && inputEl.dataset.price) {
                                     fObj.price = parseFloat(inputEl.dataset.price);
                                     const c = inputEl.dataset.currency || inputEl.dataset.currencyCode; 
                                     if (c) fObj.currency_code = c;
                                 }
                             }
                             ticketObj.fields.push(fObj);
                        });
                    } 
                    else {
                        // Standard Sub Fields
                        const hasPrices = (sub.options || (sub.data && sub.data.options) || []).some(o => o.price);
                        
                        if (hasPrices && rawVals.length > 1) {
                            // Multiple priced items -> separate entries
                            rawVals.forEach(v => {
                                ticketObj.fields.push(FormDataReader._createSubFieldObj(sub, v));
                            });
                        } else {
                            // Single entry (joined or single)
                            const val = rawVals.length > 1 ? rawVals.join(' | ') : rawVals[0];
                            if (rawVals.length === 1) {
                                ticketObj.fields.push(FormDataReader._createSubFieldObj(sub, val));
                            } else {
                                // Multi-value but single field entry (e.g. checkbox list without prices)
                                ticketObj.fields.push(FormDataReader._createSubFieldObj(sub, val));
                            }
                        }
                    }
                });

                if (hasData) {
                    initialTickets.push(ticketObj);
                }
            });
        });

        return initialTickets;
    }

    static _findOption(fieldOrSub, value) {
         let found = null;

         // 1. Product Type Products
         if (fieldOrSub.type === 'product_type' && fieldOrSub.data && fieldOrSub.data.product_type_data && fieldOrSub.data.product_type_data.products) {
              found = fieldOrSub.data.product_type_data.products.find(p => String(p.id) === String(value));
         }
         
         // 2. Standard Options (Fallback)
         if (!found) {
             const options = fieldOrSub.options || (fieldOrSub.data && fieldOrSub.data.options) || [];
             if (options.length > 0) {
                 found = options.find(o => String(o.id) === String(value));
             }
         }
         return found;
    }

    static _createSubFieldObj(sub, val) {
        let fObj = {};
        fObj[sub.type] = val;
        fObj['_subFieldId'] = sub.id; 
        
        const opt = FormDataReader._findOption(sub, val);
        if (opt) {
            const isProduct = sub.type === 'product_type';
            
            if (isProduct) {
                fObj['product_type'] = val;
            }
            
            if (opt.price !== undefined) {
                 fObj['price'] = opt.price;
            }

            const c = opt.currency || opt.currencyCode || opt.currency_code;
            if (c) {
                fObj['currency_code'] = c;
            }
        }
        return fObj;
        return fObj;
    }

}
