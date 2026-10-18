import { FormStrings } from '../form_strings.js';
import { sanitizeHtml } from '../../../utils/html.js';

export class CountdownWidget {
    static timer = null;

    static render(container, formModel, onFinished) {
        // Cleanup previous timer if exists (though usually new instance handles it, 
        // static timer here helps if we re-render without full page reload)
        if (CountdownWidget.timer) {
            clearInterval(CountdownWidget.timer);
            CountdownWidget.timer = null;
        }

        const widget = document.createElement('div');
        widget.className = 'countdown-widget';
        
        const title = formModel.countdownTitle || FormStrings.registrationStart;
        const targetDate = new Date(formModel.startTime);

        widget.innerHTML = `
            <div class="countdown-title form-header">${sanitizeHtml(title)}</div>
            <div class="countdown-timer-row">
                <div class="time-block"><div class="time-value" id="cd-days">00</div><div class="time-label">${FormStrings.days}</div></div>
                <div class="time-block"><div class="time-value" id="cd-hours">00</div><div class="time-label">${FormStrings.hours}</div></div>
                <div class="time-block"><div class="time-value" id="cd-minutes">00</div><div class="time-label">${FormStrings.minutes}</div></div>
                <div class="time-block"><div class="time-value" id="cd-seconds">00</div><div class="time-label">${FormStrings.seconds}</div></div>
            </div>
        `;
        
        container.appendChild(widget);

        // Update Function
        const update = () => {
            const now = new Date();
            const diff = targetDate - now;

            if (diff <= 0) {
                CountdownWidget.stop();
                if (onFinished) onFinished();
                return;
            }

            const days = Math.floor(diff / (1000 * 60 * 60 * 24));
            const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
            const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
            const seconds = Math.floor((diff % (1000 * 60)) / 1000);

            const pad = (n) => n.toString().padStart(2, '0');
            
            const elD = widget.querySelector('#cd-days');
            const elH = widget.querySelector('#cd-hours');
            const elM = widget.querySelector('#cd-minutes');
            const elS = widget.querySelector('#cd-seconds');
            
            if(elD) elD.textContent = pad(days);
            if(elH) elH.textContent = pad(hours);
            if(elM) elM.textContent = pad(minutes);
            if(elS) elS.textContent = pad(seconds);
        };

        CountdownWidget.timer = setInterval(update, 1000);
        update(); // Immediate, after the interval exists so expiry can stop it.
    }

    static stop() {
        if (CountdownWidget.timer) {
            clearInterval(CountdownWidget.timer);
            CountdownWidget.timer = null;
        }
    }
}
