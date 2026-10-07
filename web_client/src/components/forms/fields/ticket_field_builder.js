import * as FormFieldBuilderModule from './form_field_builder.js';
import { FormStrings } from '../form_strings.js';
import { CommonStrings } from '../../shared/common_strings.js';
import { OrdersStrings } from '../../eshop/orders_strings.js';
import { FormHelper } from '../form_helper.js';
// import { BlueprintSelector } from '../../blueprint/blueprint_selector.js';
import { DbForms } from '../db_forms.js';
import { formatPrice } from '../../../utils/formatters.js';

export class TicketFieldBuilder {
    static _uniqueIndexCounter = 0;

    static reset() {
        TicketFieldBuilder._uniqueIndexCounter = 0;
    }

    static _prepareScopedDef(scopedDef) {
         if (scopedDef.type === 'product_type') {
             // Map Options if needed
             if (scopedDef.data && scopedDef.data.product_type_data && scopedDef.data.product_type_data.products) {
                 if (!scopedDef.options || scopedDef.options.length === 0) {
                     scopedDef.options = scopedDef.data.product_type_data.products.map(p => ({
                         id: p.id,
                         title: p.title,
                         description: p.description,
                         price: p.price,
                         currency: p.currency,
                         data: p.data
                     }));
                 }
             }
             // Ensure label is visible
             delete scopedDef._hideLabel; 
         }
    }

    static create(field, formModel, session) {
    
        const container = document.createElement('div');
        container.className = 'form-field-container ticket-field';
        container.dataset.fieldId = field.id;
        
        // Error Container for the Field Itself (e.g. "At least one ticket required")
        const errorDiv = document.createElement('div');
        errorDiv.className = 'form-field-error';
        errorDiv.style.display = 'none';
        container.appendChild(errorDiv);
        
        let subFields = field.subFields;
        if (!subFields || subFields.length === 0) {
             subFields = field.fields || (field.data && field.data.fields) || [];
        }

        // Subscription for reactivity handled below
        const hasSpotField = subFields.some(f => f.type === 'spot');

        
        // Mode Logic
        // Simple Mode: 1 Ticket, no Spots (just fields).
        // Complex Mode: >1 Tickets OR Spots (Ticket List UI).
        
        let forceComplex = false;
        if (session && session.maxTickets > 1) {
             forceComplex = true;
        }

        if (!hasSpotField && !forceComplex) {
            // --- Simple Mode (Direct Fields) ---
            
            // 1. Ensure Session has at least 1 ticket
            if (session && session.state.tickets.length === 0) {
                session.addTicket(); 
            }

            // Render subfields directly
            subFields.forEach((subDef, idx) => {
                // Ensure Unique ID for Label/Input association (crucial for A11y and Validation)
                // Use a stable index '0' for Simple Mode as it's a single ticket.
                const scopedDef = { ...subDef, id: FormHelper.getTicketInputName(field.id, 0, subDef.id) };
                
                // --- Validation: Explicit Required Attribute ---
                if (scopedDef.isRequired) {
                    // This is handled inside individual field builders (TextFieldBuilder etc),
                    // but we must ensure they process 'isRequired' correctly.
                }

                TicketFieldBuilder._prepareScopedDef(scopedDef);

                TicketFieldBuilder._prepareScopedDef(scopedDef);
                
                // Resolve module cycle by accessing namespace at runtime
                const FormFieldBuilder = FormFieldBuilderModule.FormFieldBuilder; 
                if (!FormFieldBuilder) {
                     console.error("TicketFieldBuilder: FormFieldBuilder is undefined! Module keys:", Object.keys(FormFieldBuilderModule));
                } else {

                }
                const subComp = FormFieldBuilder.createFormField(scopedDef, formModel);

                
                // --- Robustness: Attach Data Attributes ---
                const inputs = subComp.querySelectorAll('input, select, textarea');
                inputs.forEach(input => {
                    input.dataset.ticketId = field.id;
                    input.dataset.index = '0';
                    input.dataset.subId = subDef.id;
                });
                
                container.appendChild(subComp);
            });
            
            // --- Reactivity for Simple Mode ---
            if (session) {
                const syncSimpleFromSession = () => {
                     // Robustness: Handle empty session (cleared tickets)
                     let ticketData = null;
                     if (session.state.tickets.length > 0) {
                         ticketData = session.state.tickets[0];
                     }

                     // On the very first sync the DOM already carries defaults applied by
                     // OptionBuilderHelper.shouldPreselect (radios/checkboxes pre-checked from
                     // sub-field default_value). Reconciling against an empty state would
                     // clobber them, so we bail out until a user interaction (or saved-form
                     // load) writes the first field entry.
                     if (!ticketData || !ticketData.fields || ticketData.fields.length === 0) return;

                     const inputs = container.querySelectorAll('input, select, textarea');
                     inputs.forEach(input => {
                         const subId = input.dataset.subId;
                         if (!subId) return;

                         // Find value in ticket fields
                         const fieldEntry = (ticketData && ticketData.fields) 
                            ? ticketData.fields.find(f => String(f._subFieldId) === String(subId))
                            : null;

                         let newVal = '';
                         if (fieldEntry) {
                             // Try to resolve type from subFields in scope
                             const subDef = subFields.find(sf => sf.id === subId);
                             const typeKey = subDef ? subDef.type : null;
                             
                             newVal = fieldEntry.value;
                             if (newVal === undefined && typeKey) newVal = fieldEntry[typeKey];
                             
                             // Fallback / Specific check
                             if (newVal === undefined && fieldEntry.product_type !== undefined) newVal = fieldEntry.product_type;
                             if (newVal === undefined) newVal = '';
                         }
                         
                         // Update Input if needed
                         if (input.type === 'radio') {
                             if (input.value === newVal || String(input.value) === String(newVal)) {
                                 input.checked = true;
                             } else {
                                 // Explicitly uncheck if it doesn't match (for cleared state)
                                 input.checked = false;
                             }
                         } else if (input.type === 'checkbox') {
                             // Checkbox Logic (Multiselect support)
                             // Session value might be "101 | 102"
                             let isChecked = false;
                             if (newVal !== undefined && newVal !== null) {
                                 if (newVal === true || newVal === 'true') {
                                     isChecked = true;
                                 } else {
                                     const valStr = String(newVal);
                                     const parts = valStr.split(' | ');
                                     isChecked = parts.some(p => String(p) === String(input.value));
                                 }
                             }
                             
                             if (input.checked !== isChecked) {
                                 input.checked = isChecked;
                             }
                         } else {
                             if (input.value !== newVal && document.activeElement !== input) {
                                 input.value = newVal;
                             }
                         }
                     });
                };
                
                // Initial Sync (to reflect defaults from addTicket)
                // Use timeout to allow DOM paint? No, synchronous is fine properly.
                // But addTicket might have happened just now.
                syncSimpleFromSession();

                session.addEventListener('state-changed', () => {
                    syncSimpleFromSession();
                });
            }
            
            return container;

        } else {
            // --- Complex Mode (Seat Selection / Multiple Items) ---

            
             if (field.title && field.title !== 'Tickets' && field.title !== OrdersStrings.tickets) {
                 const label = document.createElement('label');
                 label.className = 'form-field-label';
                 label.textContent = field.title;
                 container.appendChild(label);
            }
    
            if (field.description) {
                const desc = document.createElement('div');
                desc.className = 'form-field-description';
                desc.innerHTML = field.description;
                container.appendChild(desc);
            }

            const listContainer = document.createElement('div');
            listContainer.className = 'tickets-list';
            container.appendChild(listContainer);
            
            // --- Helper to Add Ticket Item ---
            const renderTicketItem = (index, seat = null) => {
                const ticketItem = document.createElement('div');
                ticketItem.className = 'ticket-item';
                if (seat) ticketItem.dataset.seatId = seat.id;

                ticketItem.dataset.index = index; 

                // Resolve Ticket Data from Session
                let ticketData = null;
                if (session && session.state.tickets[index]) {
                    ticketData = session.state.tickets[index];
                } 
                
                const header = document.createElement('div');
                header.className = 'ticket-header';
                
                const titleSpan = document.createElement('span');
                titleSpan.style.fontWeight = 'bold';
                titleSpan.style.fontSize = '1.3rem'; 
                
                // If it's a seat ticket, show seat name instead of "Ticket X"
                if (seat && seat.objectModel) {
                     titleSpan.textContent = seat.objectModel.name || `${FormStrings.ticket} ${index + 1}`;
                } else {
                     titleSpan.textContent = `${FormStrings.ticket} ${index + 1}`;
                }
                header.appendChild(titleSpan);

                const removeBtn = document.createElement('button');
                removeBtn.type = 'button';
                removeBtn.className = 'btn-remove-ticket'; 
                removeBtn.title = CommonStrings.remove;
                removeBtn.innerHTML = '<i class="material-icons">close</i>';
                
                removeBtn.onclick = async () => {
                    // API Deselection handled by FormSession.removeTicket
                    
                    // --- STATE INVERSION: Call Session ---
                    if (session) {
                        // Find current index in DOM (safe fallback)
                        const currentIdx = Array.from(listContainer.children).indexOf(ticketItem);
                        session.removeTicket(currentIdx);
                    }
                    
                    ticketItem.remove();
                    
                    // Always update indices
                    Array.from(listContainer.children).forEach((child, i) => {
                       const span = child.querySelector('.ticket-header span');
                       // Only update if it contains "Ticket" string to avoid overwriting custom names?
                       if (span && span.textContent.startsWith(FormStrings.ticket)) {
                           span.textContent = `${FormStrings.ticket} ${i + 1}`;
                       }
                    });
                    
                    // If seat was removed, update selectedSeats locally
                    if (container.selectedSeats && seat) {
                        container.selectedSeats = container.selectedSeats.filter(s => s.id !== seat.id);
                    }
                };
                header.appendChild(removeBtn);
                ticketItem.appendChild(header);
                
                // Sort fields to ensure Spot is first
                const sortedSubFields = [...subFields].sort((a, b) => (a.type === 'spot' ? -1 : 1));

                if (sortedSubFields.length > 0) {
                    sortedSubFields.forEach(subDef => {
                        // Create scoped definition
                        const scopedDef = { ...subDef, id: FormHelper.getTicketInputName(field.id, index, subDef.id) };
                        
                        TicketFieldBuilder._prepareScopedDef(scopedDef);

                        // --- Restore Value from Session ---
                        if (ticketData && ticketData.fields) {
                            // Find field entry
                            const fieldEntry = ticketData.fields.find(f => String(f._subFieldId) === String(subDef.id));
                            if (fieldEntry) {
                                // Extract Value
                                // entry = { type: val, _subFieldId: id }
                                let val = fieldEntry[subDef.type];
                                
                                // Fallback / Specific check (Same as updateFromSession)
                                if (val === undefined && fieldEntry.value !== undefined) val = fieldEntry.value;
                                if (val === undefined && fieldEntry.product_type !== undefined) val = fieldEntry.product_type;
                                if (val === undefined && fieldEntry.text !== undefined) val = fieldEntry.text;

                                if (val !== undefined) {
                                    scopedDef.value = val;
                                }
                            }
                        }
                        
                        if (subDef.isRequired) scopedDef.isRequired = true;

                        // --- SPOT FIELD HANDLING ---
                        if (scopedDef.type === 'spot') { 
                            scopedDef.isRequired = true; 
                            
                            // If we have a seat, we do special rendering
                            if (seat) {
                                // 1. Hidden Value Input
                                let priceVal = 0;
                                let currency = FormStrings.currencyDefault || 'CZK'; 
                                let productTitle = '';
                                
                                const product = seat.productModel || (typeof seat.product === 'object' ? seat.product : null);
                                
                                if (product) {
                                    productTitle = product.title || '';
                                    if (product.price) {
                                        priceVal = product.price;
                                    }
                                    if (product.currency) {
                                        currency = product.currency;
                                    } else if (formModel.currencyCode) {
                                        currency = formModel.currencyCode;
                                    }
                                }

                                const seatName = seat.title || seat.name || `Seat #${seat.id}`;

                                const hiddenInput = document.createElement('input');
                                hiddenInput.type = 'hidden';
                                hiddenInput.name = scopedDef.id;
                                hiddenInput.value = seat.id; // Spot ID
                                hiddenInput.dataset.name = seatName; 
                                if (priceVal > 0) hiddenInput.dataset.price = priceVal; 
                                
                                ticketItem.appendChild(hiddenInput);

                                // 2. Visible Read-Only Input (Display)
                                const displayContainer = document.createElement('div');
                                displayContainer.className = 'form-field-container';
                                
                                const label = document.createElement('label');
                                label.className = 'form-field-label';
                                label.textContent = scopedDef.title || OrdersStrings.gridSpot || 'Spot';
                                displayContainer.appendChild(label);
                                
                                const displayDiv = document.createElement('div');
                                displayDiv.className = 'form-control';
                                displayDiv.style.backgroundColor = 'var(--bs-secondary-bg, #e9ecef)'; 
                                displayDiv.style.opacity = '1';
                                displayDiv.style.display = 'flex';
                                displayDiv.style.alignItems = 'center';

                                const formattedPart = formatPrice(priceVal, currency);
                                const priceHtml = priceVal > 0 ? `&nbsp;<span class="option-price">+${formattedPart}</span>` : '';
                                const prefix = productTitle ? `${productTitle} - ` : '';
                                
                                displayDiv.innerHTML = `<span>${prefix}${seatName}</span>${priceHtml}`;
                                
                                displayContainer.appendChild(displayDiv);
                                ticketItem.appendChild(displayContainer);
                                
                                return; 
                            }
                        }
                        
                        // Resolve module cycle by accessing namespace at runtime
                        const FormFieldBuilder = FormFieldBuilderModule.FormFieldBuilder;
                        const subComp = FormFieldBuilder.createFormField(scopedDef, formModel);
                        
                        // --- Robustness: Attach Data Attributes ---
                        const inputs = subComp.querySelectorAll('input, select, textarea');
                        inputs.forEach(inputOrSelect => {
                            inputOrSelect.dataset.ticketId = field.id;
                            inputOrSelect.dataset.index = index;
                            inputOrSelect.dataset.subId = subDef.id;

                            // Validation Refactoring (Moved here)
                            if (scopedDef.isRequired) {
                                inputOrSelect.dataset.required = 'true';
                            }
                        });
            
                        ticketItem.appendChild(subComp);
                    });
                } else {
                     const hint = document.createElement('div');
                     hint.style.fontStyle = 'italic';
                     hint.style.color = '#777';
                     hint.textContent = "Ticket details";
                     ticketItem.appendChild(hint);
                }
                ticketItem.updateFromSession = (currentIndex) => {
                    if (currentIndex !== undefined) index = currentIndex;
                    // Check detachment again just in case
                    if (!document.body.contains(ticketItem) && !listContainer.contains(ticketItem)) return;

                    const inputs = ticketItem.querySelectorAll('input, select, textarea');
                    if (!session || !session.state.tickets[index]) return;
                    const ticketData = session.state.tickets[index];

                    // On the very first render of a ticket, state.fields is empty but the DOM
                    // already carries defaults applied by OptionBuilderHelper.shouldPreselect
                    // (radios/checkboxes pre-checked from sub-field default_value). Reconciling
                    // against empty state would clobber those defaults, so we bail out until a
                    // user interaction (or saved-form load) writes the first field entry.
                    if (!ticketData.fields || ticketData.fields.length === 0) return;

                    // Iterate DOM Inputs (Source of UI Truth) -> Sync from State
                    inputs.forEach(input => {
                        const subId = input.dataset.subId;
                        if (!subId) return;

                        // Find value in ticket fields
                        // ticketData.fields is array of value objects
                        const fieldEntry = ticketData.fields ? ticketData.fields.find(f => String(f._subFieldId) === String(subId)) : null;

                        // Improved Value Resolution
                        let val = undefined;
                        if (fieldEntry) {
                            // Try to resolve type from subFields in scope
                            const subDef = subFields.find(sf => sf.id === subId);
                            const typeKey = subDef ? subDef.type : null;
                        
                            val = fieldEntry.value;
                            if (val === undefined && typeKey) val = fieldEntry[typeKey];
                            
                            // Fallback / Specific check
                            if (val === undefined && fieldEntry.product_type !== undefined) val = fieldEntry.product_type;
                            if (val === undefined && fieldEntry.text !== undefined) val = fieldEntry.text;
                        } 
                        
                        // Don't overwrite active element to avoid cursor jumping (except checkboxes/radios where it matters less)
                        if (document.activeElement === input && input.type !== 'checkbox' && input.type !== 'radio') return;

                        // Apply Value
                        if (input.type === 'radio') {
                             const shouldBeChecked = val !== undefined && String(input.value) === String(val);
                             if (input.checked !== shouldBeChecked) {
                                 input.checked = shouldBeChecked;
                             }
                             if (!shouldBeChecked) input.checked = false; // Explicit Uncheck Fix
                        } else if (input.type === 'checkbox') {
                             // Checkbox Logic (Multiselect support)
                             // Session value might be "101 | 102"
                             let isChecked = false;
                             if (val !== undefined && val !== null) {
                                 if (val === true || val === 'true') {
                                     isChecked = true;
                                 } else {
                                     const valStr = String(val);
                                     const parts = valStr.split(' | ');
                                     isChecked = parts.some(p => String(p) === String(input.value));
                                 }
                             }
                             
                             if (input.checked !== isChecked) {
                                 input.checked = isChecked;
                             }
                        } else {
                             // Text/Select
                             const expected = val !== undefined ? val : '';
                             if (String(input.value) !== String(expected)) {
                                 input.value = expected;
                             }
                        }
                    });
                };

                if (ticketItem.updateFromSession) ticketItem.updateFromSession(index);
                listContainer.appendChild(ticketItem);
            };
    
            // --- Logic Branch: Blueprint vs Manual ---
            
            if (hasSpotField && formModel.blueprint) {
                // BLUEPRINT MODE
                
                container.selectedSeats = []; 
                
                let existingBtn = container.querySelector('button.btn-primary.btn-blueprint-select');
                
                if (!existingBtn) {
                     existingBtn = document.createElement('button');
                     existingBtn.type = 'button';
                     existingBtn.className = 'btn btn-primary btn-blueprint-select w-100 d-block';
                     existingBtn.textContent = FormStrings.seatSelection || "Select Seats";
                     const seatIcon = document.createElement('i');
                     seatIcon.className = 'material-icons';
                     seatIcon.setAttribute('aria-hidden', 'true');
                     seatIcon.textContent = 'event_seat';
                     seatIcon.style.verticalAlign = 'middle';
                     seatIcon.style.marginInlineEnd = '8px';
                     existingBtn.prepend(seatIcon);
                     container.appendChild(existingBtn);
                }

                existingBtn.onclick = () => {
                     import('../../blueprint/blueprint_selector.js').then(({ BlueprintSelector }) => {
                         const selector = new BlueprintSelector();
                         selector.open(session, field, container.selectedSeats || []);
                     });
                };
                
                // Do NOT add "Add Ticket" button in blueprint mode
                
            } else {
                // MANUAL MODE
                
                const addBtn = document.createElement('button');
                addBtn.type = 'button';
                addBtn.className = 'btn btn-secondary btn-sm btn-add-ticket';
                addBtn.textContent = `+ ${FormStrings.addTicket}`;
                
                addBtn.onclick = () => {
                     // --- STATE INVERSION: Call Session ---
                     if (session) session.addTicket(); // Add dummy/empty ticket
                };
                container.appendChild(addBtn);
                
                // Default 1 ticket (if session empty)
                if (session && session.state.tickets.length === 0) {
                     session.addTicket();
                     renderTicketItem(0);
                } else if (session && session.state.tickets.length > 0) {
                    // Restore from session
                    session.state.tickets.forEach((t, i) => {
                         renderTicketItem(i);
                         // TODO: Restore values?
                    });
                } else {
                    // Fallback
                    renderTicketItem(0);
                }
            }
    
            // --- Helper to Re-Sync List from Session (Reactivity) ---
            const syncListFromSession = () => {

                 const newTickets = session.state.tickets;
                 const currentItems = Array.from(listContainer.children);

                 // 1. Smart Diffing: Check Structure
                 let structureChanged = false;
                 
                 if (newTickets.length !== currentItems.length) {
                     structureChanged = true;
                 } else {
                     // Check Spots (if any mismatch, we rebuild)
                     for (let i = 0; i < newTickets.length; i++) {
                         const t = newTickets[i];
                         const item = currentItems[i];
                         
                         // Check Spot ID stability
                         // DOM dataset.seatId is string
                         if (t.spot) {
                             if (String(t.spot) !== String(item.dataset.seatId)) {
                                 structureChanged = true;

                                 break;
                             }
                         } else {
                             // If ticket has no spot, but DOM item has seatId -> Changed
                             if (item.dataset.seatId) {
                                 structureChanged = true;

                                 break;
                             }
                         }
                     }
                 }

                 // Helper for global button visibility
                 const updateButtonVisibility = () => {
                     const addBtn = container.querySelector('.btn-add-ticket');
                     if (addBtn) {
                         // Check Limit
                         const max = session.maxTickets || 999;
                         if (session.state.tickets.length >= max) {
                             addBtn.style.display = 'none';
                         } else {
                             addBtn.style.display = '';
                         }

                         // ONE TICKET MINIMUM RULE (Manual Mode)
                         const removeBtns = container.querySelectorAll('.btn-remove-ticket');
                         const count = session.state.tickets.length;
                         removeBtns.forEach(btn => {
                             if (count <= 1) {
                                 btn.style.display = 'none';
                             } else {
                                 btn.style.display = '';
                             }
                         });
                     }
                 };

                 if (!structureChanged) {
                     // Structure is stable. 
                     // iterate items and call updateFromSession

                     currentItems.forEach((ticketItem, i) => {
                         if (ticketItem.updateFromSession) {
                             ticketItem.updateFromSession(i);
                         } else {
                             console.warn(`[TicketFieldBuilder] Item ${i} missing updateFromSession!`);
                         }
                     });
                     
                     // Ensure visibility logic runs even on stable updates
                     updateButtonVisibility();

                     return; // Skip Full Re-render
                  }

                  // Full Rebuild
                  // Explicitly detach old items to prevent Ghost Listeners
                  currentItems.forEach(item => {
                      if (item.updateFromSession) item.updateFromSession = null;
                      item.remove();
                  });
                 listContainer.innerHTML = '';
                 container.selectedSeats = [];
                 
                 // Re-render from session tickets
                 session.state.tickets.forEach((ticket, i) => {
                     // Try to reconstruct seat object if possible?
                     // Verify if it's a spot ticket
                     let seatStub = null;
                     if (ticket.spot) {
                         seatStub = { 
                             id: ticket.spot,
                             title: ticket.spotName || `Spot ${ticket.spot}`, // Fallback
                             // We might lack full product model here if not persisted in state fully.
                             // But basic ID is enough for remove.
                             productModel: { price: ticket.spotPrice }
                         };
                         container.selectedSeats.push(seatStub);
                     }
                     renderTicketItem(i, seatStub);
                 });
                 
                 container.dispatchEvent(new Event('input', { bubbles: true }));
                 
                 // Update Add Button Visibility
                 updateButtonVisibility();

            };

            if (session) {
                // Initial Sync

                syncListFromSession();
                
                // Subscribe
                // Subscribe with cleanup
                const stateHandler = () => syncListFromSession();
                session.addEventListener('state-changed', stateHandler);
                
                // Expose destroy for Memory Management
                container.destroy = () => {
                     session.removeEventListener('state-changed', stateHandler);
                };
                
                // Also auto-cleanup if detached (MutationObserver is overkill, but simple check in sync helps)
                // The destroy() method is the robust way.
            }

            return container;
        }
    }
}
