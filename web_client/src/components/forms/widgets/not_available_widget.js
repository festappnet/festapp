import { FormStrings } from '../form_strings.js';

export class NotAvailableWidget {
    static render(container, formModel) {
        const wrapper = document.createElement('div');
        wrapper.className = 'not-available-widget';
        
        let text = formModel.headerOff;
        if (!text || text.length === 0) {
            text = FormStrings.reservationUnavailableMessage;
        }

        wrapper.innerHTML = `
            <i class="material-icons not-available-icon">event_busy</i>
            <div class="not-available-title">${FormStrings.reservationUnavailable}</div>
            <div class="not-available-message">${text}</div>
        `;
        container.appendChild(wrapper);
    }
}
