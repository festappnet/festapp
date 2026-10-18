import { sanitizeHtml } from '../../utils/html.js';
import { WaitlistStrings } from './waitlist_strings.js';
import { CountdownWidget } from './widgets/countdown_widget.js';
import { NotAvailableWidget } from './widgets/not_available_widget.js';

export class FormAvailabilityService {

    static Status = {
        OPEN: 'OPEN',
        CLOSED: 'CLOSED',
        BEFORE_START: 'BEFORE_START',
        // SOLD_OUT: 'SOLD_OUT' // Future use
    };

    /**
     * Determines the current status of the form based on time and settings.
     * @param {Object} formModel
     * @returns {Object} { status, message, targetTime? }
     */
    static getStatus(formModel) {
        if (formModel.registrationMode === 'offer') return { status: this.Status.OPEN };
        if (formModel.isOpen === false) return { status: this.Status.CLOSED };
        const now = new Date();

        if (formModel.startTime && now < formModel.startTime) {
            return {
                status: FormAvailabilityService.Status.BEFORE_START,
                targetTime: formModel.startTime
            };
        }

        if (formModel.registrationMode === 'full') return { status: 'FULL' };
        if (formModel.registrationMode === 'closed') return { status: this.Status.CLOSED };

        if (formModel.endTime && now > formModel.endTime) {
            return { status: FormAvailabilityService.Status.CLOSED };
        }


        return { status: FormAvailabilityService.Status.OPEN };
    }

    /**
     * Renders the appropriate UI for the current status into the container.
     * @param {HTMLElement} container
     * @param {Object} formModel
     * @param {Object} statusResult Result from getStatus
     * @param {Object} context Context like { showPreview: boolean, onReload: function }
     * @returns {boolean} True if rendering handled (flow should stop), False if form should proceed (OPEN).
     */
    static renderStatus(container, formModel, statusResult, context = {}) {
        const { showPreview } = context;
        const { status } = statusResult;

        if (status === 'FULL' && !showPreview) {
            container.replaceChildren();
            if (formModel.header) {
                const intro = document.createElement('div');
                intro.className = 'form-header'; intro.innerHTML = sanitizeHtml(formModel.header); container.appendChild(intro);
            }
            const message = document.createElement('p');
            message.textContent = WaitlistStrings.full;
            container.appendChild(message);
            return true;
        }
        // Preview Mode overrides everything
        if (showPreview) return false;

        if (status === FormAvailabilityService.Status.BEFORE_START) {
            if (formModel.enableCountdown) {
                container.replaceChildren();
                CountdownWidget.render(container, formModel, context.onReload);
                if (formModel.showBeforeStartMessage && formModel.beforeStartMessage) {
                    const information = document.createElement('div');
                    information.className = 'form-before-start-message form-header';
                    information.innerHTML = sanitizeHtml(formModel.beforeStartMessage);
                    container.appendChild(information);
                }
                return true; // Stop flow
            }
            // If countdown disabled, fall through to Not Available
        }

        if (status === FormAvailabilityService.Status.CLOSED || status === FormAvailabilityService.Status.BEFORE_START) {
            container.replaceChildren();
            NotAvailableWidget.render(container, formModel);
            return true; // Stop flow
        }

        return false; // OPEN
    }
}
