import './feedback_fab.css';
import './feedback_dialog.css';
import { FeedbackDialog } from './feedback_dialog.js';
import { LocalizationService } from '../../services/localization_service.js';
import { FeedbackStrings } from './feedback_strings.js';

export class FeedbackFab {
    static isOpen = false;
    static items = [];

    static init(containerId) {
        const appName = "Festapp";

        FeedbackFab.items = [
            { 
                label: FeedbackStrings.requestFeature, 
                icon: 'lightbulb_outline', 
                color: '#fbc02d', 
                subject: LocalizationService.tr('Feedback.subjectFeature', {appName}),
                hint: FeedbackStrings.hintFeature
            },
            { 
                label: FeedbackStrings.reportBug, 
                icon: 'bug_report', 
                color: '#ef5350', 
                subject: LocalizationService.tr('Feedback.subjectBug', {appName}),
                hint: FeedbackStrings.hintBug
            },
            { 
                label: FeedbackStrings.support, 
                icon: 'help_outline', 
                color: '#42a5f5', 
                subject: LocalizationService.tr('Feedback.subjectSupport', {appName}),
                hint: FeedbackStrings.hintSupport
            },
            { 
                label: FeedbackStrings.other, 
                icon: 'chat_bubble_outline', 
                color: '#757575', 
                subject: LocalizationService.tr('Feedback.subjectGeneral', {appName}),
                hint: FeedbackStrings.hintGeneral
            }
        ];

        const container = document.getElementById(containerId);
        if (!container) return;
        
        // Render Full Structure
        container.innerHTML = `
            <div id="fab-menu" class="fab-menu hidden">
                 <div class="fab-help-title">${FeedbackStrings.helpTitle}</div>
                 ${FeedbackFab.items.map((item, index) => `
                    <div class="fab-item" data-index="${index}">
                        <span class="fab-label">${item.label}</span>
                        <div class="fab-mini-btn" style="color: ${item.color}">
                            <i class="material-icons">${item.icon}</i>
                        </div>
                    </div>
                 `).join('')}
            </div>
            <div id="fab-button" class="fab-button">
                <i class="material-icons" id="fab-icon">chat_bubble</i>
            </div>
        `;
        
        document.getElementById('fab-button').onclick = FeedbackFab.toggle;

        // Bind Menu Item Clicks
        container.querySelectorAll('.fab-item').forEach(el => {
            el.onclick = () => {
                const index = el.getAttribute('data-index');
                const item = FeedbackFab.items[index];
                if (item) {
                    FeedbackFab.toggle(); // Close menu
                    FeedbackDialog.show(item.subject, item.hint);
                }
            };
        });
    }

    static clickOutsideListener = null;
    static escListener = null;

    static toggle() {
        FeedbackFab.isOpen = !FeedbackFab.isOpen;
        const menu = document.getElementById('fab-menu');
        const icon = document.getElementById('fab-icon');
        const btn = document.getElementById('fab-button');
        const container = document.getElementById('feedback-fab'); // We need the container for outside click check

        if (FeedbackFab.isOpen) {
            menu.classList.remove('hidden');
            icon.innerText = 'close';
            btn.classList.add('open');
            
            // Close on outside click
            setTimeout(() => {
                FeedbackFab.clickOutsideListener = (e) => {
                    // Check if click is outside the FAB container (menu + button)
                    if (container && !container.contains(e.target)) {
                         FeedbackFab.toggle();
                    }
                };
                document.addEventListener('click', FeedbackFab.clickOutsideListener);
            }, 0);

            // Close on Esc key
            FeedbackFab.escListener = (e) => {
                if (e.key === 'Escape') {
                    FeedbackFab.toggle();
                }
            };
            document.addEventListener('keydown', FeedbackFab.escListener);

        } else {
            menu.classList.add('hidden');
            icon.innerText = 'chat_bubble';
            btn.classList.remove('open');
            
            if (FeedbackFab.clickOutsideListener) {
                document.removeEventListener('click', FeedbackFab.clickOutsideListener);
                FeedbackFab.clickOutsideListener = null; // Ensure listener is cleared
            }
            if (FeedbackFab.escListener) {
                document.removeEventListener('keydown', FeedbackFab.escListener);
                FeedbackFab.escListener = null;
            }
        }
    }

}
