import './occasion_card.css';
import { LocalizationService } from '../../services/localization_service.js';
import { TimeHelper } from '../../services/time_helper.js';
import { FeatureService } from '../features/feature_service.js';
import { FeatureConstants } from '../features/feature_constants.js';
import { transformImageUrl, MEDIUM_WIDTH } from '../../utils/image_url_helper.js';
import { getOccasionHref } from './occasion_link.js';

// Presentation owner for both the public catalogue and the settings preview.
export function createOccasionCardView(occasion, { isPresent = false, isPast = false, locale = LocalizationService.currentLocale } = {}) {
    const href = getOccasionHref(occasion);
    const card = document.createElement(href ? 'a' : 'div');
    if (href) card.href = href;
    card.className = `oc-card ${isPresent ? 'oc-present' : ''}`;

    // Keep the full promotional image separate from the event metadata.
    const media = document.createElement('div');
    media.className = 'oc-media';
    if (occasion.data?.image) {
        const img = document.createElement('img');
        img.src = transformImageUrl(occasion.data.image, { width: MEDIUM_WIDTH });
        img.alt = occasion.title || 'Event Image';
        img.className = 'oc-bg';
        media.appendChild(img);
    }

    // Overlay for Past
    if (isPast) {
        const overlay = document.createElement('div');
        overlay.className = 'oc-overlay-past';
        media.appendChild(overlay);
    }

    card.appendChild(media);

    // Metadata below the image
    const header = document.createElement('div');
    header.className = 'oc-header';

    // Missing or invalid dates must not hide an otherwise public event.
    const start = occasion.start_time ? new Date(occasion.start_time) : null;
    const end = occasion.end_time ? new Date(occasion.end_time) : null;
    const dateStr = start && end && Number.isFinite(start.getTime()) && Number.isFinite(end.getTime())
        ? TimeHelper.getMinimalisticDateRange(start, end, locale) : '';

    const infoRow = document.createElement('div');
    infoRow.className = 'oc-info-row';

    const infoDiv = document.createElement('div');
    infoDiv.className = 'oc-info';

    const dateDiv = document.createElement('div');
    dateDiv.className = 'oc-date';
    dateDiv.textContent = dateStr;

    const titleDiv = document.createElement('div');
    titleDiv.className = 'oc-title';
    titleDiv.textContent = occasion.title || '';

    if (dateStr) infoDiv.appendChild(dateDiv);
    infoDiv.appendChild(titleDiv);
    if (href) {
        const arrow = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        arrow.classList.add('oc-arrow');
        arrow.setAttribute('viewBox', '0 0 24 24');
        arrow.setAttribute('fill', 'none');
        arrow.setAttribute('stroke', 'currentColor');
        arrow.setAttribute('stroke-width', '1.7');
        arrow.setAttribute('aria-hidden', 'true');
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        path.setAttribute('d', 'M4 12h15m-6-6 6 6-6 6');
        arrow.appendChild(path);
        infoDiv.appendChild(arrow);
    }
    infoRow.appendChild(infoDiv);

    const formFeature = FeatureService.getFeatureDetails(FeatureConstants.form, occasion.features);
    if (formFeature && formFeature.formExternalPrice) {
         const badge = document.createElement('div');
         badge.className = 'oc-price-badge';
         badge.textContent = formFeature.formExternalPrice;
         infoRow.appendChild(badge);
    }

    header.appendChild(infoRow);
    card.appendChild(header);

    return card;
}
