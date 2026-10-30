import { formatDisplayNumber } from '../../utils/formatters.js';
import QRCode from 'qrcode';
import { PublicOrderStrings } from './public_order_strings.js';
import { orderIcon } from './order_icons.js';

// Shared by the checkout confirmation and the persistent order overview.
export function renderPaymentDetails(paymentHost, paymentQr, { occasionTitle = '', orderSymbol, expanded = false } = {}) {
    const style = document.createElement('style');
    style.textContent = `                .result-payment-details { width: 100%; margin: 0 0 20px; }
                .result-payment-card { box-sizing: border-box; border-radius: var(--radius-md, 15px); padding: 16px; background: var(--card-bg, #fff); box-shadow: 0 2px 8px rgba(0,0,0,0.05); text-align: left; }
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
                .result-copy-icon { display: block; width: 18px; height: 18px; }
                .result-copy-tooltip { position: absolute; z-index: 1; inset-inline-end: 0; bottom: calc(100% + 6px); border-radius: 4px; padding: 6px 10px; background: #333; color: #fff; font: 12px/1.4 system-ui, sans-serif; white-space: nowrap; pointer-events: none; visibility: hidden; }
                .result-copy:hover .result-copy-tooltip, .result-copy:focus-visible .result-copy-tooltip, .result-copy.is-copied .result-copy-tooltip { visibility: visible; }
                .result-copy:focus-visible, .result-download:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 2px; }
                .result-download { display: inline-block; border: 1px solid var(--primary-color); border-radius: var(--radius-sm, 10px); padding: 10px 16px; color: var(--primary-color); text-decoration: none; font-weight: 600; }
                @media (max-width: 560px) {
                    .result-payment-card { padding: 16px; }
                    .result-payment-row { flex-wrap: wrap; }
                }
`;
    paymentHost.appendChild(style);
            // Keep the confirmation outside the card; one disclosure reveals every payment option.
            paymentHost.classList.add('result-payment-card', 'result-payment-details');
            const payload = typeof paymentQr.payload === 'string' ? paymentQr.payload : '';
            const currency = String(paymentQr.currency_code || '');
            const amount = Number(paymentQr.amount);
            const displayedAmount = Number.isFinite(amount)
                ? formatDisplayNumber(amount, document.documentElement.lang || 'cs', {
                    minimumFractionDigits: currency === 'CZK' ? 0 : 2,
                    maximumFractionDigits: 2,
                })
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
            more.open = expanded;
            const summary = document.createElement('summary');
            summary.textContent = expanded ? PublicOrderStrings.hidePaymentOptions : PublicOrderStrings.showPaymentOptions;
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
                    const eventName = filenamePart(occasionTitle);
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
                const copyIcon = document.createElement('span');
                copyIcon.className = 'result-copy-icon';
                copyIcon.setAttribute('aria-hidden', 'true');
                copyIcon.innerHTML = orderIcon('copy');
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
                        copyIcon.innerHTML = orderIcon('check');
                        tooltip.textContent = PublicOrderStrings.copied;
                        copy.classList.add('is-copied');
                        copy.setAttribute('aria-label', `${PublicOrderStrings.copied}: ${label}`);
                        resetTimer = setTimeout(() => {
                            copyIcon.innerHTML = orderIcon('copy');
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
