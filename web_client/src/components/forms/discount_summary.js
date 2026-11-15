import {LocalizationService} from '../../services/localization_service.js';
import {formatPrice} from '../../utils/formatters.js';
import {html} from '../../utils/html.js';

/** Presentation of the server's quote/snapshot; never recomputes a discount. */
export function discountSummaryHtml(discount) {
    const text = key => html`${LocalizationService.tr(`DiscountCodes.${key}`)}`;
    const money = key => html`${formatPrice(discount[key], discount.currency, 2, LocalizationService.currentLocale)}`;
    return `<section class="discount-summary">
        <p class="discount-summary-code">${text('code')}: <strong>${html`${discount.code}`}</strong></p>
        <dl class="discount-summary-amounts">
            <div class="discount-summary-row"><dt>${text('base')}</dt><dd>${money('base')}</dd></div>
            <div class="discount-summary-row"><dt>${text('discount')}</dt><dd>−${money('discount')}</dd></div>
            <div class="discount-summary-row discount-summary-total"><dt>${text('net')}</dt><dd>${money('net')}</dd></div>
        </dl>
    </section>`;
}
