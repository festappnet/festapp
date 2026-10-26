import { LocalizationService } from '../../services/localization_service.js';
import { RouterService } from '../../services/router_service.js';

export class FeedbackDialog {
    static init() {
        if (document.getElementById('feedback-dialog-root')) return;

        const root = document.createElement('div');
        root.id = 'feedback-dialog-root';
        root.className = 'feedback-dialog-overlay';
        root.setAttribute('role', 'dialog');
        root.setAttribute('aria-labelledby', 'fd-title');
        root.innerHTML = `
            <div class="feedback-dialog">
                <div class="fd-header">
                    <h2 id="fd-title" class="feedback-dialog-title"></h2>
                    <button class="icon-btn" id="fd-close-btn"><i class="material-icons">close</i></button>
                </div>
                
                <div class="fd-content">
                    <button id="fd-open-mail" class="feedback-btn primary-btn">
                        <i class="material-icons">email</i>
                        <span id="fd-open-mail-text"></span>
                    </button>

                    <div class="fd-divider">
                        <span class="line"></span>
                        <span id="fd-manual-text" class="text"></span>
                        <span class="line"></span>
                    </div>

                    <div class="copy-row">
                        <label id="fd-label-to"></label>
                        <div class="copy-input-group">
                            <span id="fd-value-to"></span>
                            <button class="icon-btn copy-btn" data-target="fd-value-to"><i class="material-icons">content_copy</i></button>
                        </div>
                    </div>

                    <div class="copy-row">
                        <label id="fd-label-subject"></label>
                        <div class="copy-input-group">
                            <span id="fd-value-subject"></span>
                            <button class="icon-btn copy-btn" data-target="fd-value-subject"><i class="material-icons">content_copy</i></button>
                        </div>
                    </div>

                    <div class="copy-row">
                        <label id="fd-label-body"></label>
                        <div class="copy-input-group">
                            <span id="fd-value-body" class="multiline"></span>
                            <button class="icon-btn copy-btn" data-target="fd-value-body"><i class="material-icons">content_copy</i></button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        document.body.appendChild(root);

        // Bind events
        document.getElementById('fd-close-btn').onclick = FeedbackDialog.close;
        root.onclick = (e) => {
            if (e.target === root) FeedbackDialog.close();
        };

        // Copy functionality
        root.querySelectorAll('.copy-btn').forEach(btn => {
            btn.onclick = () => {
                const targetId = btn.getAttribute('data-target');
                const text = document.getElementById(targetId).innerText;
                navigator.clipboard.writeText(text).then(() => {
                    const originalIcon = btn.innerHTML;
                    btn.innerHTML = '<i class="material-icons">check</i>';
                    setTimeout(() => btn.innerHTML = originalIcon, 2000);
                });
            };
        });
    }

    static escListener = null;

    static show(subject, hint) {
        FeedbackDialog.init();
        FeedbackDialog.returnFocus = document.activeElement;
        const tr = LocalizationService.tr;
        const appName = "Festapp";

        // Fill static texts
        document.getElementById('fd-title').innerText = tr('Feedback.helpTitle');
        document.getElementById('fd-open-mail-text').innerText = tr('Feedback.openEmailApp');
        document.getElementById('fd-manual-text').innerText = tr('Feedback.manualInstructions');
        
        document.getElementById('fd-label-to').innerText = tr('Feedback.emailTo');
        document.getElementById('fd-label-subject').innerText = tr('Feedback.emailSubject');
        document.getElementById('fd-label-body').innerText = tr('Feedback.emailBody');

        // Fill dynamic values
        const toEmail = 'info@festapp.net';
        const fullBody = `${hint}\n\n\n---\n${tr('Feedback.sentFrom', {appName})}`;

        document.getElementById('fd-value-to').innerText = toEmail;
        document.getElementById('fd-value-subject').innerText = subject;
        document.getElementById('fd-value-body').innerText = fullBody;

        // Open Mail Button Action
        document.getElementById('fd-open-mail').onclick = () => {
            const mailto = `mailto:${toEmail}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(fullBody)}`;
            RouterService.openExternalUrl(mailto, { inCurrentWindow: true });
        };

        const root = document.getElementById('feedback-dialog-root');
        root.classList.add('open');
        const close = document.getElementById('fd-close-btn');
        close.type = 'button';
        close.setAttribute('aria-label', tr('Feedback.close'));
        close.querySelector('i').setAttribute('aria-hidden', 'true');
        root.querySelectorAll('.copy-btn').forEach(button => {
            button.type = 'button';
            button.setAttribute('aria-label', tr('Feedback.copyToClipboard'));
        });
        close.focus();

        // Close on Esc key
        FeedbackDialog.escListener = (e) => {
            if (e.key === 'Escape') {
                FeedbackDialog.close();
            }
        };
        document.addEventListener('keydown', FeedbackDialog.escListener);
    }

    static close() {
        const root = document.getElementById('feedback-dialog-root');
        if (root) root.classList.remove('open');
        if (FeedbackDialog.returnFocus?.isConnected) FeedbackDialog.returnFocus.focus();
        FeedbackDialog.returnFocus = null;
        
        if (FeedbackDialog.escListener) {
            document.removeEventListener('keydown', FeedbackDialog.escListener);
            FeedbackDialog.escListener = null;
        }
    }
}
