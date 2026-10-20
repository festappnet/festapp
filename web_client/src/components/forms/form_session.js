import { BlueprintLayoutAdapter } from '../blueprint/blueprint_layout_adapter.js';
import { ReservationCapabilityStore } from './reservation_capability_store.js';
import { SupabaseService } from '../../services/supabase_service.js';
import { OptionBuilderHelper } from './fields/option_builder_helper.js';
import { AppConfig } from '../../app_config.js';
import { FormHelper } from './form_helper.js';
import { FormDataReader } from './form_data_reader.js';
import { DbForms } from './db_forms.js';
import { FormStrings } from './form_strings.js';
import { BlueprintStrings } from '../blueprint/blueprint_strings.js';
import { FieldInputHandlerFactory } from './handlers/field_input_handler_factory.js';

export class FormSession extends EventTarget {

    constructor(formModel, {reservationStorage, backend = SupabaseService.endpoint} = {}) {
        super();
        this.formModel = formModel;
        if (backend && formModel.key && (formModel.blueprint || reservationStorage) && !formModel.demoSimulation) {
            this._capabilityStore = new ReservationCapabilityStore(backend, formModel.key,
                reservationStorage ? {storage: reservationStorage} : {});
            const restored = this._capabilityStore.restore();
            this._restoredCapability = !!restored;
            this._reservationUnresolved = !!restored;
            if (restored) {
                formModel.secret = restored.secret;
                this.reservationExpiresAt = restored.expiresAt;
            }
            this._reservationCapability = restored || this._capabilityStore.save(formModel.secret);
        }
        
        const availableCurrencies = FormHelper.getAvailableCurrencies(formModel);
        
        this.state = {
            totalPrice: 0,
            totalItems: 0,
            currency: availableCurrencies[0], // Default execution
            availableCurrencies: availableCurrencies,
            validationErrors: {}, // { fieldId: errorMessage }
            tickets: [], // State Inversion: Single Source of Truth for Tickets
            fields: new Map() // State Inversion: Single Source of Truth for Standard Fields
        };
        
        // Initialize Payload with empty structure
        this.payload = {
            fields: [],
            ticket: [],
            [DbForms.metaSecret]: formModel.secret, 
            [DbForms.metaForm]: formModel.key
        };

        // --- Max Tickets Logic ---
        // Default to 1 if not specified (User Request)
        this.maxTickets = 1; 
        if (formModel && formModel.relatedFields) {
            const ticketField = formModel.relatedFields.find(f => f.type === 'ticket');
            if (ticketField && ticketField.data && ticketField.data.max_tickets) {
                const limit = parseInt(ticketField.data.max_tickets, 10);
                if (!isNaN(limit) && limit > 0) {
                    this.maxTickets = Math.min(limit, AppConfig.maxTicketsPerOrder);
                }
            }
        }


        if (formModel.registrationMode === 'regular' && Number.isInteger(formModel.capacity?.remainingPublic)) {
            this.maxTickets = Math.min(this.maxTickets, formModel.capacity.remainingPublic);
        }
        if (formModel.offerBundle) this.maxTickets = Math.min(this.maxTickets, formModel.offerBundle.pendingCount);
        // UI State for persistence across re-renders (not part of payload)
        this.uiState = new Map();
        
        // --- Fix: Request Serialization Queue ---
        this._spotQueue = Promise.resolve();

        // Spot Model Cache (Price Robustness)
        this.spotModels = new Map();
        const blueprintId = typeof formModel.blueprint === 'object' ? formModel.blueprint?.id : formModel.blueprint;
        if (this._capabilityStore && blueprintId) {
            this.recoverReservations = async () => {
                const data = await DbForms.getBlueprint(this.formModel.secret, this.formModel.key, blueprintId);
                const authority = new BlueprintLayoutAdapter(data, {session: this});
                authority.dispose();
                this.reservationRecoveryError = null;
            };
            if (this._restoredCapability) {
                // Serialize the reload read before any new hold or checkout.
                this._spotQueue = this._spotQueue.then(() => this.recoverReservations()).catch(error => {
                    this._reservationUnresolved = true;
                    this.reservationRecoveryError = error;
                    this._emitStateChanged();
                });
            }
        }
    }

    getComponentState(key) {
        return this.uiState.get(key);
    }

    setComponentState(key, value) {
        this.uiState.set(key, value);
    }

    /**
     * Fully refreshes the payload from the DOM.
     * Use this on initialization or structure changes (add/remove ticket).
     */
    refreshPayload(form) {
        if (!form) return;
        
        // 1. Standard Fields (Initial Srape / Sync)
        if (this.state.fields.size === 0) {
           const scrapedPayload = FormDataReader.getPayload(form, this.formModel);
            
            // Populate State from Scraped Payload
            scrapedPayload.fields.forEach(fieldObj => {
                const key = Object.keys(fieldObj).find(k => k !== 'currency_code');
                if (key) {
                    this.state.fields.set(key, fieldObj[key]);
                }
            });
        }
        
        // 2. Tickets: Sync from State (Strict Source of Truth)
        this._syncPayloadFromState();
        
        this._recalculate();
    }

    resetIncompatibleCurrencyFields(newCurrency) {
        if (!newCurrency) return;

        let hasChanges = false;

        // 1. Check Tickets
        this.state.tickets.forEach(ticket => {
             // Check spot
             if (ticket.fields) {
                 const fieldsToRemove = [];
                 ticket.fields.forEach((valObj, idx) => {
                     let itemCurrency = valObj.currency_code;
                     
                     if (!itemCurrency) {
                         const subDef = this._getTicketSubDef(valObj._subFieldId);
                             
                             if (subDef) {
                                 // Look up option (Inclusive Strategy)
                                 const val = valObj[subDef.type];
                                 let found = null;
                                 
                                 if (subDef.type === 'product_type' && subDef.data && subDef.data.product_type_data) {
                                      found = subDef.data.product_type_data.products.find(p => String(p.id) === String(val));
                                 }
                                 if (!found) {
                                     const options = subDef.options || (subDef.data && subDef.data.options) || [];
                                     found = options.find(o => String(o.id) === String(val));
                                 }

                                 if (found) {
                                     const c = found.currency || found.currencyCode || found.currency_code;
                                     if (c) {
                                         itemCurrency = c;
                                         valObj.currency_code = itemCurrency;
                                     }
                                 }
                             }
                     }
                     
                     if (itemCurrency && itemCurrency !== newCurrency) {
                         fieldsToRemove.push(idx);
                     }
                 });
                 
                 // Remove incompatible fields (reverse order)
                 for (let i = fieldsToRemove.length - 1; i >= 0; i--) {
                     ticket.fields.splice(fieldsToRemove[i], 1);
                     hasChanges = true;
                 }
     }
 });

        // 2. Check Standard Fields
        for (const [key, val] of this.state.fields.entries()) {
             // ... standard fields auto-select logic if needed ...
             // For now, focused on Ticket Products as per user report.
             const fieldDef = this.formModel.visibleFields.find(f => String(f.id) === String(key));
              if (fieldDef) {
                  const findOption = (v) => {
                     const options = fieldDef.options || (fieldDef.data && fieldDef.data.options) || [];
                     if (fieldDef.type === 'product_type' && fieldDef.data && fieldDef.data.product_type_data) {
                         return fieldDef.data.product_type_data.products.find(p => String(p.id) === String(v));
                     }
                     return options.find(o => String(o.id) === String(v));
                  };
                  
                  // Handle multi-values?
                  if (typeof val === 'string' && val.includes(' | ')) {
                      // Clear if potentially incompatible
                  } else {
                      const opt = findOption(val);
                      if (opt) {
                          const c = opt.currency || opt.currencyCode || opt.currency_code;
                          if (c && c !== newCurrency) {
                              this.state.fields.delete(key);
                              hasChanges = true;
                          }
                      }
                  }
             }
        }

        if (hasChanges) {
            this._syncPayloadFromState();
            this._recalculate();
            this._emitStateChanged();
        }
    }
    
    // --- State Inversion: Ticket Management ---

    addTicket(ticketData = {}) {
        // Ensure structure
        // Check Limit
        if (this.state.tickets.length >= this.maxTickets) {
            console.warn("[FormSession] Max tickets reached");
            throw new Error(BlueprintStrings.maxTicketsReached);
        }

        const newTicket = {
            id: Date.now() + Math.random(), // Temporary ID for UI keys if needed (not payload)
            fields: [], // Array of field values
            ...ticketData
        };

        // --- Auto-Selection Logic (User Request) ---
        // Only if adding new tickets is enabled (maxTickets > 1)
        if (this.maxTickets > 1) {
            // Find Ticket Field Definition
            const subFields = this._getTicketSubDefs();
                
                subFields.forEach(subDef => {
                    // Check if already has value (from ticketData)
                    if (newTicket.fields.some(f => String(f._subFieldId) === String(subDef.id))) return;
                    
                    // Logic: Auto-select first valid option if available
                    // Use options or product_type_data
                    let options = subDef.options || (subDef.data && subDef.data.options) || [];
                     if (subDef.type === 'product_type' && subDef.data && subDef.data.product_type_data) {
                         options = subDef.data.product_type_data.products;
                     }
                     
                     // Filter by Currency
                     const currency = this.state.currency;
                     const validOptions = options.filter(o => {
                         if (o.isAvailable === false || o.is_dynamically_available === false) return false;
                         const c = o.currency || o.currencyCode || o.currency_code;
                         return !c || c === currency;
                     });
                     
                     

                     if (validOptions.length > 0) {
                         const configuredDefault = subDef.data?.default_value;
                         const isMany = subDef.type === 'select_many' || subDef.data?.selection_type === 'select_many';
                         const selected = configuredDefault == null
                             ? [validOptions[0]]
                             : validOptions.filter(o => OptionBuilderHelper.shouldPreselect(
                                 subDef, o, isMany ? 'checkbox' : 'radio'));
                         if (isMany && subDef.type !== 'product_type') {
                             newTicket.fields.push({
                                 [subDef.type]: selected.map(o => o.id ?? o.title).join(' | '),
                                 _subFieldId: subDef.id,
                                 currency_code: currency,
                                 ...(selected.some(o => o.price !== undefined)
                                     ? { price: selected.reduce((sum, o) => sum + Number(o.price || 0), 0) } : {}),
                             });
                             return;
                         }
                         for (const autoSelect of (isMany ? selected : selected.slice(0, 1))) {

                             // Use ID if available, otherwise fallback to title (matches RadioFieldBuilder logic)
                             const autoSelectValue = (autoSelect.id !== undefined && autoSelect.id !== null) ? autoSelect.id : autoSelect.title;



                             const valObj = {
                                 [subDef.type]: autoSelectValue,
                                 _subFieldId: subDef.id,
                                 currency_code: currency
                             };

                             if (autoSelect.price !== undefined) valObj.price = autoSelect.price;
                             if (subDef.type === 'product_type') valObj.product_type = autoSelectValue;

                             newTicket.fields.push(valObj);
                         }
                     }
                });
        }
        
        this.state.tickets.push(newTicket);
        this._syncPayloadFromState();
        this._recalculate();
        
        this._emitStateChanged();
    }

    async removeTicket(index, skipBackendSync = false) {
        if (index >= 0 && index < this.state.tickets.length) {
            const ticket = this.state.tickets[index];
            if (!skipBackendSync && ticket.spot) {
                await this.toggleSpotUnit(this._spotUnits?.get(String(ticket.spot)) ||
                    [this.spotModels.get(String(ticket.spot)) || {id: ticket.spot}], false);
                return;
            }

            this.state.tickets.splice(index, 1);
            this._syncPayloadFromState();
            this._recalculate();
            this._emitStateChanged();
        } else {
            console.error(`[FormSession] removeTicket failed: index ${index} out of bounds`);
        }
    }

    updateTicket(index, fieldId, value) {

        // Auto-vivify Ticket 0 if needed (Robustness for Simple Mode after clear)
        if (index === 0 && this.state.tickets.length === 0) {
            this.addTicket();
        }

        if (index < 0 || index >= this.state.tickets.length) return;
        
        const ticket = this.state.tickets[index];
        // Value structure: { type: 'x', value: 'y', _subFieldId: 'z' }
        // We need to support the value structure expected by payload.
        
        // Find existing field entry
        const existingIdx = ticket.fields.findIndex(f => f._subFieldId === fieldId || f._subFieldId === value?._subFieldId);
        
        if (existingIdx !== -1) {
             if (value === null || value === undefined) {
                 ticket.fields.splice(existingIdx, 1); // Remove
             } else {
                 ticket.fields[existingIdx] = value; // Update
             }
        } else if (value !== null && value !== undefined) {
             ticket.fields.push(value); // Add
        }
        // Special Case: Spot/Seat
        if (value && (value.type === 'spot' || value.spot !== undefined)) {
             ticket.spot = value.value || value.spot;
             if (value.price !== undefined) ticket.spotPrice = value.price;
             // Recover price from cache if missing
             if (ticket.spotPrice === undefined && this.spotModels.has(String(ticket.spot))) {
                 const cached = this.spotModels.get(String(ticket.spot));
                 if (cached.product && cached.product.price) ticket.spotPrice = cached.product.price;
                 else if (cached.price) ticket.spotPrice = cached.price;
             }
             // Ensure product model/currency is tracked if needed? 
             // FormHelper.calculatePrice handles spotPrice on ticket object.
        }
        
        this._syncPayloadFromState();
        this._recalculate(); // Price update
        this._emitStateChanged();
    }

    setAreaQuantity(binding, quantity, available) {
        if (!Number.isInteger(quantity) || quantity < 0 || !Number.isInteger(available) || quantity > available) {
            throw new Error('area_quantity_unavailable');
        }
        if (quantity === 0) {
            this.state.tickets = this.state.tickets.filter(ticket => ticket._blueprintArea !== binding.nodeId);
            this._syncPayloadFromState(); this._recalculate(); this._emitStateChanged();
            return 0;
        }
        const candidates = (this.formModel.offeredTicketProductFields ?? this._getTicketSubDefs()).filter(field => field.type === 'product_type' && field.isHidden !== true).flatMap(field => {
            return (field.productTypeData?.products || field.data?.product_type_data?.products || field.options || []).filter(product =>
                String(product.id) === String(binding.productId) && product.is_hidden !== true && product.isAvailable !== false && product.is_dynamically_available !== false && product.is_available_dynamic_capacity !== false)
                .map(product => ({field, product}));
        });
        const choice = candidates.find(({product}) => !(product.currency_code || product.currencyCode || product.currency) ||
            (product.currency_code || product.currencyCode || product.currency) === this.state.currency);
        if (!choice) throw new Error('area_product_not_offered');
        const current = this.state.tickets.filter(ticket => ticket._blueprintArea === binding.nodeId);
        if (this.state.tickets.length - current.length + quantity > this.maxTickets) throw new Error(BlueprintStrings.maxTicketsReached);
        const before = [...this.state.tickets];
        try {
            while (current.length > quantity) {
                const ticket = current.pop();
                const index = this.state.tickets.indexOf(ticket);
                this.state.tickets.splice(index, 1);
            }
            while (current.length < quantity) {
                const value = {product_type: choice.product.id, _subFieldId: choice.field.id,
                    price: choice.product.price, currency_code: choice.product.currency_code || choice.product.currencyCode || this.state.currency};
                this.addTicket({_blueprintArea: binding.nodeId, fields: [value]});
                current.push(this.state.tickets.at(-1));
            }
            this._syncPayloadFromState(); this._recalculate(); this._emitStateChanged();
        } catch (error) {
            this.state.tickets = before;
            this._syncPayloadFromState(); this._recalculate(); this._emitStateChanged();
            throw error;
        }
        return quantity;
    }

    // One reservation command for a complete atomic unit; each member remains a
    // normal ticket in the existing form payload and price calculation.
    async toggleSpotUnit(spots, isSelecting) {
        const unique = [...new Map(spots.map(spot => [String(spot.id), spot])).values()];
        if (!unique.length) throw new Error('No seats selected');
        const ids = new Set(unique.map(spot => String(spot.id)));
        this._spotUnits ??= new Map();
        for (const spot of unique) this._spotUnits.set(String(spot.id), unique);
        const task = async () => {
            const before = this.state.tickets.filter(ticket => ids.has(String(ticket.spot)));
            const additions = unique.filter(spot => !before.some(ticket => String(ticket.spot) === String(spot.id)));
            if (isSelecting && this.state.tickets.length + additions.length > this.maxTickets) {
                throw new Error(BlueprintStrings.maxTicketsReached);
            }
            for (const spot of unique) this.spotModels.set(String(spot.id), spot);
            const apply = () => {
                if (isSelecting) for (const spot of additions) {
                    const product = spot.productModel || spot.product;
                    this.addTicket({spot: spot.id, spotName: spot.title || spot.name || `Spot ${spot.id}`,
                        ...(product && typeof product.price === 'number' ? {spotPrice: product.price} : {})});
                }
                else for (let index = this.state.tickets.length - 1; index >= 0; index--) {
                    if (ids.has(String(this.state.tickets[index].spot))) this.removeTicket(index, true);
                }
            };
            const capability = this._capabilityStore?.save(this.formModel.secret, this.reservationExpiresAt ?? null);
            if (capability) this._reservationCapability = capability;
            apply();
            try {
                const result = this.formModel.demoSimulation ? {spotIds: unique.map(s => s.id)}
                    : await DbForms.selectSpot(this.formModel.key, this.formModel.secret, unique[0].id, isSelecting);
                if (result?.spotIds && (result.spotIds.length !== ids.size || result.spotIds.some(id => !ids.has(String(id))))) {
                    // The authoritative command succeeded but the geometry is stale.
                    // Keep those tickets recoverable and require a fresh layout.
                    throw Object.assign(new Error('Seat unit changed; reload the seating plan'), {reservationApplied: true});
                }
                if (!this.state.tickets.some(ticket => ticket.spot)) this.reservationExpiresAt = null;
                this.adoptReservation(result);
                if (!this.state.tickets.some(ticket => ticket.spot)) this.completeReservation(this._reservationCapability);
                return result;
            } catch (error) {
                // Restore the last confirmed payload before attempting a read.
                this.state.tickets = this.state.tickets.filter(ticket => !ids.has(String(ticket.spot)));
                this.state.tickets.push(...before);
                this._syncPayloadFromState(); this._recalculate(); this._emitStateChanged();
                if (!error.reservationRejected || error.reservationApplied) {
                    this._reservationUnresolved = true;
                    if (this.recoverReservations) {
                        try {
                            await this.recoverReservations();
                            error.reservationRecovered = true;
                        } catch { /* Unknown state blocks checkout until an authoritative read succeeds. */ }
                    }
                }
                throw error;
            }
        };
        const enqueued = this._spotQueue.then(task);
        this._spotQueue = enqueued.catch(() => {});
        return enqueued;
    }

    toggleSpot(spotObjOrId, isSelecting) {
        const spot = typeof spotObjOrId === 'object' ? spotObjOrId : {id: spotObjOrId};
        return this.toggleSpotUnit(this._spotUnits?.get(String(spot.id)) || [spot], isSelecting);
    }

    captureReservationCapability() { return this._reservationCapability; }
    completeReservation(capability) {
        if (this._capabilityStore?.clear(capability)) this._reservationCapability = null;
    }

    adoptReservation(result) {
        const secret = result?.secret || result?.secretId;
        if (secret) {
            this.formModel.secret = secret;
            this.payload[DbForms.metaSecret] = secret;
        }
        // Server deadlines may shorten, but a retry never grants a new timeout.
        if (result?.expiresAt && Number.isFinite(Date.parse(result.expiresAt))) {
            if (!this.reservationExpiresAt || Date.parse(result.expiresAt) < Date.parse(this.reservationExpiresAt)) {
                this.reservationExpiresAt = result.expiresAt;
            }
        }
        const stored = this._capabilityStore?.save(this.formModel.secret, this.reservationExpiresAt ?? null);
        if (stored) this._reservationCapability = stored;
    }

    reconcileReservations(models, result = {}) {
        const scoped = new Map(models.map(model => [String(model.id), model]));
        const own = [...scoped.values()].filter(model => model.state === 'selected_by_me');
        const ownIds = new Set(own.map(model => String(model.id)));
        this.state.tickets = this.state.tickets.filter(ticket =>
            !scoped.has(String(ticket.spot)) || ownIds.has(String(ticket.spot)));
        for (const model of own) {
            this.spotModels.set(String(model.id), model);
            if (!this.state.tickets.some(ticket => String(ticket.spot) === String(model.id))) {
                this.addTicket({spot: model.id, spotName: model.title,
                    spotPrice: model.productModel?.price});
            }
        }
        // A read supplies the actual server deadline, including a genuinely new
        // hold acquired after an earlier reservation expired in another tab.
        this.reservationExpiresAt = this.state.tickets.some(ticket => ticket.spot)
            ? result.expiresAt ?? this.reservationExpiresAt : null;
        this.adoptReservation(result);
        if (!this.state.tickets.some(ticket => ticket.spot)) this.completeReservation(this._reservationCapability);
        this._reservationUnresolved = false;
        this._syncPayloadFromState(); this._recalculate(); this._emitStateChanged();
    }

    async awaitPendingReservations() {
        // A new operation can join while the previous queue settles.
        let queue;
        do { queue = this._spotQueue; await queue; } while (queue !== this._spotQueue);
        if (this._reservationUnresolved) throw new Error('reservation_state_unknown');
        if (this.reservationExpiresAt && Date.parse(this.reservationExpiresAt) <= Date.now() &&
            this.state.tickets.some(ticket => ticket.spot)) {
            if (!this.recoverReservations) throw new Error('reservation_expired');
            await this.recoverReservations();
        }
    }

    // --- Critical: Sync Payload from State ---
    _syncPayloadFromState() {
        // Rebuilds this.payload.ticket from this.state.tickets
        // Never relies on DOM scraping for tickets.
        
        this.payload.ticket = this.state.tickets.map((t, i) => {
            const rawFields = t.fields || [];
            const processedFields = [];
            
            rawFields.forEach(fObj => {
                // Check if any value in fObj contains pipe (Multi-Choice)
                let isMultiSelect = false;
                let subDef = null;
                
                let hasPipe = false;
                let pipeVal = null;
                let pipeKey = null;

                subDef = this._getTicketSubDef(fObj._subFieldId);
                // Keep explicit clears in the draft, but never submit them as products.
                if (subDef?.type === 'product_type' && (fObj.product_type === '' ||
                    (Array.isArray(fObj.product_type) && !fObj.product_type.length))) return;

                if (subDef) {
                    if (subDef.type === 'checkbox') isMultiSelect = true;
                    if (subDef.data && subDef.data.selection_type === 'select_many') isMultiSelect = true;
                }

                Object.entries(fObj).forEach(([k, v]) => {
                    if (k === '_subFieldId' || k === 'currency_code') return;
                    // Only check for pipe if it's a multi-select field
                    if (isMultiSelect && typeof v === 'string' && v.includes(' | ')) {
                        hasPipe = true;
                        pipeVal = v;
                        pipeKey = k;
                    }
                });
                
                if (hasPipe && pipeVal) {
                    // Split and Expand
                    const parts = pipeVal.split(' | ');
                    parts.forEach(part => {
                        // Clone object
                        const newEntry = { ...fObj };
                        // Replace pipe value with single part
                        newEntry[pipeKey] = part;
                        
                        // Explicit fix for SQL
                        if (newEntry.product_type === pipeVal) newEntry.product_type = part; 

                        // Re-hydrate Price (Critical for Multi-Select)
                        // Because "A | B" lookup failed in handleInput, we must lookup A and B individually here.
                        try {
                            // Find Definition
                             const subDef = this._getTicketSubDef(fObj._subFieldId);
                             
                             if (subDef) {
                                     // Find Option (Inclusive Logic)
                                     let opt = null;
                                     if (subDef.type === 'product_type' && subDef.data && subDef.data.product_type_data) {
                                          opt = subDef.data.product_type_data.products.find(p => String(p.id) === String(part));
                                     }
                                     if (!opt) {
                                         const options = subDef.options || (subDef.data && subDef.data.options) || [];
                                         opt = options.find(o => String(o.id) === String(part));
                                     }

                                     if (opt && opt.price !== undefined) {
                                         newEntry.price = parseFloat(opt.price);
                                     }
                                     if (opt) {
                                         const c = opt.currency || opt.currencyCode || opt.currency_code;
                                         if (c) {
                                             newEntry.currency_code = c;
                                         }
                                     }
                                 }

                        } catch (e) {
                            console.warn('[FormSession] Failed to re-hydrate price for multi-select part:', part, e);
                        }
                        
                        processedFields.push(newEntry);
                    });
                } else {
                     processedFields.push(fObj);
                }
            });

            const ticketObj = {
                ...(t.ticketId ? { ticketId: t.ticketId } : {}),
                fields: processedFields.map(field => {
                    const definition = this._getTicketSubDef(field._subFieldId);
                    if (!definition || ['product_type', 'spot'].includes(definition.type)) return field;
                    const value = field[definition.type] ?? field[definition.id];
                    return value === undefined ? field : { ...field, [definition.id]: value };
                }),
                _ticketIndex: i
            };
            
            // Map special top-level props expected by Backend/Calc
            if (t.spot) ticketObj.spot = t.spot;

            if (t.spotPrice) ticketObj.spotPrice = t.spotPrice;
            // Recover from cache if missing
            if (ticketObj.spot && !ticketObj.spotPrice && this.spotModels.has(String(ticketObj.spot))) {
                 const cached = this.spotModels.get(String(ticketObj.spot));
                if (cached.product && cached.product.price) ticketObj.spotPrice = cached.product.price;
                else if (cached.price) ticketObj.spotPrice = cached.price;
            }
            if (t.spotName) ticketObj.spotName = t.spotName;
            
            return ticketObj;
        });
        
        // --- Standard Fields Sync ---
        this.payload.fields = [];
        for (const [fieldId, value] of this.state.fields.entries()) {
            if (value === null || value === undefined) continue;

            const fieldDef = this.formModel.visibleFields.find(f => String(f.id) === String(fieldId));
            if (!fieldDef) continue; // Should not happen
            if (value === '' && !['select_one', 'select_many'].includes(fieldDef.type)) continue;

            const entry = { [fieldId]: value };
            
             // Currency Logic (Shared with old scraper)
            if (typeof value === 'string' && !value.includes(' | ')) {
                 const findOption = (val) => {
                     const options = fieldDef.options || (fieldDef.data && fieldDef.data.options) || [];
                      if (fieldDef.type === 'product_type' && fieldDef.data && fieldDef.data.product_type_data) {
                         return fieldDef.data.product_type_data.products.find(p => String(p.id) === String(val));
                     }
                     return options.find(o => String(o.id) === String(val));
                 };
                 const opt = findOption(value);
                 if (opt) {
                     const c = opt.currency || opt.currencyCode || opt.currency_code;
                     if (c) {
                         entry['currency_code'] = c;
                     }
                 }
            }
            // TODO: Multi-value currency logic? (Usually ignored for Checkboxes)
            
            this.payload.fields.push(entry);
        }
    }

    /**
     * Incrementally updates the payload based on a single input change.
     * Prevents full DOM scraping on every keystroke.
     */
    handleInput(e, form) {
        if (!e.target) return;
        const target = e.target;
        const name = target.name || (target.getAttribute && target.getAttribute('name'));
        
        if (!name) {
                return; 
        }
        
        // 1. Check for Structured Data Attributes (Ticket Fields)
        if (target.dataset.ticketId && target.dataset.index !== undefined && target.dataset.subId) {
                const ticketId = target.dataset.ticketId;
                const index = parseInt(target.dataset.index, 10);
                const subId = target.dataset.subId;
                
                // Directly call refactored handler with pre-parsed data
                this._handleTicketInputRefactored(target, form, [null, ticketId, index, subId]); // Mock match array
                return;
        }

        // 2. Fallback: Regex Parsing (Legacy support for tickets)
        // Format: ticketId_index_subId
        const ticketMatch = name.match(/^(\d+)_(\d+)_(.+)$/);
        
        if (ticketMatch) {
            this._handleTicketInputRefactored(target, form, ticketMatch);
        } else {
                // 3. Delegate to Factory for Standard/Complex Fields
                const { handler, fieldId, context } = FieldInputHandlerFactory.getHandler(this.formModel, target, name);
                if (handler) {
                    handler.handle(this, target, form, fieldId, context);
                } else {
                    console.warn(`[FormSession] No handler found for input ${name}`);
                }
        }
    }
    
    _handleTicketInputRefactored(target, form, match) {
         // match: [full, fieldId, domIndex, subId]
         // Or direct array from dataset logic
         const ticketFieldId = match[1];
         // Ensure index is number
         const index = typeof match[2] === 'number' ? match[2] : parseInt(match[2], 10);
         const subId = match[3];
         
         // Resolve Value Object expected by updateTicket
         // We need the SubField Definition to know the Type
         const subDef = this._getTicketSubDef(subId);
         
         if (!subDef) {
             console.warn(`[FormSession] subDef failed for subId ${subId}`);
             return;
         }
                  // Extract Value
          let val = target.value;
          let type = target.type;
         
         // Multi-Choice Checkbox Logic
         if (type === 'checkbox') {
             const name = target.name;
             if (name) {
                 // Gather all checked inputs for this field group
                 const checked = form.querySelectorAll(`input[name="${name}"]:checked`);
                 const vals = Array.from(checked).map(c => c.value);
                 // Join with pipe for consistent storage
                 val = vals.length > 0 ? vals.join(' | ') : null;
             } else {
                 if (!target.checked) val = null; 
             }
         } else if (type === 'radio') {
             if (!target.checked) val = null;
         }
         
         // Construct Value Object
         // Similar to _readSingleTicket logic but isolated
         if (val !== null) {
              // Find Option for Price/Currency
             const findOption = (v) => {
                 const opts = subDef.options || (subDef.data && subDef.data.options) || [];
                 let found = null;
                 
                 // 1. Try Product Type Data
                 if (subDef.type === 'product_type' && subDef.data && subDef.data.product_type_data) {
                     found = subDef.data.product_type_data.products.find(p => String(p.id) === String(v));
                 }
                 
                 // 2. Fallback to Standard Options (if not found above)
                 if (!found) {
                     found = opts.find(o => String(o.id) === String(v));
                 }
                 return found;
             };
             
             const valueObj = {
                 [subDef.type]: val,
                 _subFieldId: subDef.id
             };
             
             // Add product_type prop if needed by calculator
             if (subDef.type === 'product_type') {
                 valueObj['product_type'] = val;
             }
             
             // --- Price Calculation (Handle Multiselect) ---
             let totalPrice = 0;
             let currency = null;
             let pricesFound = false;

             const parts = String(val).split(' | ');
             parts.forEach(part => {
                 const opt = findOption(part);
                 if (opt) {
                     if (opt.price !== undefined) {
                         totalPrice += parseFloat(opt.price);
                         pricesFound = true;
                     }
                     const c = opt.currency || opt.currencyCode || opt.currency_code;
                     if (c) currency = c;
                 }
             });

             if (pricesFound) {
                 valueObj['price'] = totalPrice;
             }
             if (currency) {
                 valueObj['currency_code'] = currency;
             }
              
              // Fallback: If price/currency missing from Model, check DOM dataset (Robustness)
              // Only valid for Single Select (otherwise dataset is ambiguity of last clicked)
              if (!pricesFound && parts.length === 1 && target.dataset.price) {
                   valueObj['price'] = parseFloat(target.dataset.price);
              }
              if (!currency && target.dataset.currency) {
                   valueObj['currency_code'] = target.dataset.currency;
              }
              // Also check selected option if target is SELECT
              if (target.tagName === 'SELECT' && target.options[target.selectedIndex]) {
                   const selOpt = target.options[target.selectedIndex];
                   if (!pricesFound && selOpt.dataset.price) {
                        valueObj['price'] = parseFloat(selOpt.dataset.price);
                   }
                   if (!currency && selOpt.dataset.currency) {
                        valueObj['currency_code'] = selOpt.dataset.currency;
                   }
              }
             
             // Special Spot handling
              if (subDef.type === 'spot') {
                  // Ensure we grabbed the price from the option (handled above if option found)
                  // If option NOT found (e.g. dynamic spot?), we might fail. 
                  // But for "Variant 1", it is an option.
              }
              
              this.updateTicket(index, subDef.id, valueObj);
         } else {
             // Preserve explicit clears so rebuilding does not restore defaults.
             this.updateTicket(index, subDef.id, { [subDef.type]: '', _subFieldId: subDef.id });
         }
    }

    initialize(form) {
        // 1. Hydrate Tickets (One-time from DOM)
        const initialTickets = FormDataReader.getTicketDataFromDom(form, this.formModel);
        if (initialTickets.length > 0 && !this.formModel.offerBundle) {
            this.state.tickets = initialTickets;
        }

        // 2. Hydrate/Refresh Standard Fields & Calc
        this.refreshPayload(form);
    }

    _handleStandardInput_LEGACY(target, form, fieldId) {
        // Find field definition
        const field = this.formModel.visibleFields.find(f => String(f.id) === fieldId);
        if (!field) return; 

        // Get value(s)
        let val = target.value;
        const type = target.type;
        
        // For Checkboxes/SelectMany, we must read the group state
        if (type === 'checkbox' || field.type === 'select_many') {
            const checked = form.querySelectorAll(`input[name="${fieldId}"]:checked`);
            const vals = Array.from(checked).map(c => c.value);
            val = vals.length > 1 ? vals.join(' | ') : (vals[0] || '');
            
            // If empty, remove from payload? Or keep empty string?
            // FormDataReader removes empty entries usually, but keeping empty string is safe.
        }

        // Update Payload
        // Remove existing entry for this field
        const existingIdx = this.payload.fields.findIndex(f => f[fieldId] !== undefined);
        if (existingIdx !== -1) {
            this.payload.fields.splice(existingIdx, 1);
        }
        
        if (val) {
            const entry = { [fieldId]: val };
            
            // Find option for currency/meta
            const findOption = (val) => {
                 const options = field.options || (field.data && field.data.options) || [];
                 if (field.type === 'product_type' && field.data && field.data.product_type_data) {
                     return field.data.product_type_data.products.find(p => String(p.id) === String(val));
                 }
                 return options.find(o => String(o.id) === String(val));
             };
             
            // If single value, attach currency
            if (!val.includes(' | ')) {
                const opt = findOption(val);
                if (opt && opt.currency) {
                     entry['currency_code'] = opt.currency;
                }
            }
            
            this.payload.fields.push(entry);
        }
        
        this._recalculate();
    }

    _recalculate() {
        // Debug Logging
        const priceData = FormHelper.calculatePrice(this.payload, this.formModel);

        const hasBoundCurrency = this._payloadHasBoundCurrency();



        if (!hasBoundCurrency && this.state.currency) {
            // Force keep session currency if payload doesn't care
            priceData.currency = this.state.currency;
        } else if (!priceData.currency) {
            // If calculator returned nothing (no default?), keep session
             priceData.currency = this.state.currency;
        }

        // Visual-only meta-surcharge sums (per currency). Never affect totalPrice.
        priceData.metaSurchargeSums =
            FormHelper.calculateMetaSurchargeSums(this.payload, this.formModel);

        this.updateState(priceData);
    }

    _payloadHasBoundCurrency() {
        // Check if any field or ticket item has an explicit currency_code
        // Note: this.payload is built in _syncPayloadFromState
        
        if (this.payload.fields) {
            for (const f of this.payload.fields) {
                if (f.currency_code) return true;
            }
        }
        
        if (this.payload.ticket) {
            for (const t of this.payload.ticket) {
                 // Check ticket-level or field-level?
                 // Usually ticket fields have currency_code
                 if (t.fields) {
                     for (const f of t.fields) {
                         if (f.currency_code) return true;
                     }
                 }
            }
        }
        return false;
    }


    // --- Helper: Emit State Changed ---
    _emitStateChanged() {
         // Force emit current state
         this.dispatchEvent(new CustomEvent('state-changed', { detail: this.state }));
    }

    setCurrency(currencyCode) {
        if (this.state.currency !== currencyCode) {
            this.state.currency = currencyCode;
            
            // STRICT CLEARING Logic (User Request: "all selected products or fields must be deselected")
            // 1. Clear all tickets
            // Reset to 1 empty ticket (Default State) instead of wiping all (which removes UI).
            this.state.tickets = [{ fields: [] }];
            
            // 2. Clear fields that are likely products or currency-dependent choices
            // Text inputs usually preserved, but product_type/selects cleared.
            const fieldsToRemove = [];
            for (const [key, val] of this.state.fields.entries()) {
                const fieldDef = this.formModel.visibleFields.find(f => String(f.id) === String(key));
                if (fieldDef) {
                     // Heuristic: If it has options or is a product_type, clear it.
                     // Exceptions: 'text', 'textarea', 'email', 'tel', 'date' - usually keep unless currency specific.
                     // The user said "selected products or fields". Usually "selected" implies choices.
                     const isSelection = ['product_type', 'select', 'radio', 'checkbox', 'ticket'].includes(fieldDef.type);
                     if (isSelection) {
                         fieldsToRemove.push(key);
                     }
                }
            }
            fieldsToRemove.forEach(k => this.state.fields.delete(k));

            this._syncPayloadFromState();
            this._recalculate();
            this._emitStateChanged();
        }
    }

    updateState(newState) {
        // Simple distinct check to avoid event spam?
        // Or just emit always? Let's emit always to be safe for now, 
        // as "User Typed" might not change price but might signify activity.
        // Actually, we only care about price/items for the widget.
        
        const metaChanged = JSON.stringify(newState.metaSurchargeSums || []) !==
            JSON.stringify(this.state.metaSurchargeSums || []);
        const hasChanged =
            newState.totalPrice !== this.state.totalPrice ||
            newState.totalItems !== this.state.totalItems ||
            newState.currency !== this.state.currency ||
            metaChanged;

        if (hasChanged) {
            this.state = { ...this.state, ...newState };
            this.dispatchEvent(new CustomEvent('state-changed', { detail: this.state }));
        }
    }

    setValidationErrors(errors) {
        this.state = { ...this.state, validationErrors: errors };
        this.dispatchEvent(new CustomEvent('validation-changed', { detail: this.state.validationErrors }));
    }
    
    setIsReady(ready) {
        // Force emit current state (useful for initial rendering sync)
        this.dispatchEvent(new CustomEvent('state-changed', { detail: this.state }));
    }

    // --- Refactoring Helpers ---

    _getTicketFieldDef() {
        let def = this.formModel.visibleFields.find(f => f.type === 'ticket');
        if (!def && this.formModel.relatedFields) {
            def = this.formModel.relatedFields.find(f => f.type === 'ticket');
        }
        return def;
    }

    _getTicketSubDefs() {
        const ticketDef = this._getTicketFieldDef();
        if (!ticketDef) return [];
        return ticketDef.subFields || ticketDef.fields || (ticketDef.data && ticketDef.data.fields) || [];
    }

    _getTicketSubDef(subId) {
        const subDefs = this._getTicketSubDefs();
        return subDefs.find(s => String(s.id) === String(subId)) || this.formModel.offeredTicketProductFields?.find(s => String(s.id) === String(subId));
    }

    get currentState() {
        return this.state;
    }
}
