import { LocalizationService } from '../../../services/localization_service.js';
import { sanitizeHtml } from '../../../utils/html.js';
import { CountdownWidget } from './countdown_widget.js';
import { FormStrings } from '../form_strings.js';
import { saleOpeningText, renderSaleOpening } from '../sale_opening_notifications.js';

// One document owns order. Hydration occurs only after the common sanitizer.
export function renderPresaleContent(container, model, onFinished, {preview = false} = {}) {
    if (!preview && !model.enableCountdown) CountdownWidget.waitForOpening(model.startTime, onFinished);
    const doc = container.ownerDocument;
    const content = doc.createElement('div'); content.className = 'form-header form-presale-content';
    content.innerHTML = sanitizeHtml(model.presaleContent ?? model.countdownTitle ?? (model.enableCountdown ? `<p>${FormStrings.registrationStart}</p>` : ''));
    // The editor retains empty paragraphs and inactive countdown slots around blocks.
    content.querySelectorAll('.form-presale-system-title').forEach(el => { el.textContent = FormStrings.registrationStart; });
    content.querySelectorAll('.form-presale-legacy-secondary').forEach(el => {
        el.style.textAlign = 'left'; el.style.fontSize = '18px';
        el.style.margin = '12px'; el.style.lineHeight = '1.5';
    });
    const notification = content.querySelector('div.html-editor-block.form-sale-opening-notification');
    const surrounding = content.cloneNode(true);
    surrounding.querySelectorAll('.form-sale-opening-notification, .form-countdown').forEach(slot => slot.remove());
    if ((model.presaleHeader ?? (model.enableCountdown ? 'date' : 'none')) === 'none' && !model.enableCountdown && notification && (model.saleOpeningNotification?.canSubscribe || (preview && model.data?.sale_opening_notifications?.enabled && !model.data?.sale_opening_notifications?.collection_paused)) &&
        !surrounding.textContent.replace(/[\s\u200b]/gu, '') && !surrounding.querySelector('img,video,iframe,table,hr')) {
        content.classList.add('form-presale-subscription-only');
        content.replaceChildren(notification);
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
            CountdownWidget.render(slot, {...model, startTime: model.startTime, countdownTitle: ''}, preview ? () => {} : onFinished);
            slot.querySelector('.countdown-title')?.remove();
        } else if (model.saleOpeningNotification?.canSubscribe || (preview && model.data?.sale_opening_notifications?.enabled && !model.data?.sale_opening_notifications?.collection_paused)) renderSaleOpening(slot, model, {preview});
        else slot.remove();
    }
    const date = doc.createElement('p');
    if (model.startTime) date.textContent = new Intl.DateTimeFormat(LocalizationService.currentLocale || undefined, {dateStyle: 'full', timeStyle: 'short', timeZone: model.saleOpeningNotification?.timeZone || 'Europe/Prague'}).format(model.startTime);
    const meaningful = content.textContent.replace(/[\s\u200b]/gu, '') || content.querySelector('input,button,img,video,iframe,table,hr,.countdown-widget');
    const header = model.presaleHeader ?? (model.enableCountdown ? 'date' : 'none');
    if (!meaningful && !model.enableCountdown && header === 'none') {
        const opening = doc.createElement('p');
        opening.className = 'form-scheduled-opening';
        opening.textContent = saleOpeningText('scheduledStart').replace('{date}', () => date.textContent);
        content.append(opening);
    }
    if (header === 'event_and_date') {
        const title = doc.createElement('h2'); title.textContent = model.occasionTitle || model.title || '';
        container.append(title);
    }
    if (header !== 'none') container.append(date);
    container.append(content);
}
