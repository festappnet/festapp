import { ColorUtils } from '../../../utils/color_utils.js';
import { FormStrings } from '../form_strings.js';

export class CurrencySelectorWidget {
    constructor(session, container) {
        this.session = session;
        this.container = container;
        this.element = null;
        
        // Subscribe to changes
        this._handleStateChange = this._onStateChange.bind(this);
        this.session.addEventListener('state-changed', this._handleStateChange);
        
        this.render();
    }

    render() {
        const { currency, availableCurrencies } = this.session.state;
        
        // Remove existing if any
        if (this.element) {
            this.element.remove();
            this.element = null;
        }

        // Only show if multiple currencies
        if (!availableCurrencies || availableCurrencies.length <= 1) {
            return;
        }

        this.element = document.createElement('div');
        this.element.className = 'currency-selector-widget';
        this.element.style.cssText = `
            margin-bottom: 24px;
            width: 100%;
            display: flex;
            flex-direction: column;
            align-items: flex-start;
        `;

        // Title
        const title = document.createElement('div');
        title.className = 'currency-selector-title';
        title.textContent = FormStrings.currencySelectLabel;
        title.style.cssText = `
            font-size: 14px;
            color: var(--text-color, #000); /* Fallback to black for light theme */
            margin-bottom: 8px;
            opacity: 0.8;
            font-weight: 500;
        `;
        this.element.appendChild(title);

        // Buttons Container (Segmented Control style)
        const btnGroup = document.createElement('div');
        btnGroup.className = 'currency-btn-group';
        btnGroup.style.cssText = `
            display: inline-flex;
            background-color: var(--surface-color, rgba(255, 255, 255, 0.05)); 
            border-radius: 8px;
            overflow: hidden;
            border: 1px solid var(--divider-color, rgba(0, 0, 0, 0.1));
        `;

        availableCurrencies.forEach((code, index) => {
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'btn currency-btn';
            btn.textContent = code;
            
            const isSelected = code === currency;
            
            // Base Style
            btn.style.cssText = `
                border: none;
                padding: 10px 24px;
                font-size: 14px;
                font-weight: 500;
                cursor: pointer;
                transition: background-color 0.2s, color 0.2s;
                min-width: 80px;
                background-color: transparent;
                color: var(--text-color, #000);
                opacity: 0.6;
                border-radius: 0; /* Explicitly no radius for segmented look */
                flex: 1; /* Stretch to fill */
            `;
            
            // Border logic (divider between buttons)
            if (index > 0) {
                // Use a pseudo-element or actual border. 
                // Actual border on the left of item works if radius is 0.
                btn.style.borderLeft = '1px solid var(--divider-color, rgba(0, 0, 0, 0.1))';
            }

            if (isSelected) {
                this._applySelectedStyle(btn);
            }

            btn.onclick = () => {
                this.session.setCurrency(code);
            };
            
            btnGroup.appendChild(btn);
        });

        this.element.appendChild(btnGroup);

        // Insert logic
        // Find the first product or ticket field to insert before
        const formModel = this.session.formModel;
        let targetFieldId = null;
        
        if (formModel && formModel.visibleFields) {
            const firstProductField = formModel.visibleFields.find(f => 
                f.type === 'product_type' || f.type === 'ticket'
            );
            if (firstProductField) {
                targetFieldId = firstProductField.id;
            }
        }

        let inserted = false;
        if (targetFieldId) {
             // 1. Try finding container by data-field-id (Ticket Fields)
             let targetContainer = this.container.querySelector(`.form-field-container[data-field-id="${targetFieldId}"]`);
             
             // 2. If not found, try finding input by name (Product/Radio Fields)
             if (!targetContainer) {
                 const targetInput = this.container.querySelector(`input[name="${targetFieldId}"]`);
                 if (targetInput) {
                     targetContainer = targetInput.closest('.form-field-container');
                 }
             }

             if (targetContainer && targetContainer.parentNode) {
                 targetContainer.parentNode.insertBefore(this.element, targetContainer);
                 inserted = true;
             }
        }

        if (!inserted) {
             // Fallback: Insert after header or prepend to wrapper
            const header = this.container.querySelector('.form-header') || this.container.querySelector('h1.form-title');
            
            if (header && header.parentElement) {
                if (header.nextSibling) {
                    header.parentElement.insertBefore(this.element, header.nextSibling);
                } else {
                    header.parentElement.appendChild(this.element);
                }
            } else {
                // Fallback: Try to find wrapper
                const wrapper = this.container.querySelector('.form-wrapper');
                if (wrapper) {
                    wrapper.prepend(this.element);
                } else {
                    this.container.prepend(this.element);
                }
            }
        }
    }

    _applySelectedStyle(btn) {
        // Active Style (Purpleish/Primary as per Flutter theme or Screenshot)
        // Screenshot shows a muted purple/dark grey for active.
        // Let's use the primary color with some opacity or a specific dark overlay.
        // Assuming primary color variable is available.
        btn.style.backgroundColor = 'var(--primary-color, #6200EE)'; 
        btn.style.color = '#fff'; 
        btn.style.opacity = '1';
        // If the primary color is very bright, text might need to be dark, but screenshot shows light text on dark rect.
        // Let's assume standard behavior: Primary background, White text.
        // Or slightly transparent primary.
        
        // Add a class for potential external CSS overrides
        btn.classList.add('active');
    }

    _onStateChange(e) {
        const newState = e.detail;
        if (this.element) {
            // Re-render whole group is safer for segmented control border logic / styles
            this.render();
        } 
    }

    destroy() {
        this.session.removeEventListener('state-changed', this._handleStateChange);
        if (this.element) {
            this.element.remove();
        }
    }
}
