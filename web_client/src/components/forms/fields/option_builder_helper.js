import { html, sanitizeHtml } from '../../../utils/html.js';
import { formatPrice } from '../../../utils/formatters.js';
import { FormStrings } from '../form_strings.js';
import { FeatureService, DEFAULT_META_SURCHARGE_CURRENCY } from '../../features/feature_service.js';
import { LocalizationService } from '../../../services/localization_service.js';

export class OptionBuilderHelper {
    /**
     * Detect whether card design should be used.
     */
    static isCardDesign(field, formModel) {
        const shouldCheckOptions = field.type !== 'product_type';
        const hasOptionDescription = shouldCheckOptions && field.options &&
            field.options.some(opt => opt.description && opt.description.trim().length > 0);

        return (formModel && formModel.isCardDesign) ||
               (field.description && field.description.trim().length > 0) ||
               hasOptionDescription;
    }

    /**
     * Build <label class="form-field-label"> with optional required star.
     */
    static buildFieldLabel(field) {
        const label = document.createElement('label');
        label.className = 'form-field-label';
        label.innerHTML = html`${field.title || ''}${field.isRequired ? html`<span class="required-star">*</span>` : ''}`;
        return label;
    }

    /**
     * Build <div class="form-field-description">.
     */
    static buildFieldDescription(field) {
        const desc = document.createElement('div');
        desc.className = 'form-field-description';
        desc.innerHTML = sanitizeHtml(field.description);
        return desc;
    }

    /**
     * Build a single option wrapper (radio or checkbox).
     * @param {object} field
     * @param {object} opt
     * @param {object} formModel
     * @param {'radio'|'checkbox'} inputType
     * @param {boolean} cardDesign
     * @returns {HTMLDivElement} wrapper element
     */
    static buildOptionWrapper(field, opt, formModel, inputType, cardDesign) {
        const wrapper = document.createElement('div');
        wrapper.className = 'form-check';
        if (cardDesign) wrapper.classList.add('option-card');

        const input = document.createElement('input');
        input.type = inputType;
        input.name = field.id;
        input.value = (opt.id !== undefined && opt.id !== null) ? opt.id : opt.title;
        input.id = `${field.id}_${(opt.id !== undefined && opt.id !== null) ? opt.id : opt.title}`;
        input.className = 'form-check-input';

        // Apply default selection from field.data.default_value (radio: string, checkbox: list of strings).
        // Matches by option title or id.
        if (OptionBuilderHelper.shouldPreselect(field, opt, inputType)) {
            input.checked = true;
        }

        // Currency tagging
        const currency = opt.currencyCode || opt.currency || opt.currency_code;
        if (currency) {
            input.setAttribute('data-currency', currency);
            wrapper.setAttribute('data-currency', currency);
        }

        // Full wrapper clickability
        wrapper.onclick = (e) => {
            if (e.target !== input && e.target.tagName !== 'LABEL' && !e.target.closest('label')) {
                input.click();
            }
        };

        // Rich label
        const optLabel = document.createElement('label');
        optLabel.className = 'form-check-label';
        optLabel.htmlFor = input.id;

        let labelContent = html`<span>${opt.title || ''}</span>`;
        if (opt.price) {
            const priceDisplay = formatPrice(opt.price, currency, 0, 'cs-CZ');
            labelContent = html`${labelContent}<span class="option-price">+ ${priceDisplay}</span>`;
        }
        optLabel.innerHTML = labelContent;

        // Content wrapper with label + optional deposit/description
        const contentWrapper = document.createElement('div');
        contentWrapper.appendChild(optLabel);

        const ticketField = formModel && formModel.relatedFields
            ? formModel.relatedFields.find(f => f.type === 'ticket')
            : null;
        const showDepositDescription = ticketField && ticketField.data && ticketField.data.show_surcharge_description !== undefined
            ? ticketField.data.show_surcharge_description
            : true;

        const depositData = opt.data && opt.data.deposit;
        const isDepositAvailable = FeatureService.isDepositChoiceAvailable(
            formModel && formModel.occasionFeatures,
            formModel && formModel.occasionStartTime
        );
        const hasDeposit = showDepositDescription && isDepositAvailable && depositData && depositData.amount && depositData.amount > 0;

        const metaSurchargeHtml = OptionBuilderHelper.buildMetaSurchargeHtml(opt, formModel);

        if (opt.description || hasDeposit || metaSurchargeHtml) {
            const optDesc = document.createElement('span');
            optDesc.className = 'option-description';

            let descHtml = html``;
            // Order: deposit (bold) → meta surcharge → original description
            if (hasDeposit) {
                const depositPrice = formatPrice(depositData.amount, currency, 0, 'cs-CZ');
                descHtml = html`${descHtml}<span class="deposit-info">${FormStrings.depositInfo}: ${depositPrice}</span>`;
                if (metaSurchargeHtml || opt.description) descHtml = html`${descHtml}<br>`;
            }
            if (metaSurchargeHtml) {
                descHtml = html`${descHtml}${sanitizeHtml(metaSurchargeHtml)}`;
                if (opt.description) descHtml = html`${descHtml}<br>`;
            }
            if (opt.description) {
                descHtml = html`${descHtml}${sanitizeHtml(opt.description)}`;
            }

            optDesc.innerHTML = descHtml;
            contentWrapper.appendChild(optDesc);
        }

        wrapper.appendChild(input);
        wrapper.appendChild(contentWrapper);

        return wrapper;
    }

    /**
     * Visual-only meta-surcharge label rendered above the description (form, preview).
     * Returns the inner HTML string (wrapped in span.meta-surcharge), or '' when nothing should render.
     * Negative amounts represent discounts (slevy) and render with a leading "−".
     * NEVER affects payment totals — purely informational.
     */
    static buildMetaSurchargeHtml(opt, formModel) {
        const features = formModel && formModel.occasionFeatures;
        if (!FeatureService.isFeatureEnabled(FeatureService.FeatureConstants.deposit, features)) {
            return '';
        }
        // Meta surcharge applies only to product options (has currency or explicit meta_surcharge data).
        const isProductLike = !!(opt && (opt.currencyCode || opt.currency || opt.currency_code
            || (opt.data && opt.data.meta_surcharge)));
        if (!isProductLike) return '';

        const description = FeatureService.getMetaSurchargeDescription(features);
        const ms = opt && opt.data && opt.data.meta_surcharge;
        const amountRaw = ms && (typeof ms.amount === 'number' ? ms.amount : parseFloat(ms.amount));
        const amount = Number.isFinite(amountRaw) && amountRaw !== 0 ? amountRaw : null;
        // No amount → render nothing. Global description alone is not enough.
        if (amount === null) return '';

        // Default currency matches the placeholder shown in the admin input ("EUR").
        // Surcharge doesn't share the product price currency by default.
        const currency = (ms && ms.currency) || DEFAULT_META_SURCHARGE_CURRENCY;
        const locale = LocalizationService.currentLocale;
        const sign = amount < 0 ? '− ' : '+ ';
        const amountText = `${sign}${formatPrice(Math.abs(amount), currency, 0, locale)}`;
        const body = description ? `${amountText} — ${description}` : amountText;
        return html`<span class="meta-surcharge">${body}</span>`.toString();
    }

    static shouldPreselect(field, opt, inputType) {
        // Existing answer (field.value) takes precedence — defaults only apply to fresh forms.
        if (inputType === 'radio' && field.value !== undefined && field.value !== null && field.value !== '') {
            return false;
        }
        const def = field && field.data && field.data.default_value;
        if (def == null) return false;
        // Match either by option.title (select_one/many) or option.id (product_type).
        const matches = (key) => key === opt.title || String(key) === String(opt.id);
        if (inputType === 'checkbox') {
            return Array.isArray(def) && def.some(matches);
        }
        return matches(def);
    }
}
