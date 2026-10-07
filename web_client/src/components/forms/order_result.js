import { observeOrderDelivery } from './order_delivery_status.js';
import { OrdersStrings } from '../eshop/orders_strings.js';
import { PublicOrderStrings } from './public_order_strings.js';
import QRCode from 'qrcode';

export class OrderResult {
    static render(container, success, resultData, formModel, onClose) {
        container._orderDeliveryObserver?.stop();
        // Prepare Data
        const tone = formModel.communicationTone; 
        // We need to know if tickets were involved. 
        // FormModel knows fields. If ticket field exists -> hasTickets = true.
        const hasTickets = formModel.visibleFields.some(f => f.type === 'ticket');
        
        let title, subtitle;
        let icon = 'check_circle';
        let colorClass = 'success-color'; 

        if (success) {
            title = PublicOrderStrings.successTitle(tone, hasTickets);
            const email = resultData?.ticketOrder?.order?.data?.email;
            subtitle = PublicOrderStrings.confirmationInfo(tone, Boolean(resultData?.payment_qr), typeof email === 'string' ? email.trim() : '');
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
            subtitle = PublicOrderStrings.orderError(code);
            icon = 'error';
            colorClass = 'error-color';
        }

        // Render HTML
        container.innerHTML = `
            <div class="result-container">
                <div class="result-icon-wrapper ${colorClass}">
                    <i class="material-icons result-icon">${icon}</i>
                </div>
                <h2 class="result-title ${colorClass}"></h2>
                <p class="result-subtitle"></p>
                <p class="result-order-symbol"></p>
                <div class="result-payment-details"></div>
                
                <div class="result-actions">
                    <button class="btn btn-outline-secondary btn-back-to-form">
                        ${PublicOrderStrings.backToForm}
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
                .result-payment-details { width: 100%; margin: 0 0 20px; }
                .result-payment-card { border-radius: var(--radius-md, 15px); padding: 16px; background: var(--card-bg, #fff); box-shadow: 0 2px 8px rgba(0,0,0,0.05); text-align: left; }
                .result-payment-label { display: block; color: var(--text-color); opacity: .72; font-size: .8rem; letter-spacing: .05em; text-transform: uppercase; }
                .result-payment-total { display: block; margin: 3px 0 6px; font-size: 2rem; line-height: 1.1; }
                .result-payment-more { margin-top: 16px; border-top: 1px solid var(--input-border, #ddd); text-align: left; }
                .result-payment-more summary { cursor: pointer; color: var(--primary-color); font-size: 1.1rem; font-weight: 600; padding: 14px 0; min-height: 44px; }
                .result-payment-more summary:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 2px; }
                .result-payment-qr-area { text-align: center; padding: 8px 0 18px; }
                .result-payment-qr-title { margin: 0 0 6px; font-size: 1.05rem; }
                .result-payment-hint { margin: 0 0 12px; color: var(--text-color); line-height: 1.4; }
                .result-payment-qr { display: block; width: 220px; height: 220px; margin: 0 auto 14px; background: white; image-rendering: pixelated; }
                .result-payment-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 8px 0; border-top: 1px solid var(--input-border, #ddd); text-align: left; }
                .result-payment-value { font-weight: 600; text-align: right; overflow-wrap: anywhere; }
                .result-copy { position: relative; display: inline-flex; align-items: center; justify-content: center; flex: 0 0 40px; width: 40px; height: 40px; box-sizing: border-box; border: 0; border-radius: 50%; background: transparent; color: var(--primary-color); cursor: pointer; padding: 0; }
                .result-copy:hover { background: color-mix(in srgb, var(--primary-color) 10%, transparent); }
                .result-copy .material-icons { display: block; width: 18px; height: 18px; font-size: 18px; line-height: 18px; }
                .result-copy-tooltip { position: absolute; z-index: 1; inset-inline-end: 0; bottom: calc(100% + 6px); border-radius: 4px; padding: 6px 10px; background: #333; color: #fff; font: 12px/1.4 system-ui, sans-serif; white-space: nowrap; pointer-events: none; visibility: hidden; }
                .result-copy:hover .result-copy-tooltip, .result-copy:focus-visible .result-copy-tooltip, .result-copy.is-copied .result-copy-tooltip { visibility: visible; }
                .result-copy:focus-visible, .result-download:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 2px; }
                .result-download { display: inline-block; border: 1px solid var(--primary-color); border-radius: var(--radius-sm, 10px); padding: 10px 16px; color: var(--primary-color); text-decoration: none; font-weight: 600; }
                @media (max-width: 560px) {
                    .result-payment-card { padding: 16px; }
                    .result-payment-row { flex-wrap: wrap; }
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

        container.querySelector('.result-title').textContent = title;
        container.querySelector('.result-subtitle').textContent = subtitle;
        const orderSymbol = success ? resultData?.ticketOrder?.order?.order_symbol : null;
        if (typeof orderSymbol === 'string') {
            container.querySelector('.result-order-symbol').textContent = `${OrdersStrings.gridOrderSymbol}: ${orderSymbol}`;
        }

        const paymentQr = success ? resultData?.payment_qr : null;
        const paymentHost = container.querySelector('.result-payment-details');
        if (paymentHost && paymentQr) {
            // Keep the confirmation outside the card; one disclosure reveals every payment option.
            paymentHost.classList.add('result-payment-card');
            const payload = typeof paymentQr.payload === 'string' ? paymentQr.payload : '';
            const currency = String(paymentQr.currency_code || '');
            const amount = Number(paymentQr.amount);
            const displayedAmount = Number.isFinite(amount)
                ? new Intl.NumberFormat(document.documentElement.lang || 'cs', {
                    minimumFractionDigits: currency === 'CZK' ? 0 : 2,
                    maximumFractionDigits: 2,
                }).format(amount)
                : String(paymentQr.amount);
            const paymentAmount = `${displayedAmount} ${currency}`.trim();
            const label = document.createElement('span');
            label.className = 'result-payment-label';
            label.textContent = PublicOrderStrings.amountToPay;
            const total = document.createElement('strong');
            total.className = 'result-payment-total';
            total.textContent = paymentAmount;
            paymentHost.append(label, total);
            const more = document.createElement('details');
            more.className = 'result-payment-more';
            const summary = document.createElement('summary');
            summary.textContent = PublicOrderStrings.showPaymentOptions;
            more.appendChild(summary);
            more.addEventListener('toggle', () => {
                summary.textContent = more.open ? PublicOrderStrings.hidePaymentOptions : PublicOrderStrings.showPaymentOptions;
            });
            if (payload) {
                const qrArea = document.createElement('div');
                qrArea.className = 'result-payment-qr-area';
                const heading = document.createElement('h3');
                heading.className = 'result-payment-qr-title';
                heading.textContent = PublicOrderStrings.paymentQrTitle;
                const hint = document.createElement('p');
                hint.className = 'result-payment-hint';
                hint.textContent = PublicOrderStrings.paymentQrSubtitle;
                qrArea.append(heading, hint);
                more.appendChild(qrArea);
                QRCode.toDataURL(payload, { errorCorrectionLevel: 'M', margin: 3, width: 512 }).then(url => {
                    const qr = document.createElement('img');
                    qr.className = 'result-payment-qr';
                    qr.src = url;
                    qr.alt = PublicOrderStrings.paymentQrTitle;
                    hint.after(qr);
                    const download = document.createElement('a');
                    download.className = 'result-download';
                    download.href = url;
                    const filenamePart = value => String(value ?? '')
                        .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
                        .toLowerCase().replace(/[^a-z0-9]+/g, '-')
                        .replace(/^-+|-+$/g, '');
                    const eventName = filenamePart(formModel.occasionId?.title || formModel.title);
                    const symbol = filenamePart(orderSymbol || paymentQr.reference);
                    download.download = [eventName, 'objednavka', symbol, 'qr'].filter(Boolean).join('-') + '.png';
                    download.textContent = PublicOrderStrings.downloadQr;
                    qrArea.appendChild(download);
                }).catch(error => {
                    console.error('Could not render payment QR', error);
                    qrArea.remove();
                    more.open = true;
                });
            }
            const rows = [
                [PublicOrderStrings.bankAccount, paymentQr.account_number_human_readable || paymentQr.account_number],
                ...(paymentQr.account_number_human_readable && paymentQr.account_number && paymentQr.account_number_human_readable !== paymentQr.account_number
                    ? [[PublicOrderStrings.iban, paymentQr.account_number]] : []),
                [paymentQr.reference_kind === 'RF' ? PublicOrderStrings.paymentReference : PublicOrderStrings.variableSymbol, paymentQr.reference],
                [PublicOrderStrings.amountToPay, paymentAmount],
            ];
            for (const [label, value] of rows) {
                if (value == null || String(value).trim() === '') continue;
                const row = document.createElement('div');
                row.className = 'result-payment-row';
                const labelNode = document.createElement('span');
                const valueNode = document.createElement('span');
                valueNode.className = 'result-payment-value';
                labelNode.textContent = label;
                valueNode.textContent = String(value);
                const copy = document.createElement('button');
                copy.type = 'button';
                copy.className = 'result-copy';
                const copyIcon = document.createElement('i');
                copyIcon.className = 'material-icons';
                copyIcon.setAttribute('aria-hidden', 'true');
                copyIcon.textContent = 'content_copy';
                const tooltip = document.createElement('span');
                tooltip.className = 'result-copy-tooltip';
                tooltip.setAttribute('aria-hidden', 'true');
                tooltip.textContent = PublicOrderStrings.copy;
                copy.append(copyIcon, tooltip);
                const copyLabel = `${PublicOrderStrings.copy}: ${label}`;
                copy.setAttribute('aria-label', copyLabel);
                let resetTimer;
                copy.addEventListener('click', async () => {
                    try {
                        await navigator.clipboard.writeText(String(value));
                        clearTimeout(resetTimer);
                        copyIcon.textContent = 'check';
                        tooltip.textContent = PublicOrderStrings.copied;
                        copy.classList.add('is-copied');
                        copy.setAttribute('aria-label', `${PublicOrderStrings.copied}: ${label}`);
                        resetTimer = setTimeout(() => {
                            copyIcon.textContent = 'content_copy';
                            tooltip.textContent = PublicOrderStrings.copy;
                            copy.classList.remove('is-copied');
                            copy.setAttribute('aria-label', copyLabel);
                        }, 2000);
                    } catch (error) {
                        console.error('Could not copy payment detail', error);
                    }
                });
                row.append(labelNode, valueNode, copy);
                more.appendChild(row);
            }
            paymentHost.appendChild(more);
        }

        if (success && resultData?.delivery_receipt) {
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
