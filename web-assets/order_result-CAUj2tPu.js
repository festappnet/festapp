import"./index-BxGoqAKg.js";import{P as e}from"./public_order_strings-DgqgOWWe.js";class _{static render(a,m,t,b,f){const l=b.communicationTone,h=b.visibleFields.some(o=>o.type==="ticket");let n,c,s="check_circle",i="success-color";if(m)n=e.successTitle(l,h),c=e.paymentInfo(l);else if(t&&t.code===1017){const o=t.product&&t.product.title||"";n=e.productUnavailable(o),c=e.chooseDifferentVariant(l),s="error",i="error-color"}else{const o=t&&t.code||0;n=e.orderFailed,c=e.orderError(o),s="error",i="error-color"}a.innerHTML=`
            <div class="result-container">
                <div class="result-icon-wrapper ${i}">
                    <i class="material-icons result-icon">${s}</i>
                </div>
                <h2 class="result-title ${i}">${n}</h2>
                <p class="result-subtitle">${c}</p>
                <div class="result-payment-details"></div>
                
                <div class="result-actions">
                    <button class="btn btn-outline-secondary btn-back-to-form">
                        ${e.backToForm}
                    </button>
                </div>
            </div>
            <style>
                .result-container {
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    padding: 32px 16px;
                    text-align: center;
                    animation: fadeIn 0.5s ease-out;
                    width: 100%;
                    max-width: 600px; /* Prevent being too wide on desktops */
                    margin: 0 auto; /* Center in parent if block */
                    box-sizing: border-box;
                }
                .result-icon-wrapper {
                    width: 120px;
                    height: 120px;
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    margin-bottom: 24px;
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
                    font-size: 64px;
                }
                .result-title {
                    font-size: 1.4rem;
                    font-weight: bold;
                    margin-bottom: 8px;
                }
                .result-subtitle {
                    font-size: 1rem;
                    color: var(--text-color);
                    opacity: 0.7;
                    margin-bottom: 32px;
                    max-width: 400px;
                    line-height: 1.5;
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
                .result-payment-details { width: 100%; max-width: 420px; margin: 0 0 24px; }
                .result-payment-row { display: flex; justify-content: space-between; gap: 16px; padding: 6px 0; text-align: left; }
                .result-payment-value { font-weight: 600; text-align: right; overflow-wrap: anywhere; }
                .result-actions button:hover {
                    background-color: rgba(0,0,0,0.05);
                }
                
                @keyframes scaleIn {
                    from { transform: scale(0); opacity: 0; }
                    to { transform: scale(1); opacity: 1; }
                }
            </style>
        `;const r=m?t?.payment_qr:null,x=a.querySelector(".result-payment-details");if(x&&r){const o=[[e.bankAccount,r.account_number_human_readable||r.account_number],[r.reference_kind==="RF"?e.paymentReference:e.variableSymbol,r.reference],[e.amountToPay,`${r.amount} ${r.currency_code}`]];for(const[v,d]of o){if(d==null||String(d).trim()==="")continue;const p=document.createElement("div");p.className="result-payment-row";const g=document.createElement("span"),u=document.createElement("span");u.className="result-payment-value",g.textContent=v,u.textContent=String(d),p.append(g,u),x.appendChild(p)}}const y=a.querySelector(".btn-back-to-form");y&&(y.onclick=()=>{f&&f()})}}export{_ as OrderResult};
