import { FeatureService, DEFAULT_META_SURCHARGE_CURRENCY } from '../features/feature_service.js';
import { formatPrice } from '../../utils/formatters.js';

export class FormHelper {
    static get metaFields() { return 'fields'; }
    static get metaSecret() { return 'secret'; }
    static get metaForm() { return 'form'; }
    static get metaValues() { return 'values'; }

    static getTicketInputName(ticketFieldId, index, subFieldId) {
        return `${ticketFieldId}_${index}_${subFieldId}`;
    }
    
    // Extracts data from the form DOM based on the model
    // getDataFromForm removed - Use FormDataReader.getPayload instead

    static getAvailableCurrencies(formModel) {
        const currencies = new Set();
        const fields = formModel.visibleFields || [];
        
        fields.forEach(field => {


             // Check top level options (product_type mapped to fields)
             if (field.data && field.data.product_type_data && field.data.product_type_data.products) {
                 field.data.product_type_data.products.forEach(p => {
                     if (p.currency) currencies.add(p.currency);
                     if (p.currencyCode) currencies.add(p.currencyCode);
                     if (p.currency_code) currencies.add(p.currency_code);
                 });
             }
             
             // Check standard options
             if (field.options) {
                 field.options.forEach(o => {
                     if (o.currency) currencies.add(o.currency);
                     if (o.currencyCode) currencies.add(o.currencyCode);
                     if (o.currency_code) currencies.add(o.currency_code);
                 });
             }
             
             // Tickets
             if (field.type === 'ticket') {
                 const subFields = field.subFields || field.fields || (field.data && field.data.fields) || [];
                 subFields.forEach(sf => {
                     // Check 'options' as FormFieldModel parses product_type_data into options
                     if (sf.options) {
                         sf.options.forEach(o => {
                             if (o.currency) currencies.add(o.currency);
                             if (o.currencyCode) currencies.add(o.currencyCode);
                             if (o.currency_code) currencies.add(o.currency_code);
                         });
                     }
                     
                     // Fallback for raw objects (if not using FormFieldModel but raw json)
                     if (sf.data && sf.data.product_type_data && sf.data.product_type_data.products) {
                         sf.data.product_type_data.products.forEach(p => {
                            if (p.currency) currencies.add(p.currency);
                            if (p.currencyCode) currencies.add(p.currencyCode);
                            if (p.currency_code) currencies.add(p.currency_code);
                         });
                     }
                     // Raw fallback level 2
                     if (sf.product_type_data && sf.product_type_data.products) {
                          sf.product_type_data.products.forEach(p => {
                            if (p.currency) currencies.add(p.currency);
                            if (p.currencyCode) currencies.add(p.currencyCode);
                            if (p.currency_code) currencies.add(p.currency_code);
                         });
                     }
                 });
             }
        });
        
        if (currencies.size === 0) {
            return ['CZK']; // Default
        }
        

        
        // Ensure CZK is first if present (Priority)
        const arr = Array.from(currencies);
        if (arr.includes('CZK')) {
            return ['CZK', ...arr.filter(c => c !== 'CZK')];
        }
        return arr;
    }

    
    static calculatePrice(payload, formModel) {
        let totalPrice = 0;
        let totalItems = 0;
        let currency = null;

        if (payload.ticket && payload.ticket.length > 0) {
            payload.ticket.forEach(t => {
                let ticketPrice = 0;
                
                // Spot Logic
                if (t.spotPrice) {
                    ticketPrice += parseFloat(t.spotPrice);
                }
                
                // Fields Logic
                if (t.fields) {
                    t.fields.forEach(f => {
                         // Use price on object if available (set by FormSession lookup)
                         if (f.price !== undefined) {
                             ticketPrice += parseFloat(f.price);
                         } 
                         
                         if (f.currency_code) currency = f.currency_code;
                    });
                }
                
                // If the ticket has a price (or is a valid item), count it
                // FIX: Count items even if price is 0 (User Request), BUT ONLY IF SELECTED.
                // We check if there are fields or a spot.
                const hasSelection = (t.fields && t.fields.length > 0) || t.spot || ticketPrice > 0;
                
                if (hasSelection) {
                    totalItems++;
                }
                
                if (ticketPrice > 0) {
                    totalPrice += ticketPrice;
                }
            });
        }

        // --- NEW: Top-Level Fields Handling ---
        // (Fix for Simple Mode / Direct Product Fields)
        if (payload.fields && payload.fields.length > 0) {
            payload.fields.forEach(f => {
                 let fieldPrice = 0;
                 if (f.price !== undefined) {
                     fieldPrice += parseFloat(f.price);
                 }
                 
                 if (fieldPrice > 0) {
                     totalPrice += fieldPrice;
                 }
                 
                 if (f.currency_code) currency = f.currency_code;
            });
        }

        return { totalPrice, totalItems, currency };
    }

    /**
     * Computes meta-surcharge sums grouped by currency across all selected products.
     * Visual-only — never added to totalPrice. Empty array if DepositFeature is off.
     * @returns {Array<{currency: string, sum: number}>}
     */
    static calculateMetaSurchargeSums(payload, formModel) {
        const features = formModel && formModel.occasionFeatures;
        if (!FeatureService.isFeatureEnabled(FeatureService.FeatureConstants.deposit, features)) {
            return [];
        }

        // Build a flat list of all fields (top-level + ticket subFields) to resolve product_type defs.
        const allFields = [];
        if (formModel.relatedFields) {
            formModel.relatedFields.forEach(f => {
                allFields.push(f);
                if (f.subFields) allFields.push(...f.subFields);
            });
        }
        const findFieldDef = (subFieldId) =>
            allFields.find(fd => String(fd.id) === String(subFieldId));

        const sumsByCurrency = new Map();
        const add = (amount, currency) => {
            if (!Number.isFinite(amount) || amount === 0) return;
            const key = currency || '';
            sumsByCurrency.set(key, (sumsByCurrency.get(key) || 0) + amount);
        };

        const collectFromField = (f) => {
            const fieldDef = findFieldDef(f._subFieldId);
            if (!fieldDef || fieldDef.type !== 'product_type') return;
            // FormFieldModel constructor maps products to fieldDef.options (FormOptionModel with .data carrying meta_surcharge).
            const options = fieldDef.options || [];
            if (options.length === 0) return;
            const selectedRaw = f.product_type !== undefined ? f.product_type : f[fieldDef.type];
            if (selectedRaw === undefined || selectedRaw === null) return;
            const parts = String(selectedRaw).split(' | ');
            parts.forEach(part => {
                const opt = options.find(o => String(o.id) === String(part));
                if (!opt || !opt.data || !opt.data.meta_surcharge) return;
                const ms = opt.data.meta_surcharge;
                const amount = typeof ms.amount === 'number' ? ms.amount : parseFloat(ms.amount);
                add(amount, ms.currency || DEFAULT_META_SURCHARGE_CURRENCY);
            });
        };

        if (payload.ticket) {
            payload.ticket.forEach(t => {
                if (t.fields) t.fields.forEach(collectFromField);
            });
        }
        if (payload.fields) {
            payload.fields.forEach(collectFromField);
        }

        return Array.from(sumsByCurrency.entries()).map(([currency, sum]) => ({ currency, sum }));
    }

    /**
     * Formats per-currency meta-surcharge sums into display strings.
     * Zero entries are filtered out so callers can render the result directly.
     * Used by the price widget (live total) and the order preview (final total).
     * @param {Array<{currency: string, sum: number}>} sums output of calculateMetaSurchargeSums
     * @param {string} locale e.g. LocalizationService.currentLocale
     * @returns {string[]} formatted lines like "+ 200 EUR" / "− 50 EUR"
     */
    static formatMetaSurchargeSumLines(sums, locale) {
        if (!Array.isArray(sums)) return [];
        return sums
            .filter(s => s && Number.isFinite(s.sum) && s.sum !== 0)
            .map(s => {
                const sign = s.sum < 0 ? '−' : '+';
                const abs = formatPrice(Math.abs(s.sum), s.currency, 0, locale);
                return `${sign} ${abs}`;
            });
    }
}
