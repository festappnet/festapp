import { LocalizationService } from '../../services/localization_service.js';
import { RouterService } from '../../services/router_service.js';
import { ThemeService } from '../../services/theme_service.js';
import { TimeHelper } from '../../services/time_helper.js';
import { FeatureService } from '../features/feature_service.js';
import { FeatureConstants } from '../features/feature_constants.js';
import { CommonStrings } from '../shared/common_strings.js';
import { FormPage } from '../forms/form_page.js';
import { getOccasionHref } from './occasion_link.js';

export class OccasionDetailDialog {

    static show(occasion) {
        // Create Overlay
        const overlay = document.createElement('div');
        overlay.className = 'overlay visible';
        
        // Lock body scroll
        document.body.style.overflow = 'hidden';

        overlay.style.position = 'fixed';
        overlay.style.top = '0';
        overlay.style.left = '0';
        overlay.style.width = '100%';
        overlay.style.height = '100%';
        
        overlay.style.display = 'flex';
        overlay.style.alignItems = 'center'; // Align to center vertically
        overlay.style.justifyContent = 'center'; // Center horizontally
        overlay.style.zIndex = '2000'; // High z-index
        
        // Resolve Text
        const title = occasion.title || '';
        const description = occasion.description || '';
        const dateStr = TimeHelper.getMinimalisticDateRange(new Date(occasion.start_time), new Date(occasion.end_time), LocalizationService.currentLocale);
        
        // Feature Details for Button Title
        const formFeature = FeatureService.getFeatureDetails(FeatureConstants.form, occasion.features);
        let reserveTitle = LocalizationService.tr("Common.reserveASpot");
        if (formFeature && formFeature.reserveButtonTitle) {
            reserveTitle = formFeature.reserveButtonTitle;
        }

        let btnStyle = 'width: 100%; padding: 12px;';
        if (formFeature && formFeature.primaryColor) {
             let bgColor = formFeature.primaryColor.trim();
             if (!bgColor.startsWith('#')) bgColor = '#' + bgColor;
             const textColor = ThemeService.getBestTextColor(bgColor);
             btnStyle += ` background-color: ${bgColor} !important; color: ${textColor} !important; border: none;`;
        }

        overlay.innerHTML = `
            <div class="overlay-content dialog-content" style="
                max-width: 600px;
                width: 90%;
                max-height: 90vh;
                display: flex;
                flex-direction: column;
                border-radius: 12px;
                background: var(--card-bg, white);
                position: relative;
                color: var(--text-color, #000);
            ">
                <!-- Sticky Header -->
                <div style="
                    padding: 24px 24px 16px 24px;
                    border-bottom: 1px solid var(--divider-color, #e0e0e0);
                    flex-shrink: 0;
                    position: relative;
                    background: var(--card-bg, white);
                    border-radius: 12px 12px 0 0;
                ">
                    <button class="close-btn" style="
                        position: absolute;
                        top: 16px;
                        right: 16px;
                        background: none;
                        border: none;
                        font-size: 28px;
                        cursor: pointer;
                        color: var(--text-color, inherit);
                        line-height: 1;
                        padding: 4px;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                    ">&times;</button>
                    
                    <h2 style="
                        margin: 0 0 8px 0;
                        font-size: 20px;
                        font-weight: 600;
                        padding-right: 32px;
                        color: var(--text-color, #000);
                    ">${title}</h2>
                    
                    <div style="
                        color: var(--text-color, #666);
                        font-size: 14px;
                        opacity: 0.7;
                    ">${dateStr}</div>
                </div>
                
                <!-- Scrollable Body -->
                <div style="
                    padding: 24px;
                    overflow-y: auto;
                    flex-grow: 1;
                ">
                    <div class="dialog-description" style="
                        margin-bottom: 24px;
                        line-height: 1.6;
                        color: var(--text-color, inherit);
                    ">
                        ${description}
                    </div>
                    
                    <button class="btn btn-primary btn-reserve" style="${btnStyle}">${reserveTitle}</button>
                </div>
            </div>
        `;

        document.body.appendChild(overlay);

        // Bind Events
        const closeBtn = overlay.querySelector('.close-btn');
        const reserveBtn = overlay.querySelector('.btn-reserve');

        const onKeyDown = (e) => {
            if (e.key === 'Escape') close();
        };
        document.addEventListener('keydown', onKeyDown);

        const close = () => {
             document.removeEventListener('keydown', onKeyDown);
             document.body.style.overflow = ''; // Restore scroll
             overlay.classList.remove('visible');
             setTimeout(() => overlay.remove(), 300);
        };

        closeBtn.onclick = close;
        
        reserveBtn.onclick = async () => {
            await OccasionDetailDialog.handleReserveAction(occasion);
            close();
        };
        
        // Close on click outside
        overlay.onclick = (e) => {
            if (e.target === overlay) close();
        };
    }

    static async handleReserveAction(occasion) {
        const href = getOccasionHref(occasion);
        if (!href) return;
        if (/^https?:\/\//i.test(href)) {
            RouterService.openExternalUrl(href);
            return;
        }
        if (href.startsWith('/form/')) {
            return RouterService.navigateToForm(decodeURIComponent(href.slice('/form/'.length)));
        }
        return RouterService.navigateToOccasionApp(occasion.link);
    }
}
