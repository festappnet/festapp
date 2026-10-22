import { ColorUtils } from '../../../utils/color_utils.js';
import { formatPrice } from '../../../utils/formatters.js';
import { LocalizationService } from '../../../services/localization_service.js';
import { FormHelper } from '../form_helper.js';

export class PriceWidget {
    constructor(formSession, container) {
        this.session = formSession;
        this.container = container;
        this.element = null;
        this.isVisible = false;
        
        // Bind for listener
        this._onStateChange = this._onStateChange.bind(this);
        
        // Subscribe
        this.session.addEventListener('state-changed', this._onStateChange);
    }

    _onStateChange(e) {
        const state = e.detail;
        this.render(state);
    }

    render(state = null) {
        const { totalPrice, totalItems, currency, metaSurchargeSums } = state || this.session.currentState;

        // Logic matched from FormPage._renderFloatingPriceWidget
        const formModel = this.session.formModel;
        const isBlueprint = !!formModel.blueprint;

        // Condition:
        // Unified Logic: Show if EITHER price > 0 OR items > 0
        // This supports free products (items > 0, price = 0)
        let shouldHide = false;
        
        if (totalPrice <= 0 && totalItems <= 0) {
            shouldHide = true;
        }

        if (shouldHide) {
             if (this.element) {
                 this.element.remove();
                 this.element = null;
             }
             this.updateSubmitButton(false);
             return;
        }

        this.updateSubmitButton(true);

        if (!this.element) {
            this.element = document.createElement('div');
            this.element.id = 'floating-price-widget';
            this.element.className = 'floating-price-widget';
            
            // Attach to BODY to break out of any stacking contexts (transforms) in the app
            document.body.appendChild(this.element);

            // Apply Styling
            // We use the CSS variable as the source of truth because ThemeService might have 
            // adjusted it (e.g. for Dark Mode contrast)
            const primaryColor = 'var(--primary-color)';
            
            // Resolve CSS variable if needed
            const resolvedColor = this._resolveColor(primaryColor);
            const textColor = ColorUtils.isLight(resolvedColor) ? 'black' : 'white';

            this.element.style.cssText = `
                position: fixed; /* Always fixed as requested */
                top: 16px;
                right: 16px;
                z-index: 2005; /* Above Blueprint Modal */

                background-color: ${primaryColor};
                color: ${textColor};
                padding: 12px 16px;
                border-radius: 8px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.3);
                display: flex;
                flex-direction: column;
                align-items: flex-end;
                font-family: var(--font-family-base);
                font-weight: 600 !important;
                font-size: 1.1rem;
                animation: fadeIn 0.3s ease-out;
                cursor: pointer;
            `;
            

            // Use flexbox on container? No, container has form content.
            // Let's use absolute positioning relative to a sticky wrapper?
            // Actually, simplest 'Floating' behavior in flow:
            // position: sticky; top: 16px; left: 100%; transform: translateX(-100%); ?
            // No.
            
            // Let's try explicit sticky behavior.

            
            // Note: If container has padding, sticky respects it.
            // form-page-container usually has padding.
            
            this.element.onclick = () => {
                const submitBtn = document.querySelector('#dynamic-form button[type="submit"]');
                if (submitBtn) submitBtn.scrollIntoView({ behavior: 'smooth' });
            };
        }

        const locale = LocalizationService.currentLocale;
        const formattedPrice = formatPrice(totalPrice, currency, 0, locale);

        // Per-currency meta surcharge lines (visual-only, NOT added to totalPrice).
        // Negative amounts (slevy) render with "−".
        const metaLines = FormHelper.formatMetaSurchargeSumLines(metaSurchargeSums, locale);

        const metaHtml = metaLines.length > 0
            ? `<div style="font-size: 0.9rem; font-weight: 700; margin-top: 4px;">
                 ${metaLines.map(l => `<div>${l}</div>`).join('')}
               </div>`
            : '';

        this.element.innerHTML = `
            <div style="display: flex; align-items: center;">
                <span style="margin-right: 6px; font-weight: 600;">${totalItems}x</span>
                <i class="material-icons" style="font-size: 24px; margin-right: 10px;">local_activity</i>
                <span style="font-weight: 600;">${formattedPrice}</span>
            </div>
            ${metaHtml}
        `;
    }

    updateSubmitButton(isEnabled) {
        // We need to find the submit button. Ideally the session knows the form, or we search?
        // FormSession doesn't store DOM. We search by ID as 'dynamic-form' is standard.
        // Use container if available to avoid global search
        const context = this.container || document;
        const form = context.querySelector('#dynamic-form') || document.getElementById('dynamic-form');
        
        if (!form) return;
        
        const submitBtn = form.querySelector('button[type="submit"]');
        const hasTicketField = this.session.formModel.visibleFields.some(f => f.type === 'ticket');
        
        if (hasTicketField && submitBtn) {
            if (isEnabled) {
                submitBtn.disabled = false;
                submitBtn.classList.remove('disabled');
                submitBtn.style.opacity = '1';
                submitBtn.style.cursor = 'pointer';
            } else {
                submitBtn.disabled = true;
                submitBtn.classList.add('disabled');
                submitBtn.style.opacity = '0.5';
                submitBtn.style.cursor = 'not-allowed';
            }
        }
    }

    destroy() {
        this.session.removeEventListener('state-changed', this._onStateChange);
        if (this.element) this.element.remove();
    }

    _resolveColor(colorString) {
        if (!colorString) return null;
        if (colorString.startsWith('var(--')) {
            try {
                const varName = colorString.match(/var\(([^)]+)\)/)[1];
                // We resolve against document.body as ThemeService sets overrides there
                const resolved = getComputedStyle(document.body).getPropertyValue(varName).trim();
                return resolved || colorString; 
            } catch (e) {
                return colorString;
            }
        }
        return colorString;
    }
}
