import { FormStrings } from './form_strings.js';
import { overviewText } from './order_overview.js';
import { WaitlistStrings } from './waitlist_strings.js';
import { observeOrderDelivery } from './order_delivery_status.js';
import { OrdersStrings } from '../eshop/orders_strings.js';
import { PublicOrderStrings } from './public_order_strings.js';
import { renderPaymentDetails } from './payment_details.js';

export class OrderResult {
    static render(container, success, resultData, formModel, onClose) {
        container._orderDeliveryObserver?.stop();
        if (formModel.demoSimulation) resultData = {};
        // Prepare Data
        const isWaitlist = formModel.registrationMode === 'waitlist';
        const tone = formModel.communicationTone; 
        // We need to know if tickets were involved. 
        // FormModel knows fields. If ticket field exists -> hasTickets = true.
        const hasTickets = formModel.visibleFields.some(f => f.type === 'ticket');
        
        let title, subtitle;
        let icon = 'check_circle';
        let colorClass = 'success-color'; 

        if (success && formModel.demoSimulation) {
            title = FormStrings.demoComplete;
            subtitle = FormStrings.demoResult;
        } else if (success) {
            title = isWaitlist ? WaitlistStrings.text('registered', tone) : PublicOrderStrings.successTitle(tone, hasTickets);
            const email = resultData?.ticketOrder?.order?.data?.email;
            subtitle = isWaitlist ? `${WaitlistStrings.text('waitingStatus', tone)} ${WaitlistStrings.text('resultNextStep', tone)}` : PublicOrderStrings.confirmationInfo(tone, Boolean(resultData?.payment_qr), typeof email === 'string' ? email.trim() : '');
        } else if (resultData && resultData.code === 1017) { // Product Unavailable
            const prodTitle = (resultData.product && resultData.product.title) || "";
            title = PublicOrderStrings.productUnavailable(prodTitle);
            subtitle = PublicOrderStrings.chooseDifferentVariant(tone);
            icon = 'error';
            colorClass = 'error-color';
        } else {
            // Generic Error
            const code = (resultData && resultData.code) || 0;
            title = PublicOrderStrings.orderFailed;
            subtitle = resultData?.errorCode ? WaitlistStrings.text(resultData.errorCode, tone) : PublicOrderStrings.orderError(code);
            icon = 'error';
            colorClass = 'error-color';
        }

        if (success && isWaitlist && ['declined', 'withdrawn', 'cancelled', 'expired', 'accepted'].includes(resultData?.waitlistOutcome)) {
            title = WaitlistStrings.text(`${resultData.waitlistOutcome}Title`, tone);
            subtitle = WaitlistStrings.text(`${resultData.waitlistOutcome}Explanation`, tone);
            if (resultData.waitlistOutcome === 'expired' || resultData.waitlistOutcome === 'cancelled') icon = 'info';
        }

        // Render HTML
        container.innerHTML = `
            <div class="result-container">
                <div class="result-icon-wrapper ${colorClass}">
                    <i class="material-icons result-icon">${icon}</i>
                </div>
                <p class="result-occasion-title"></p>
                <h2 class="result-title ${colorClass}"></h2>
                <p class="result-subtitle"></p>
                <p class="result-order-symbol"></p>
                <div class="result-payment-details"></div>
                
                <div class="result-actions">
                    <button class="btn btn-outline-secondary btn-back-to-form">
                        ${success && resultData?.overviewAvailable ? overviewText('title') : PublicOrderStrings.backToForm}
                    </button>
                </div>
            </div>
            <style>
                .result-container {
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    padding: 20px 16px;
                    text-align: center;
                    animation: fadeIn 0.5s ease-out;
                    width: 100%;
                    max-width: 600px;
                    margin: 0 auto; /* Center in parent if block */
                    box-sizing: border-box;
                    font-family: var(--font-family-base, inherit);
                }
                .result-icon-wrapper {
                    width: 52px;
                    height: 52px;
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    margin-bottom: 12px;
                    animation: scaleIn 0.5s cubic-bezier(0.175, 0.885, 0.32, 1.275);
                }
                .success-color {
                    color: var(--dark-green, #2e7d32); /* ThemeConfig.darkGreen */
                }
                .result-icon-wrapper.success-color {
                    background-color: var(--dark-green, #2e7d32);
                    color: white;
                }
                .error-color {
                    color: var(--red-color, #d32f2f);
                }
                .result-icon-wrapper.error-color {
                    background-color: var(--red-color, #d32f2f);
                    color: white;
                }
                .result-icon {
                    font-size: 30px;
                }
                .result-title {
                    font-size: 1.4rem;
                    font-weight: bold;
                    margin-bottom: 20px;
                }
                .result-subtitle {
                    font-size: 1rem;
                    color: var(--text-color);
                    margin-bottom: 18px;
                    max-width: 400px;
                    line-height: 1.5;
                    overflow-wrap: anywhere;
                }
                .result-actions button {
                    /* Match Flutter OutlinedButton style roughly */
                    border: 1px solid var(--divider-color, #ccc);
                    background: transparent;
                    color: var(--primary-color);
                    padding: 12px 32px;
                    border-radius: 8px;
                    font-weight: bold;
                    text-transform: uppercase;
                    cursor: pointer;
                    transition: all 0.2s;
                }
                .result-actions button:hover {
                    background-color: rgba(0,0,0,0.05);
                }
                
                @keyframes scaleIn {
                    from { transform: scale(0); opacity: 0; }
                    to { transform: scale(1); opacity: 1; }
                }
            </style>
        `;

        container.querySelector('.result-occasion-title').textContent = formModel.occasionTitle || '';
        container.querySelector('.result-title').textContent = title;
        container.querySelector('.result-subtitle').textContent = subtitle + (success && resultData?.conversion === 'split' ? ` ${WaitlistStrings.remaining}: ${resultData.waitlistSummary?.pendingPlaces ?? 0}.` : '');
        const orderSymbol = success ? resultData?.ticketOrder?.order?.order_symbol : null;
        if (typeof orderSymbol === 'string') {
            container.querySelector('.result-order-symbol').textContent = `${isWaitlist ? WaitlistStrings.text('registrationSymbol') : OrdersStrings.gridOrderSymbol}: ${orderSymbol}`;
        }

        const paymentQr = success && !isWaitlist ? resultData?.payment_qr : null;
        const paymentHost = container.querySelector('.result-payment-details');
        if (paymentHost && paymentQr) {
            renderPaymentDetails(paymentHost, paymentQr, { occasionTitle: formModel.occasionId?.title || formModel.title, orderSymbol });
        }

        if (success && !isWaitlist && resultData?.delivery_receipt) {
            container._orderDeliveryObserver = observeOrderDelivery(resultData.delivery_receipt, state => {
                if (!container.isConnected) { container._orderDeliveryObserver?.stop(); return; }
                const email = resultData?.ticketOrder?.order?.data?.email;
                container.querySelector('.result-subtitle').textContent = PublicOrderStrings.confirmationInfo(tone, Boolean(resultData?.payment_qr), typeof email === 'string' ? email.trim() : '', state);
            }, {alive: () => container.isConnected});
        }

        // Attach Event
        const backBtn = container.querySelector('.btn-back-to-form');
        if (backBtn) {
            backBtn.onclick = () => {
                container._orderDeliveryObserver?.stop();
                if (onClose) onClose();
            };
        }
    }
}
