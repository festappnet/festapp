import { isValidEmail } from '../../logic/email_address.js';
import { EmailSuffixConfirmation } from './email_suffix_confirmation.js';
import { FormStrings } from './form_strings.js';
import { FormHelper } from './form_helper.js';

export class FormValidator {

    static handleInputValidation(e, form, session) {
         if (!session) return;
         
         const target = e.target;
         const fieldName = target.name;
         if (!fieldName) return;
         
         const currentErrors = { ...session.state.validationErrors };
         const hadError = !!currentErrors[fieldName];
         // Logic: If field HAD error, we must validate on input. 
         if (!hadError && !target.classList.contains('invalid') && !(target.type === 'email' && e.type === 'blur')) return;

         const isRequired = target.dataset.required === 'true';
         let nowValid = true; // Default to valid unless proven otherwise
         let failureReason = null;
         
         if (target.type === 'radio' || target.type === 'checkbox') {
             // For Checkbox/Radio, we need to check group if required
             // But usually required applies to the GROUP. 
             // If individual checkbox is required (e.g. Terms), check checked.
             if (target.type === 'checkbox' && isRequired) {
                 nowValid = target.checked;
                 if (!nowValid) failureReason = FormStrings.fieldCannotBeEmpty;
             } else if (target.type === 'radio' && isRequired) {
                 const group = form.querySelectorAll(`input[name="${fieldName}"]`);
                 nowValid = Array.from(group).some(i => i.checked);
                 if (!nowValid) failureReason = FormStrings.fieldCannotBeEmpty;
             }
         } else {
             // Text/Select inputs
             // Check Required
             if (isRequired) {
                 if (!target.value || target.value.trim() === '') {
                     nowValid = false;
                     failureReason = FormStrings.fieldCannotBeEmpty;
                 }
             }
             
             // Check invalid format if needed
             if (nowValid && target.value) {
                 // Only check format if we have a value
                 if (target.type === 'email' && !isValidEmail(target.value)) {
                     nowValid = false;
                     failureReason = FormStrings.invalidFormat;
                 } else if (!target.checkValidity()) {
                      // It is invalid natively (e.g. pattern or type)
                      // distiguish error
                      if (target.validity.typeMismatch || target.validity.patternMismatch) {
                          nowValid = false;
                          failureReason = FormStrings.invalidFormat;
                      }
                      // we ignore valueMissing here because we checked it manually above (or didn't require it)
                      // wait, if we used manual check for required, native checkValidity might still say valid if no required attr.
                      // correct.
                 }
             }
         }
         
         if (nowValid) {
             if (currentErrors[fieldName]) {
                 delete currentErrors[fieldName];
                 session.setValidationErrors(currentErrors);
             }
             
             // Immediate DOM cleanup to ensure responsiveness
             target.classList.remove('invalid');
             const container = target.closest('.form-field-container');
             if (container) {
                 const errorDiv = container.querySelector('.form-field-error');
                 if (errorDiv) errorDiv.style.display = 'none';
                 const optionsContainer = container.querySelector('.radio-options, .checkbox-options');
                 if (optionsContainer) optionsContainer.classList.remove('invalid');
             }
         } else {

             // Check validation message
             let message = failureReason || target.validationMessage || FormStrings.fieldCannotBeEmpty;
             
             // Update State
             currentErrors[fieldName] = message;
             session.setValidationErrors(currentErrors);
             
             // Immediate DOM Update (Restoration)
             target.classList.add('invalid');
             const container = target.closest('.form-field-container');
             if (container) {
                 const errorDiv = container.querySelector('.form-field-error');
                 if (errorDiv) {
                     errorDiv.textContent = message;
                     errorDiv.style.display = 'block';
                 }
                 
                 // Fix: Ensure options container (radios/checkboxes) gets invalid class too
                 const optionsContainer = container.querySelector('.radio-options, .checkbox-options');
                 if (optionsContainer) {
                     optionsContainer.classList.add('invalid');
                 }
             }
         }
    }

    /**
     * Extracts values for a specific subfield from a ticket item
     * @param {Object} ticketItem - The ticket object from payload
     * @param {Object} subFieldDef - The subfield definition
     * @returns {Array} Array of selected values (strings/IDs)
     */
    static getTicketFieldValues(ticketItem, subFieldDef) {
        const values = [];
        
        // 1. Direct Field Access: Spot
        if (subFieldDef.type === 'spot') {
            if (ticketItem.spot) {
                // Spot is selected
                values.push(ticketItem.spot);
            }
            return values;
        }
        
        // 2. Nested 'fields' array (Standard for Festapp)
        if (ticketItem.fields) {
            ticketItem.fields.forEach(fObj => {
                const id = String(subFieldDef.id);
                if (fObj._subFieldId != null && String(fObj._subFieldId) !== id) return;
                const hasId = Object.hasOwn(fObj, id);
                if (!hasId && fObj._subFieldId == null && Object.keys(fObj).some(key => /^\d+$/.test(key))) return;
                // Stable ID and legacy type are aliases of one answer, never two selections.
                const val = hasId ? fObj[id] : fObj[subFieldDef.type];
                const selected = Array.isArray(val) ? val : (typeof val === 'string' ? val.split(' | ') : [val]);
                values.push(...selected.filter(value => value !== null && value !== undefined && value !== ''));

            });
        }
        
        return values;
    }

    /**
     * @returns {boolean} true if valid, false if invalid (and errors shown)
     */
    static validateAndShowErrors(form, formModel, session) {
            const errors = {}; // { fieldId: message }

            // 1. HTML5 Validity Check
            const elements = form.elements;
            for (let i = 0; i < elements.length; i++) {
                const el = elements[i];
                if (el.nodeName === 'BUTTON' || el.type === 'submit') continue;
                
                if (errors[el.name]) continue;

                // --- Manual Required Check (replacing native input.required) ---
                if (el.dataset.required === 'true') {
                    let valid = true;
                    if (el.type === 'radio') {
                        // Check if ANY in group is checked (skip if already validated group via name)
                         const group = form.querySelectorAll(`input[name="${el.name}"]`);
                         valid = Array.from(group).some(i => i.checked);
                    } else if (el.type === 'checkbox') {
                        // Strict requirement (must be checked)
                        valid = el.checked;
                    } else {
                        // Text/Select
                        valid = el.value && el.value.trim() !== '';
                    }
                    
                    if (!valid) {
                        errors[el.name] = FormStrings.fieldCannotBeEmpty;
                        continue; 
                    }
                }

                // Native Validity Check (Format only, ignore valueMissing if we rely on manual)
                if (el.type === 'email' && el.value && !isValidEmail(el.value)) {
                    errors[el.name] = FormStrings.invalidFormat;
                } else if (el.validity && !el.validity.valid) {
                     if (el.validity.valueMissing) {
                        // Only add if we didn't check manual already (or if manual missed it?)
                        // If we didn't set data-required but browser thinks it is required?
                        // We decided to remove native required. So this shouldn't trigger for required.
                        // But keep it as fallback.
                        errors[el.name] = FormStrings.fieldCannotBeEmpty;
                    } else if (el.validity.typeMismatch || el.validity.patternMismatch) {
                        if (el.type === 'tel') {
                             errors[el.name] = FormStrings.phoneFormatValidation;
                        } else {
                             errors[el.name] = FormStrings.invalidFormat;
                        }
                    } else {
                        errors[el.name] = el.validationMessage;
                    }
                }
            }

            // 2. State-Based Required Check
            const payload = session ? session.payload : null;
            const payloadFields = payload ? payload.fields : [];

            formModel.visibleFields.forEach(field => {
                if (field.type === 'ticket') {
                    // Ticket Validation
                    // We need to validate each ticket item against required subfields
                    const tickets = (payload && payload.ticket) ? payload.ticket : [];
                    
                    // Definition of subfields
                    let subFields = field.subFields;
                    if (!subFields || subFields.length === 0) {
                         subFields = field.fields || (field.data && field.data.fields) || [];
                    }
                    
                    // Iterate tickets in payload
                    tickets.forEach((ticketItem, tIdx) => {
                         subFields.forEach(sub => {
                             const stateIndex = ticketItem._ticketIndex ?? tIdx;
                             if (sub.type === 'spot' && session?.state.tickets[stateIndex]?._blueprintArea) return;
                             // Handle Model (camelCase) or Raw Data (snake_case)
                             const isRequired = sub.isRequired !== undefined ? sub.isRequired : sub.is_required;
                             
                             if (isRequired) {
                                  // Refactored: Centralized Value Extraction
                                  const values = FormValidator.getTicketFieldValues(ticketItem, sub);
                                  
                                  const isSatisfied = values.length > 0;
                                  
                                  if (!isSatisfied) {
                                      // Construct error ID matching the input name: fieldId_tIdx_subId
                                      const idxToUse = ticketItem['_ticketIndex'] !== undefined ? ticketItem['_ticketIndex'] : tIdx;
                                      const errorId = FormHelper.getTicketInputName(field.id, idxToUse, sub.id);
                                      errors[errorId] = FormStrings.fieldCannotBeEmpty;
                                  }
                             }
                             
                             // Max Options Validation
                             const maxOptions = sub.maxOptions || (sub.data && sub.data.max_options);
                             if (maxOptions && maxOptions > 0) {
                                  // Use Helper for Count
                                  const values = FormValidator.getTicketFieldValues(ticketItem, sub);
                                  const selectedCount = values.length;

                                  if (selectedCount > maxOptions) {
                                            const idxToUse = ticketItem['_ticketIndex'] !== undefined ? ticketItem['_ticketIndex'] : tIdx;
                                            const errorId = FormHelper.getTicketInputName(field.id, idxToUse, sub.id);
                                            // Fallback string or format
                                            errors[errorId] = (FormStrings.maxOptionsReached || "Maximum options: {0}").replace('{0}', maxOptions);
                                       }
                                  }
                          });
                    });
                    

                    


                    // Check if field itself is required (min 1 ticket)
                    if (field.isRequired) {
                         const hasTickets = tickets.length > 0;
                         if (!hasTickets) {
                             errors[field.id] = FormStrings.fieldCannotBeEmpty;
                         }
                    }

                    return; // Done with ticket field itself
                }

                if (errors[field.id]) return;

                if (field.isRequired) {
                     let isSatisfied = false;
                     if (payload) {
                         const entry = payloadFields.find(f => f[field.id.toString()] !== undefined);
                         const val = entry ? entry[field.id.toString()] : null;
                         
                         if (Array.isArray(val)) {
                             isSatisfied = val.length > 0;
                         } else {
                             isSatisfied = val !== null && val !== '' && val !== undefined;
                         }
                     } 
                     
                     if (!isSatisfied) {
                         errors[field.id] = FormStrings.fieldCannotBeEmpty;
                     }
                }
            });

            // 3. Update Session State
            if (session) {
                session.setValidationErrors(errors);
            }

            // 4. Check & Focus
            if (Object.keys(errors).length > 0) {
                 const firstErrorId = Object.keys(errors)[0];
                 
                 // Try to Find via form.elements (Standard HTML Collection)
                 // This handles RadioNodeList and works without CSS selector escaping issues
                 let firstInvalid = form.elements[firstErrorId];
                 
                // If it's a RadioNodeList (multiple inputs with same name), pick the first one
                 if (typeof RadioNodeList !== 'undefined' && firstInvalid instanceof RadioNodeList) {
                     firstInvalid = firstInvalid[0];
                 }
                 
                 // Fallback to Query Selector if form.elements fails (e.g. if name has weird chars not indexed?)
                 if (!firstInvalid) {
                      try {
                          firstInvalid = form.querySelector(`[name="${firstErrorId}"]`);
                      } catch (e) {
                          console.warn(`[FormValidator] Selector error for ${firstErrorId}`, e);
                      }
                 }
                 
                 if (firstInvalid) {
                     // Try to scroll to container
                     const container = firstInvalid.closest('.form-field-container');
                     (container || firstInvalid).scrollIntoView({ behavior: 'smooth', block: 'center' });
                     
                     // Focus: If it's a radio/checkbox, sometimes focusing the input is weird. 
                     // But we should try.
                     if (firstInvalid.focus) firstInvalid.focus({ preventScroll: true });
                 } else {
                     console.warn(`[FormValidator] Could not find element for error field: ${firstErrorId}`);
                 }
                 return false;
            }

            return EmailSuffixConfirmation.validate(form, session.emailSuffixConfirmations ??= new Map(), session);
    }

    static renderErrors(container, errors) {
        // Clear all existing errors first
        const allErrors = container.querySelectorAll('.form-field-error');
        allErrors.forEach(el => el.style.display = 'none');
        const allInvalid = container.querySelectorAll('.invalid');
        allInvalid.forEach(el => el.classList.remove('invalid'));

        // Show active errors
        if (!errors || Object.keys(errors).length === 0) return;

        Object.keys(errors).forEach(fieldId => {
             const message = errors[fieldId];
             
             // For Render, we are searching in CONTAINER (Header + Form + Footer wrapper), not just FORM
             // Query Selector is safest here.
             let input = container.querySelector(`[name="${fieldId}"]`);
             
             // Fallback: Try to find form and use elements if querySelector failed
             if (!input) {
                 const form = container.querySelector('form');
                 if (form && form.elements[fieldId]) {
                     let el = form.elements[fieldId];
                     if (typeof RadioNodeList !== 'undefined' && el instanceof RadioNodeList) el = el[0];
                     input = el;
                 }
             }

             // Fallback 2: Look for container by field ID (e.g. Ticket Field)
             if (!input) {
                 input = container.querySelector(`[data-field-id="${fieldId}"]`);
             }

             if (input) {
                 input.classList.add('invalid');
                 const fieldContainer = input.closest('.form-field-container');
                 if (fieldContainer) {
                     const errorDiv = fieldContainer.querySelector('.form-field-error');
                     if (errorDiv) {
                         errorDiv.textContent = message;
                         errorDiv.style.display = 'block';
                     } else {
                         console.error('[FormValidator] Error div not found in container', fieldContainer);
                     }
                     
                     // Highlight options container if exists (for radio/checkbox groups)
                     const optionsContainer = fieldContainer.querySelector('.radio-options, .checkbox-options');
                     if (optionsContainer) {
                         optionsContainer.classList.add('invalid');
                     }
                 } else {
                     console.warn('[FormValidator] Field container not found for input', input);
                 }
             } else {
                 console.warn(`[FormValidator] Input not found for error field: ${fieldId} in container`, container);
                 // Fallback: Try to find by ID if Name failed? 
                 // Sometimes ID might be constructed differently but worth a debug log.
             }
        });
    }
}
