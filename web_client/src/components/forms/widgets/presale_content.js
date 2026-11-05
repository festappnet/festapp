import { LocalizationService } from '../../../services/localization_service.js';
import { sanitizeHtml } from '../../../utils/html.js';
import { CountdownWidget } from './countdown_widget.js';
import { FormStrings } from '../form_strings.js';
import { saleOpeningText, renderSaleOpening } from '../sale_opening_notifications.js';

// One document owns order. Hydration occurs only after the common sanitizer.
export function renderPresaleContent(container, model, onFinished, {preview = false} = {}) {
    if (!model.enableCountdown) CountdownWidget.waitForOpening(model.startTime, onFinished);
    const doc = container.ownerDocument;
    const content = doc.createElement('div'); content.className = 'form-header form-presale-content';
    content.innerHTML = sanitizeHtml(model.countdownTitle ?? `<p>${FormStrings.registrationStart}</p>`);
    // Center the standalone opt-in without rearranging authored countdown content.
    if (!model.enableCountdown && content.children.length === 1 &&
        content.firstElementChild.matches('.html-editor-block.form-sale-opening-notification') && !content.textContent.trim()) {
        content.classList.add('form-presale-subscription-only');
    }
    const types = ['form-countdown', 'form-sale-opening-notification'];
    // Legacy countdown documents without a slot keep their original behavior.
    if (model.enableCountdown && !content.querySelector('.html-editor-block.form-countdown')) {
        const slot = doc.createElement('div'); slot.className = 'html-editor-block form-countdown'; content.append(slot);
    }
    for (const type of types) {
        const slots = [...content.querySelectorAll(`div.html-editor-block.${type}`)];
        for (const duplicate of slots.slice(1)) duplicate.remove();
        const slot = slots[0]; if (!slot) continue;
        if (type === 'form-countdown') {
            if (!model.enableCountdown) { slot.remove(); continue; }
            CountdownWidget.render(slot, {...model, startTime: model.startTime, countdownTitle: ''}, onFinished);
            slot.querySelector('.countdown-title')?.remove();
        } else if (model.saleOpeningNotification?.canSubscribe || preview) renderSaleOpening(slot, model, {preview});
        else slot.remove();
    }
    const date = doc.createElement('p');
    if (model.startTime) date.textContent = new Intl.DateTimeFormat(LocalizationService.currentLocale || undefined, {dateStyle: 'full', timeStyle: 'short', timeZone: model.saleOpeningNotification?.timeZone || 'Europe/Prague'}).format(model.startTime);
    const meaningful = content.textContent.replace(/[\s\u200b]/gu, '') || content.querySelector('input,button,img,video,iframe,table,hr,.countdown-widget');
    if (!meaningful && !model.enableCountdown) {
        const opening = doc.createElement('p');
        opening.className = 'form-scheduled-opening';
        opening.textContent = saleOpeningText('scheduledStart').replace('{date}', () => date.textContent);
        content.append(opening);
    }
    if (model.enableCountdown) container.append(date);
    container.append(content);
}
