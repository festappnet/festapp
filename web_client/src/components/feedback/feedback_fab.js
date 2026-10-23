import './feedback_fab.css';
import './feedback_dialog.css';
import { FeedbackDialog } from './feedback_dialog.js';
import { LocalizationService } from '../../services/localization_service.js';
import { FeedbackStrings } from './feedback_strings.js';

export class FeedbackFab {
    static isOpen = false;
    static items = [];

    static init(containerId) {
        if (FeedbackFab.isOpen) FeedbackFab.setOpen(false);
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
                    <button type="button" class="fab-item" data-index="${index}">
                        <span class="fab-label">${item.label}</span>
                        <span class="fab-mini-btn" aria-hidden="true" style="color: ${item.color}">
                            <i class="material-icons">${item.icon}</i>
                        </span>
                    </button>
                 `).join('')}
            </div>
            <button type="button" id="fab-button" class="fab-button" aria-controls="fab-menu" aria-expanded="false">
                <i class="material-icons" id="fab-icon" aria-hidden="true">chat_bubble</i>
            </button>
        `;
        
        const button = container.querySelector('#fab-button');
        button.setAttribute('aria-label', FeedbackStrings.helpTitle);
        button.onclick = FeedbackFab.toggle;

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
        FeedbackFab.setOpen(!FeedbackFab.isOpen);
    }

    static setOpen(open, { restoreFocus = false } = {}) {
        const menu = document.getElementById('fab-menu');
        const icon = document.getElementById('fab-icon');
        const btn = document.getElementById('fab-button');
        if (!menu || !btn || !icon) return;
        FeedbackFab.isOpen = open;
        menu.classList.toggle('hidden', !open);
        icon.innerText = open ? 'close' : 'chat_bubble';
        btn.classList.toggle('open', open);
        btn.setAttribute('aria-expanded', String(open));
        btn.setAttribute('aria-label', open ? LocalizationService.tr('Feedback.close') : FeedbackStrings.helpTitle);

        if (FeedbackFab.clickOutsideListener) {
            document.removeEventListener('click', FeedbackFab.clickOutsideListener);
            FeedbackFab.clickOutsideListener = null;
        }
        if (FeedbackFab.escListener) {
            document.removeEventListener('keydown', FeedbackFab.escListener);
            FeedbackFab.escListener = null;
        }
        if (open) {
            // The opening click is inside this container, so no delayed listener is needed.
            const container = btn.parentElement;
            FeedbackFab.clickOutsideListener = event => {
                if (!container.contains(event.target)) FeedbackFab.setOpen(false);
            };
            FeedbackFab.escListener = event => {
                if (event.key === 'Escape') {
                    FeedbackFab.setOpen(false, { restoreFocus: true });
                }
            };
            document.addEventListener('click', FeedbackFab.clickOutsideListener);
            document.addEventListener('keydown', FeedbackFab.escListener);
            menu.querySelector('button')?.focus();
        } else if (restoreFocus || menu.contains(document.activeElement)) {
            btn.focus();
        }
    }
}
