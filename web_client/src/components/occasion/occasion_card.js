import { createOccasionCardView } from './occasion_card_view.js';
import { RouterService } from '../../services/router_service.js';
import { FeatureService } from '../features/feature_service.js';
import { FeatureConstants } from '../features/feature_constants.js';
import { HtmlUtils } from '../../utils/html_utils.js';
import { OccasionDetailDialog } from './occasion_detail_dialog.js';
import { AppConfig } from '../../app_config.js';
import { OccasionCardAction, resolveOccasionCardAction } from './occasion_card_action.js';
import { getOccasionHref } from './occasion_link.js';

export class OccasionCard {
    static create(occasion, isPresent = false, isPast = false) {
        const href = getOccasionHref(occasion);
        const card = createOccasionCardView(occasion, { isPresent, isPast });
        
        // --- Logic Dependencies ---
        const hasFormFeature = FeatureService.isFeatureEnabled(FeatureConstants.form, occasion.features);
        const isDescriptionEmpty = HtmlUtils.isHtmlEmptyOrNull(occasion.description);
        const action = resolveOccasionCardAction({
            hasFormFeature,
            isDescriptionEmpty,
            isAppSupported: AppConfig.isAppSupported,
        });

        // --- Click Handler (Exact Flutter Logic) ---
        card.onclick = async (event) => {
             if (!href || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
             event.preventDefault();
             // Logic aligned with Flutter:
             // 1. If skipDialog (Has Form + No Description) -> Execute Action immediately 
             // 2. If Has Form + Description -> Show Dialog 
             // 3. If No Form -> Navigate to App
             if (action === OccasionCardAction.reserve) {
                 await OccasionDetailDialog.handleReserveAction(occasion);
             } else if (action === OccasionCardAction.details) {
                 OccasionDetailDialog.show(occasion);
             } else {
                 // Navigate to Occasion App
                 RouterService.navigateToOccasionApp(occasion.link);
             }
        };

        return card;
    }
}
