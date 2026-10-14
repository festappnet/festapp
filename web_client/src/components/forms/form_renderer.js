import { FormStrings } from './form_strings.js';
import { CommonStrings } from '../shared/common_strings.js';
import { FormFieldBuilder } from './fields/form_field_builder.js';
import { DbForms } from './db_forms.js';
import { html, sanitizeHtml } from '../../utils/html.js';

export class FormRenderer {
    
    static render(container, session, formModel, showPreview, callbacks) {
        // Declarative Layout
        container.innerHTML = html`
            <div class="form-wrapper ${formModel.isCardDesign ? 'is-card-design' : ''}">
                ${formModel.demoSimulation ? html`<p role="status" class="demo-form-notice">${FormStrings.demoNotice}</p>` : ''}
                ${showPreview ? html`<div style="width:100%; color:black; background:orange; padding:8px; margin-bottom:16px; text-align:center; font-weight:bold; font-size:13px;">${FormStrings.previewMode}</div>` : ''}
                
                ${formModel.header ? html`<div class="form-header">${sanitizeHtml(this._optimizeLcp(formModel.header))}</div>` : ''}
                
                ${formModel.description ? html`<div class="form-description">${sanitizeHtml(formModel.description)}</div>` : ''}

                <form id="dynamic-form" novalidate>
                    <!-- Fields will be appended here -->
                    <div id="fields-container"></div>

                    <div class="form-actions">
                        <button type="submit" class="btn btn-primary btn-submit">${FormStrings.buttonContinue}</button>
                    </div>
                </form>
            </div>
        `;

        const form = container.querySelector('#dynamic-form');
        const fieldsContainer = form.querySelector('#fields-container');

        // Append Fields (FormFieldBuilder still returns Nodes)
        (formModel.displayFields || formModel.visibleFields).forEach(field => {
            const definition = session.state.fields.has(String(field.id))
                ? { ...field, value: session.state.fields.get(String(field.id)) } : field;
            const fieldComponent = FormFieldBuilder.createFormField(definition, formModel, session);
            fieldsContainer.appendChild(fieldComponent);
        });
        
        // Bind Callbacks
        form.onsubmit = (e) => {
            e.preventDefault();
            if(callbacks.onSubmit) callbacks.onSubmit(form, formModel);
        }

        // BACKUP: Explicit Click Listener
        // Some mobile browsers or specific states might not fire 'submit' if 'novalidate' is weirdly handled
        // or if something else intercepts.
        const submitBtn = form.querySelector('.btn-submit');
        if (submitBtn) {
            submitBtn.onclick = (e) => {
                 // If default submit fires, this runs first. 
                 // We prevent default here too to specific double-submit if both fire?
                 // Actually, if we prevent default on click, submit event might not fire for button?
                 // Let's just monitor. If 'submit' doesn't fire, we manually fire it?
                 // No, safer is: Click -> Prevent Default -> Call Submit Logic directly.
                 e.preventDefault();
                 if(callbacks.onSubmit) callbacks.onSubmit(form, formModel);
            };
        }

        const updateHandler = (e) => {
            if(callbacks.onInput) callbacks.onInput(e, form, formModel);
        };
        form.addEventListener('input', updateHandler);
        // Change event needed for some inputs
        form.addEventListener('change', updateHandler);
    }

    static _optimizeLcp(htmlContent) {
        if (!htmlContent) return htmlContent;
        // Inject fetchpriority="high" into the first img tag
        // Simple regex replace for the first occurrence
        return htmlContent.replace(/<img\s/, '<img fetchpriority="high" ');
    }

    // _renderHeader helper removed as it is now inlined in render() template
}
