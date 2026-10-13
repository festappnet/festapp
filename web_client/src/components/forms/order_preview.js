import { formFieldTitle } from './form_field_labels.js';
import { html as htmlText } from '../../utils/html.js';
import { WaitlistStrings } from './waitlist_strings.js';
import { CommonStrings } from '../shared/common_strings.js';
import { formatPrice } from '../../utils/formatters.js';
import { FormStrings } from './form_strings.js';
import { OrdersStrings } from '../eshop/orders_strings.js'; 

import { RouterService } from '../../services/router_service.js';
import { PublicOrderStrings } from './public_order_strings.js';
import { OrderResult } from './order_result.js';
import { FeatureService } from '../features/feature_service.js';
import { FormDataReader } from './form_data_reader.js';
import { FieldPreviewFactory } from './previews/field_preview_factory.js';
import { FormHelper } from './form_helper.js';
import { LocalizationService } from '../../services/localization_service.js';

// Inject CSS
if (typeof document !== 'undefined') {
    const cssUrl = new URL('./order_preview.css', import.meta.url).href;
    if (!document.querySelector(`link[href="${cssUrl}"]`)) {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = cssUrl;
        document.head.appendChild(link);
    }
}

export class OrderPreview {

    static show(form, formModel, priceData, onConfirm, onClose, precalculatedPayload = null, presentation = {}) {
        // 1. Calculate and Prepare Data
        const data = { ...OrderPreview._prepareData(form, formModel, priceData, precalculatedPayload), presentation };
        
        // 2. Render Overlay
        let overlay = document.getElementById('order-preview-overlay');
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'order-preview-overlay';
            overlay.className = 'order-preview-overlay';
            document.body.appendChild(overlay);
        }

        overlay.innerHTML = OrderPreview._render(data);

        // 3. Close Logic (with Animation)
        let isClosing = false;
        const closePreview = () => {
            if (isClosing) return;
            isClosing = true;
            
            // If closed by drag, we handled animation manually. Don't add .closing class (which forces slideDown from 0).
            if (overlay.dataset.closedByDrag !== 'true') {
                overlay.classList.add('closing');
            } else {
                // We closed by drag. The content is already translated down.
                // We just want to fade out the background.
                // We can add a specialized class or just rely on the fact that overlay supports fadeOut.
                // If we add .closing, it triggers fadeOut on overlay, AND slideDown on content.
                // We want to suppress slideDown on content.
                const content = overlay.querySelector('.order-preview-content');
                if (content) {
                     // Force animation to none so CSS keyframes don't override our manual transform
                     content.style.animation = 'none';
                }
                overlay.classList.add('closing');
            }
            
            // Remove listeners
            document.removeEventListener('keydown', escHandler);
            overlay.removeEventListener('click', backdropHandler);
            
            // Wait for animation
            setTimeout(() => {
                overlay.style.display = 'none';
                overlay.classList.remove('visible', 'closing');
                delete overlay.dataset.closedByDrag; 
                overlay.innerHTML = ''; // Cleanup
                document.body.style.overflow = ''; // Restore Scroll
                if (onClose) onClose();
            }, 250); 
        };

        const closeBtn = overlay.querySelector('.btn-close-preview');
        // Close via Button -> Navigate Back (which triggers popstate -> close) OR Close directly?
        // Flutter logic: Navigator.pop().
        // SPA logic: history.back().
        
        // We pushed state. So to close, we should go back.
        // The popstate listener will then trigger the actual close visuals?
        // OR we close visual + go back.
        
        // Let's rely on history.back() for all "close" actions to ensure state consistency.
        const triggerBack = () => {
            RouterService.goBackProgrammatically();
        };

        if (closeBtn) closeBtn.onclick = triggerBack;

        // 4. Listeners
        
        // ESC Key
        const escHandler = (e) => {
            if (e.key === 'Escape') triggerBack();
        };
        document.addEventListener('keydown', escHandler);

        // Backdrop Click
        const backdropHandler = (e) => {
            if (e.target === overlay) triggerBack();
        };
        overlay.addEventListener('click', backdropHandler);
        
        // Submit
        const submitBtn = overlay.querySelector('.btn-submit-order');
        if (submitBtn) {
            submitBtn.onclick = () => {
                 // Capture payment_type from deposit radio if present
                 const selectedRadio = overlay.querySelector('input[name="payment_type"]:checked');
                 const paymentType = selectedRadio ? selectedRadio.value : null;
                 if (onConfirm) onConfirm(overlay, paymentType);
            };
        }

        // Show
        overlay.classList.remove('closing');
        overlay.style.display = 'flex';
        overlay.offsetHeight; // Force reflow
        overlay.classList.add('visible');
        
        const content = overlay.querySelector('.order-preview-content');
        const body = overlay.querySelector('.order-preview-body');
        
        let startY = 0;
        let currentY = 0;
        let isDragging = false;
        let ignoreGesture = false;
        
        const touchStart = (e) => {
            // Check if touch target is header or handle
            const isHeader = e.target.closest('.order-preview-header') || e.target.closest('.order-preview-handle-bar');
            
            if (!isHeader) {
                ignoreGesture = true;
                return;
            }
            
            ignoreGesture = false;
            startY = e.touches[0].clientY;
            isDragging = false;
            content.style.transition = 'none'; // Disable transition during drag
        };
        
        const touchMove = (e) => {
            if (ignoreGesture) return;
            
            currentY = e.touches[0].clientY;
            const deltaY = currentY - startY;
            
            if (deltaY > 0) {
                 if (e.cancelable) e.preventDefault();
                 
                 isDragging = true;
                 
                 // Native feel: 1:1 tracking
                 content.style.transform = `translateY(${deltaY}px)`;
                 
                 // Dynamic Backdrop Fade
                 const height = content.clientHeight || 500;
                 const progress = Math.min(deltaY / height, 1);
                 const opacity = 0.5 * (1 - progress);
                 overlay.style.backgroundColor = `rgba(0, 0, 0, ${opacity})`;
            }
        };
        
        const touchEnd = (e) => {
            if (ignoreGesture) return;
            if (!isDragging) return;
            
            const deltaY = currentY - startY;
            
            const threshold = 150; // Pixels to close
            
            if (deltaY > threshold) {
                // Trigger Close
                content.style.transition = 'transform 0.2s ease-out';
                content.style.transform = 'translateY(100%)';
                overlay.dataset.closedByDrag = 'true';
                triggerBack();
            } else {
                // Snap back
                content.style.transition = 'transform 0.25s cubic-bezier(0.25, 0.8, 0.25, 1.0)';
                content.style.transform = '';
                overlay.style.backgroundColor = ''; // Restore opacity
                
                // Cleanup transition after snap so future drags (touchstart) can set transition: none
                setTimeout(() => {
                   if (!isDragging && content) content.style.transition = '';
                }, 250);
            }
            isDragging = false;
        };
        
        // Apply listeners to the content wrapper (header + body)
        // We might want to be careful not to block scroll on body if we are not at top.
        // Actually best to attach to content, but check scrollTop in Move.
        if (content) {
            content.addEventListener('touchstart', touchStart, { passive: false });
            content.addEventListener('touchmove', touchMove, { passive: false });
            content.addEventListener('touchend', touchEnd);
        }

        // Auto-Scroll to Bottom (User Request)
        // Ensure the body (scrollable area) is scrolled to show tickets/total/submit
        // "scrolling can be bit slower" -> Custom JS animation required as 'smooth' is browser-fixed.
        setTimeout(() => {
             if (body) {
                 OrderPreview._animateScrollToBottom(body, 700); // 700ms duration (User Request)
             }
        }, 150); 
        
        // Disable Body Scroll
        document.body.style.overflow = 'hidden';
        
        RouterService.pushOverlayState('order-preview');

        // Handle Back Button (PopState)
        // We need a way to detect THIS specific popstate. 
        // RouterService.onPopState is generic. 
        // Let's add a temporary listener for this view.
        const popHandler = () => {
             closePreview();
             window.removeEventListener('popstate', popHandler);
        };
        window.addEventListener('popstate', popHandler, { once: true });
    }

    static _animateScrollToBottom(element, duration) {
        const start = element.scrollTop;
        const to = element.scrollHeight - element.clientHeight;
        
        // If already at bottom, do nothing
        if (start >= to) return;

        const change = to - start;
        const startDate = +new Date();
        
        // Quadratic easing in/out
        const easeInOutQuad = (t, b, c, d) => {
            t /= d / 2;
            if (t < 1) return c / 2 * t * t + b;
            t--;
            return -c / 2 * (t * (t - 2) - 1) + b;
        };
        
        const animateScroll = () => {
            const currentDate = +new Date();
            const currentTime = currentDate - startDate;
            
            element.scrollTop = parseInt(easeInOutQuad(currentTime, start, change, duration));
            
            if (currentTime < duration) {
                requestAnimationFrame(animateScroll);
            } else {
                element.scrollTop = to; // Ensure finish
            }
        };
        animateScroll();
    }

    static _prepareData(form, formModel, priceData, precalculatedPayload) {
        // Use passed payload (from Session) or generalized helper (Scraper)
        const payload = precalculatedPayload || FormDataReader.getPayload(form, formModel);
        
        // We use passed pricing data to display logic properly
        const totalPriceData = priceData;

        const personalInfo = [];

        // 1. Process Payload Fields (for Personal Info)
        // Ensure deterministic order by iterating formModel.visibleFields
        const payloadFieldsMap = new Map();
        if (payload.fields) {
            payload.fields.forEach(fObj => {
                Object.keys(fObj).forEach(k => payloadFieldsMap.set(k, fObj[k]));
            });
        }

        if (formModel.visibleFields) {
            formModel.visibleFields.forEach(field => {
                 // Skip ticket fields
                 if (field.type === 'ticket') return;
                 
                 if (payloadFieldsMap.has(String(field.id))) {
                     const val = payloadFieldsMap.get(String(field.id));
                     if (field.id === 'currency_code') return; 

                     const result = FieldPreviewFactory.format(field, val, { 
                          currency: totalPriceData.currency 
                     });
                     // result is now { value, price }
                     personalInfo.push({ label: formFieldTitle(field), value: result.value, price: result.price });
                 }
            });
        }


        // 2. Process Payload Tickets
        // We need to reconstruct the "ticket rows" structure expected by _render
        const tickets = [];
        const payloadTickets = payload.ticket || [];
        
        // Collect all ticket sub-definitions in order from formModel
        const allSubFieldsOrdered = [];
        if (formModel.visibleFields) {
            formModel.visibleFields.forEach(f => {
                if (f.type === 'ticket') {
                    const subs = f.subFields || f.fields || (f.data && f.data.fields) || [];
                    allSubFieldsOrdered.push(...subs);
                }
            });
        }

        payloadTickets.forEach((ticketData, index) => {
             const tData = { index: index + 1, rows: [], hasSpot: false };
             
             if (ticketData.spot !== undefined) {
                 tData.hasSpot = true;
                 
                 // Resolve Spot Label
                 let spotLabel = ticketData.spotName || `Spot #${ticketData.spot}`;
                 let spotPrice = null;
                 if (ticketData.spotPrice) {
                     spotPrice = formatPrice(ticketData.spotPrice, totalPriceData.currency, 0, 'cs-CZ');
                     // Don't append price to label anymore
                 }
                 
                 tData.rows.push({ label: OrdersStrings.gridSpot || "Spot", value: spotLabel, price: spotPrice, isSpot: true });
             }
             
             if (ticketData.fields) {
                 // Iterate definitions to ensure correct order
                 allSubFieldsOrdered.forEach(subDef => {
                      // Find matching data entry in ticketData.fields
                      const fObj = ticketData.fields.find(obj => {
                           if (obj['_subFieldId']) {
                               return String(obj['_subFieldId']) === String(subDef.id);
                           }
                           // Match by Key (fallback if no subFieldId)
                           return obj.hasOwnProperty(subDef.type);
                      });

                      if (fObj) {
                           let val = fObj[subDef.type];
                           if (val === undefined) {
                                // Fallback: find relevant value key
                                const key = Object.keys(fObj).find(k => k !== '_subFieldId' && k !== 'currency_code');
                                if (key) val = fObj[key];
                           }

                           if (val !== undefined) {
                               const result = FieldPreviewFactory.format(subDef, val, {
                                  currency: totalPriceData.currency,
                                  features: formModel.occasionFeatures,
                               });
                               if (formModel.registrationMode === 'waitlist' && !String(result.value ?? '').trim()) return;
                               tData.rows.push({ label: formFieldTitle(subDef), value: result.value, price: result.price, metaSurcharge: result.metaSurcharge });
                           }
                      }
                 });
             }
             if (formModel.registrationMode !== 'waitlist' || tData.rows.length) tickets.push(tData);
        });


        // Deposit logic: check if any selected ticket product has deposit data
        const depositInfo = formModel.registrationMode === 'waitlist' ? null : OrderPreview._getDepositInfo(payload, formModel, totalPriceData.currency);

        // Visual-only meta surcharge sums per currency (e.g. on-site EUR doplatek).
        // Never added to totalPrice — surcharge doesn't go through the bank.
        const metaSurchargeSums = FormHelper.calculateMetaSurchargeSums(payload, formModel);

        return {
            registrationMode: formModel.registrationMode,
            occasionTitle: formModel.occasionTitle,
            orderSymbol: formModel.offerBundle?.orderSymbol,
            personalInfo,
            tickets,
            ticketCount: payloadTickets.length,
            totalPrice: totalPriceData.totalPrice,
            currency: totalPriceData.currency,
            hasTickets: FeatureService.isFeatureEnabled(FeatureService.FeatureConstants.ticket, formModel.occasionFeatures),
            tone: formModel.communicationTone,
            deposit: depositInfo,
            metaSurchargeSums
        };
    }

    /**
     * Checks if any selected ticket product has deposit and calculates deposit total.
     * Mirrors Flutter's _hasDepositProducts + _calculateDepositTotal + isDepositChoiceAvailable.
     * Returns { hasDeposit, depositTotal, depositFeature, currency } or null.
     */
    static _getDepositInfo(payload, formModel, currency) {
        const features = formModel.occasionFeatures;
        if (!FeatureService.isFeatureEnabled(FeatureService.FeatureConstants.deposit, features)) return null;
        if (!FeatureService.isDepositChoiceAvailable(features, formModel.occasionStartTime)) return null;

        // Build map: product ID → deposit amount from FormOptionModel instances
        // (sub.options are FormOptionModel with .id and .data.deposit.amount)
        const depositMap = new Map();
        const allSubFields = [];
        if (formModel.relatedFields) {
            formModel.relatedFields.forEach(f => {
                const subs = f.subFields || [];
                allSubFields.push(...subs);
            });
        }
        allSubFields.forEach(sub => {
            if (sub.type === 'product_type' && sub.options) {
                sub.options.forEach(opt => {
                    if (opt.data && opt.data.deposit && opt.data.deposit.amount > 0) {
                        depositMap.set(String(opt.id), opt.data.deposit.amount);
                    }
                });
            }
        });

        if (depositMap.size === 0) return null;

        // Check selected products in payload and calculate deposit total
        // Mirrors Flutter: depositAmount ?? price (fallback to full price)
        let depositTotal = 0;
        let hasDeposit = false;
        const payloadTickets = payload.ticket || [];
        payloadTickets.forEach(t => {
            if (t.fields) {
                t.fields.forEach(f => {
                    const productId = f.product_type;
                    if (productId) {
                        // Handle multiselect (pipe-separated)
                        String(productId).split(' | ').forEach(pid => {
                            const depAmount = depositMap.get(String(pid));
                            if (depAmount) {
                                depositTotal += depAmount;
                                hasDeposit = true;
                            }
                        });
                    }
                });
            }
        });

        if (!hasDeposit) return null;

        const depositFeature = FeatureService.getDepositFeature(features);
        return { hasDeposit, depositTotal, depositFeature, currency };
    }

    static _render(data) {
        // Determine labels
        const isWaitlist = data.registrationMode === 'waitlist';
        const itemLabel = isWaitlist ? WaitlistStrings.text((data.ticketCount ?? data.tickets.length) === 1 ? 'yourRegistration' : 'person') : data.hasTickets ? (OrdersStrings.ticket || "Ticket") : (OrdersStrings.application || "Application");

        // Header
        let html = `
            <div class="order-preview-content">
                <div class="order-preview-handle-bar">
                    <div class="order-preview-handle"></div>
                </div>
                <div class="order-preview-header">
                    <h2>${data.presentation?.title || (isWaitlist ? WaitlistStrings.title : PublicOrderStrings.summary)}</h2>
                    <button class="btn-close-preview"><i class="material-icons">close</i></button>
                </div>
                <div class="order-preview-body">
        `;

        const occasionTitle = data.presentation?.occasionTitle || data.occasionTitle;
        const orderSymbol = data.presentation?.orderSymbol || data.orderSymbol;
        if (occasionTitle || orderSymbol) {
            html += `<div class="waitlist-context">${occasionTitle ? htmlText`<strong>${occasionTitle}</strong>` : ''}${orderSymbol ? htmlText`<p>${WaitlistStrings.text('registrationSymbol')}: ${orderSymbol}</p>` : ''}</div>`;
        }
        if (isWaitlist) html += `<p class="waitlist-intro preview-section">${data.presentation?.explanation || WaitlistStrings.explanation}</p>`;

        if (data.presentation?.people) {
            html += `<div class="preview-section">${data.presentation.people.map(name => htmlText`${name}`).join('<br>')}</div>`;
        }
        // Personal Info
        if (data.personalInfo.length > 0) {
            html += `<div class="preview-section">`;
            data.personalInfo.forEach((item, index) => {
                const priceHtml = !isWaitlist && item.price ? `<span class="preview-price">+ ${item.price}</span>` : '';
                html += `
                    <div class="preview-info-row">
                        <span class="preview-label">${item.label ? htmlText`${item.label}:` : ''}</span>
                        <div class="preview-value-row">
                             <span class="preview-value">${item.value}</span>
                             ${priceHtml}
                        </div>
                    </div>
                `;
                if (index < data.personalInfo.length - 1) {
                    html += `<div class="preview-divider"></div>`;
                }
            });
            html += `</div>`;
        }

        if (isWaitlist && data.ticketCount > 1) {
            html += `<p class="preview-registration-count">${WaitlistStrings.text('registrationCount')}: ${data.ticketCount}</p>`;
        }
        // Tickets
        if (data.tickets.length > 0) {
             data.tickets.forEach((ticket) => {
                  html += `
                    <div class="ticket-card">
                        <div class="ticket-header-title">${itemLabel}${(data.ticketCount ?? data.tickets.length) > 1 ? ' ' + ticket.index : ''}</div>
                  `;
                  
                  // Spot/Fields
                  ticket.rows.forEach((row, rIndex) => {
                      const priceHtml = !isWaitlist && row.price ? `<span class="preview-price">+ ${row.price}</span>` : '';
                      const metaHtml = !isWaitlist && row.metaSurcharge
                          ? `<div class="preview-meta-surcharge">${String(row.metaSurcharge).replace(/\n/g, '<br>')}</div>`
                          : '';
                      html += `
                        <div class="preview-info-row">
                             <span class="preview-label">${row.label ? htmlText`${row.label}:` : ''}</span>
                             <div class="preview-value-row">
                                  <span class="preview-value">${row.value}</span>
                                  ${priceHtml}
                             </div>
                             ${metaHtml}
                        </div>
                      `;
                      if (rIndex < ticket.rows.length - 1) {
                           html += `<div class="preview-divider"></div>`;
                      }
                  });

                  html += `</div>`; // Close card
             });
        }

        // Deposit Section
        if (data.deposit) {
            const dep = data.deposit;
            const depositPrice = formatPrice(dep.depositTotal, dep.currency, 0, 'cs-CZ');
            const fullPrice = formatPrice(data.totalPrice, data.currency, 0, 'cs-CZ');
            const isOnSite = dep.depositFeature && dep.depositFeature.deposit_deadline === 'on_site';
            const infoText = isOnSite
                ? PublicOrderStrings.depositInfoOnSite
                : PublicOrderStrings.depositInfoDaysBefore(dep.depositFeature?.deposit_deadline_days || 0);

            html += `
                <div class="preview-section deposit-section">
                    <div class="deposit-section-title">${PublicOrderStrings.paymentMethod}</div>
                    <label class="deposit-option">
                        <input type="radio" name="payment_type" value="deposit" checked />
                        <span>${PublicOrderStrings.payWithDeposit} (${depositPrice})</span>
                        <div class="deposit-info-text">${infoText}</div>
                    </label>
                    <label class="deposit-option">
                        <input type="radio" name="payment_type" value="full" />
                        <span>${PublicOrderStrings.payFullAmount} (${fullPrice})</span>
                    </label>
                </div>
            `;
        }

        // Total
        const formattedPrice = formatPrice(data.totalPrice, data.currency, 0, 'cs-CZ');
        const totalPriceString = PublicOrderStrings.totalPrice(formattedPrice);

        // Per-currency meta surcharge sums (visual-only, NOT added to totalPrice).
        // Negative amounts (slevy) render with leading "−".
        const metaLines = FormHelper.formatMetaSurchargeSumLines(
            data.metaSurchargeSums, LocalizationService.currentLocale);
        const metaHtml = metaLines.length > 0
            ? `<div class="preview-total-meta-surcharge">
                 ${metaLines.map(l => `<div>${l}</div>`).join('')}
               </div>`
            : '';

        if (!isWaitlist) html += `
             <div class="preview-total-price">
                 ${totalPriceString}
                 ${metaHtml}
             </div>
        `;

        html += `</div>`; // Close Body

        // Actions
        // Determine Tone and Ticket Status from FormModel? passing it??
        // We passed formModel to show, but _render takes 'data'.
        // We need tone. Let's hijack data to include tone.
        const tone = data.tone; 
        const hasTickets = data.hasTickets;
        
        const submitLabel = data.presentation?.submitLabel || (isWaitlist ? WaitlistStrings.register : PublicOrderStrings.getSubmitButton(hasTickets, tone));

        html += `
             <div class="preview-actions">
                 <button class="btn-submit-order">
                     ${submitLabel}
                 </button>
             </div>
        `;

        html += `</div>`; // Close Content
        return html;
    }
}
