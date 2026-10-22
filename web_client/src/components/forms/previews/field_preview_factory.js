import { FormStrings } from '../form_strings.js';
import { LocalizationService } from '../../../services/localization_service.js';
import { formatPrice } from '../../../utils/formatters.js';
import { FeatureService, DEFAULT_META_SURCHARGE_CURRENCY } from '../../features/feature_service.js';

/**
 * Strategy interface:
 * {
 *    format(value, fieldDef, context) => string
 * }
 */

class BasePreviewStrategy {
    format(value, fieldDef, context) {
        if (value === null || value === undefined) return { value: '', price: null };
        
        // Safety Fallback for ID Documents catching Base Strategy
        if (typeof value === 'object' && value.id_document_number) {
            console.warn('[FieldPreviewFactory] ID Document caught in BaseStrategy via sniffing');
            // Delegate manually if we can't switch strategy easily, or just format here
            let display = value.id_document_number;
            if (value.id_document_expiry_date) {
                // Formatting isn't easily available here without referencing IdDocumentPreviewStrategy instance
                // So let's just do basic display to avoid [object Object]
                 display += ` (${value.id_document_expiry_date})`;
            }
            return { value: display, price: null };
        }

        // 1. Resolve Options (if applicable)
        let resolved = this._resolveValue(value, fieldDef, context);
        return resolved;
    }

    _getOptions(fieldDef) {
        return fieldDef.options || (fieldDef.data && fieldDef.data.options);
    }

    _resolveValue(val, fieldDef, context) {
        const options = this._getOptions(fieldDef);
        
        // Handle " | " for multi-selects
        const valStr = String(val);
        if (valStr.includes(' | ')) {
            const parts = valStr.split(' | ');
            // For multi-select, we currently don't support individual prices in the summary nicely
            // So we just join the titles and ignore price formatting for this specific case?
            // Or we assume sum? For now, let's just join titles and existing behavior.
            const mapped = parts.map(part => this._findOption(part, options, context));
            const joinedValue = mapped.map(m => m.value).join(', ');
            const metas = mapped.map(m => m.metaSurcharge).filter(Boolean);
            const metaSurcharge = metas.length > 0 ? metas.join('\n') : null;
            // We lose individual prices here, but that's consistent with complex behavior complexity
            return { value: joinedValue, price: null, metaSurcharge };
        }
        
        if (options && options.length > 0) {
            return this._findOption(val, options, context);
        }
        
        // Fallback for objects to avoid [object Object]
        if (typeof val === 'object') {
            return { value: JSON.stringify(val), price: null };
        }

        return { value: valStr, price: null };
    }

    _findOption(val, options, context) {
        const found = options.find(o => o.id != null && String(o.id) === String(val));
        if (found) {
            let title = found.title;
            let priceStr = null;
            const locale = LocalizationService.currentLocale;
            // Extract price if pertinent and available in context
            if (found.price && context && context.currency) {
                 priceStr = formatPrice(found.price, context.currency, context.cardPricing ? 2 : 0, locale);
            }
            const metaSurcharge = _buildMetaSurchargeForProduct(found, context);
            return { value: title, price: priceStr, metaSurcharge };
        }
        return { value: val, price: null };
    }
}

/**
 * Visual-only meta-surcharge text for a product in order preview rows.
 * Returns the string body (no wrapping element), or null when nothing should render.
 * NEVER affects payment/order totals.
 */
function _buildMetaSurchargeForProduct(product, context) {
    const features = context && context.features;
    if (!FeatureService.isFeatureEnabled(FeatureService.FeatureConstants.deposit, features)) {
        return null;
    }
    const description = FeatureService.getMetaSurchargeDescription(features);
    const ms = product && product.data && product.data.meta_surcharge;
    const amountRaw = ms ? (typeof ms.amount === 'number' ? ms.amount : parseFloat(ms.amount)) : null;
    const amount = Number.isFinite(amountRaw) && amountRaw !== 0 ? amountRaw : null;
    // No amount → render nothing. Global description alone is not enough.
    if (amount === null) return null;
    // Default currency matches the admin input placeholder ("EUR").
    const currency = (ms && ms.currency) || DEFAULT_META_SURCHARGE_CURRENCY;
    const locale = LocalizationService.currentLocale;
    const sign = amount < 0 ? '− ' : '+ ';
    const amountText = `${sign}${formatPrice(Math.abs(amount), currency, 0, locale)}`;
    return description ? `${amountText} — ${description}` : amountText;
}

class ProductTypePreviewStrategy extends BasePreviewStrategy {
    _getOptions(fieldDef) {
        // Prioritize internal schema for product types
        if (fieldDef.productTypeData?.products) return fieldDef.productTypeData.products;
        if (fieldDef.data && fieldDef.data.product_type_data && fieldDef.data.product_type_data.products) {
            return fieldDef.data.product_type_data.products;
        }
        return super._getOptions(fieldDef);
    }
}

class IdDocumentPreviewStrategy extends BasePreviewStrategy {
    format(value, fieldDef, context) {
         if (!value) return { value: '', price: null };
         
         let number, expiry;
         
         if (typeof value === 'object') {
             number = value.id_document_number;
             expiry = value.id_document_expiry_date;
         } else {
             number = value;
         }

         if (!number) return { value: '', price: null };

         let display = number;
         if (expiry) {
             const formattedExpiry = this._formatDate(expiry);
             display += ` (${formattedExpiry})`;
         }
         
         return { value: display, price: null };
    }

    _formatDate(dateStr) {
        if (!dateStr) return '';
        try {
            const date = new Date(dateStr);
            if (isNaN(date.getTime())) return dateStr;

            const locale = LocalizationService.currentLocale === 'cs' ? 'cs-CZ' : 'en-US';
            return new Intl.DateTimeFormat(locale, {
                year: 'numeric',
                month: 'numeric',
                day: 'numeric'
            }).format(date);
        } catch (e) {
            return dateStr;
        }
    }
}

class SexPreviewStrategy extends BasePreviewStrategy {
    format(value, fieldDef, context) {
        const label = value === 'male' ? FormStrings.maleLabel
            : value === 'female' ? FormStrings.femaleLabel
            : value === '' ? FormStrings.notSpecifiedLabel : null;
        return label == null ? super.format(value, fieldDef, context) : { value: label, price: null };
    }
}

class BirthDatePreviewStrategy extends BasePreviewStrategy {
    format(value, fieldDef, context) {
        // A birth date is a calendar date, independent of the viewer's timezone.
        const match = typeof value === 'string' && /^(\d{4})-(\d{2})-(\d{2})(?:$|T)/.exec(value);
        if (!match) return super.format(value, fieldDef, context);
        const [, year, month, day] = match;
        const date = new Date(`${year}-${month}-${day}T12:00:00Z`);
        if (!Number.isFinite(date.getTime()) || date.getUTCFullYear() !== Number(year) ||
            date.getUTCMonth() + 1 !== Number(month) || date.getUTCDate() !== Number(day)) {
            return super.format(value, fieldDef, context);
        }
        return { value: new Intl.DateTimeFormat(LocalizationService.currentLocale, {
            year: 'numeric', month: 'numeric', day: 'numeric', timeZone: 'UTC'
        }).format(date), price: null };
    }
}

export class FieldPreviewFactory {
    static _strategies = {
        'default': new BasePreviewStrategy(),
        'product_type': new ProductTypePreviewStrategy(),
        'id_document': new IdDocumentPreviewStrategy(),
        'sex': new SexPreviewStrategy(),
        'birth_date': new BirthDatePreviewStrategy()
    };

    static getStrategy(fieldDef) {
        return this._strategies[fieldDef.type] || this._strategies['default'];
    }
    
    /**
     * Main entry point
     * NB: Returns { value: string, price: string|null }
     */
    static format(fieldDef, value, context) {
        const strategy = this.getStrategy(fieldDef);
        const result = strategy.format(value, fieldDef, context);
        // Safety Fallback for legacy strategies if any exist or if logic didn't return object
        if (typeof result === 'string') {
            return { value: result, price: null };
        }
        return result;
    }
}
