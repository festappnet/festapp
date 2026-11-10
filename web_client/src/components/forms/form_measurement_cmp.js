import klaro from 'klaro';
import {isConsentLinkOrigin, isLocalConsentLink, prepareConsentLink, requestLinkedConsent} from './form_consent_link.js';
import {applyKlaroVisitChoice, bindKlaroConsent} from './form_measurement_consent.js';
import {FormStrings} from './form_strings.js';
import {AppConfig} from '../../app_config.js';
import {ColorUtils} from '../../utils/color_utils.js';

const channel = value => { const c = value / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
const luminance = ({r, g, b}) => 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
function contrast(first, second) {
    const [a, b] = [first, second].map(color => ColorUtils.parseToRgb(color));
    if (!a || !b || [a.r, a.g, a.b, b.r, b.g, b.b].some(Number.isNaN)) return 0;
    const [high, low] = [luminance(a), luminance(b)].sort((x, y) => y - x);
    return (high + 0.05) / (low + 0.05);
}

// ThemeService puts the form design on body. It is used only when both the text
// and the buttons stay readable, otherwise the notice keeps its standard look.
function noticeColors(win) {
    const style = win.getComputedStyle(win.document.body);
    const read = name => style.getPropertyValue(name).trim();
    const colors = {surface:read('--card-bg'), text:read('--text-color'), primary:read('--primary-color'), button:read('--btn-text-color')};
    const safe = Object.values(colors).every(color => /^(#[0-9a-f]{3,6}|rgb\([\d\s.,]+\))$/i.test(color));
    const palette = safe && contrast(colors.text, colors.surface) >= 4.5 && contrast(colors.button, colors.primary) >= 4.5 ? colors
        : {surface:'#fff', text:'#000', primary:'#4465a6', button:'#fff'};
    // Filled actions can retain branding even when that color is too light as text.
    return {...palette, accent:contrast(palette.primary, palette.surface) >= 4.5 ? palette.primary : palette.text};
}

// Plain text only. Braces are Klaro placeholders, and an unknown one would vanish.
function customText(value, limit) {
    return typeof value === 'string' && value.trim() ? value.trim().slice(0, limit).replace(/[{}]/g, '') : null;
}

function privacyUrl(value) {
    if (typeof value !== 'string' || value.length > 2048 || !/^https:\/\//.test(value) || /[\s\\\x00-\x1f\x7f]/.test(value)) return null;
    try {
        const url = new URL(value);
        return url.protocol === 'https:' && url.hostname && !url.username && !url.password
            && !value.slice(8).split(/[/?#]/)[0].includes('@') ? value : null;
    } catch { return null; }
}

export function startMeasurementConsent({win = window, model, setConsent, host}) {
    prepareConsentLink(win);
    const policy = model.data?.analytics;
    if (!Number.isSafeInteger(policy?.organization) || !Number.isSafeInteger(policy?.unit)) return () => {};
    const privacy = privacyUrl(policy.privacy_url);
    if (!privacy) {
        return () => {};
    }
    const lang = win.document.documentElement.lang?.slice(0,2) || AppConfig.defaultLanguage;
    const notice = policy.consent_notice;
    const title = customText(notice?.title, 80) ?? FormStrings.measurementConsentTitle;
    const ownText = customText(notice?.text, 500);
    const description = ownText ? ownText + ' ' + FormStrings.measurementConsentChangeChoice : FormStrings.measurementConsentDescription;
    const config = {
        version:1, elementID:'festapp-measurement-consent',
        storageName:`festapp-measurement-${policy.organization}-${policy.unit}-${policy.processing_revision}`,
        storageMethod:'cookie', cookieExpiresAfterDays:180, cookiePath:'/',
        lang, fallbackLang:lang,
        // In Klaro 0.7.21 mustConsent forces the detailed modal. The modal
        // notice itself has no close action or backdrop dismissal.
        noticeAsModal:true, mustConsent:false, acceptAll:true, hideLearnMore:false,
        disablePoweredBy:true, showNoticeTitle:true, groupByPurpose:false, hideToggleAll:true, htmlTexts:false,
        privacyPolicy:privacy,
        translations:{[lang]:{
            ok:FormStrings.measurementConsentAccept, acceptAll:FormStrings.measurementConsentAcceptAll,
            acceptSelected:FormStrings.measurementConsentSave, save:FormStrings.measurementConsentSave,
            decline:FormStrings.measurementConsentDecline, close:FormStrings.measurementConsentClose,
            consentNotice:{title, learnMore:FormStrings.measurementConsentSettings, description:description + ' {privacyPolicy}', changeDescription:''},
            // Fixed heading; the organizer's own text (if any) stays visible when the choice is changed later.
            consentModal:{title:FormStrings.measurementConsentModalTitle, description:ownText ? ownText + ' ' + FormStrings.measurementConsentModalDescription + ' ' + FormStrings.measurementConsentChangeChoice : FormStrings.measurementConsentModalDescription},
            privacyPolicy:{name:FormStrings.measurementConsentPrivacy, text:'{privacyPolicy}'},
        }},
        services:[
            {name:'analytics',title:FormStrings.measurementConsentService,
                description:FormStrings.measurementConsentAnalyticsDescription,purposes:[],default:false,required:false},
            {name:'marketing',title:FormStrings.measurementConsentMarketing,
                description:FormStrings.measurementConsentMarketingDescription,purposes:[],default:false,required:false},
        ],
    };
    let manager, unbind, choices, activeLayer, opener, draft, stopLink, expiryTimer;
    // Remote choice lives only in this controller; local saves keep Klaro storage.
    let imported = false;
    const hadConsentSpace = win.document.body.classList.contains('festapp-consent-space');
    win.document.body.classList.add('festapp-consent-space');
    let focusTimer, disposed = false;
    const inertNodes = new Map();
    // Informational only: registering another Klaro service would change the
    // stored cookie and invalidate existing two-purpose choices.
    const necessary = win.document.createElement('li');
    necessary.className = 'cm-service festapp-necessary';
    const heading = win.document.createElement('div');
    heading.className = 'festapp-necessary-head';
    const label = win.document.createElement('span');
    label.className = 'cm-list-title';
    label.textContent = FormStrings.measurementConsentNecessary;
    const always = win.document.createElement('span');
    always.className = 'festapp-always';
    always.textContent = FormStrings.measurementConsentAlwaysActive;
    const lockedSwitch = win.document.createElement('span');
    lockedSwitch.className = 'festapp-switch-locked'; lockedSwitch.setAttribute('aria-hidden', 'true');
    heading.append(label, always, lockedSwitch);
    const details = win.document.createElement('p');
    details.className = 'cm-list-description';
    details.textContent = FormStrings.measurementConsentNecessaryDescription;
    necessary.append(heading, details);
    const rootNode = () => win.document.getElementById(config.elementID);
    const focusables = layer => [...layer.querySelectorAll('button,a[href],input,[tabindex]')]
        .filter(node => !node.disabled && node.tabIndex >= 0 && !node.hidden);
    const restoreInert = () => {
        for (const [node, value] of inertNodes) {
            if (value === null) node.removeAttribute('inert'); else node.setAttribute('inert', value);
        }
        inertNodes.clear();
    };
    const enhance = () => {
        if (disposed) return;
        const root = rootNode();
        const list = root?.querySelector('.cm-services');
        if (list && necessary.parentNode !== list) list.prepend(necessary);
        // On the standalone form the privacy policy opens in a new tab, so the
        // visitor does not leave a form in progress. Embedded forms show no bar.
        if (win.self === win.top) root?.querySelectorAll('a[href]').forEach(link => {
            if (link.target !== '_blank') link.target = '_blank';
            if (!link.relList.contains('noopener')) link.relList.add('noopener');
        });
        root?.querySelectorAll('.cm-list-input:not(:disabled)').forEach(input => {
            if (input.tabIndex !== 0) input.tabIndex = 0;
        });
        const noticeLayer = root?.querySelector('.cookie-modal-notice');
        const modal = root?.querySelector('.cm-modal');
        if (noticeLayer) {
            if (noticeLayer.tabIndex !== -1) noticeLayer.tabIndex = -1;
            noticeLayer.removeAttribute('autofocus');
            noticeLayer.setAttribute('role', 'dialog');
            noticeLayer.setAttribute('aria-modal', 'true');
            noticeLayer.setAttribute('aria-labelledby', 'id-cookie-title');
            const buttons = noticeLayer.querySelector('.cn-ok');
            const settings = buttons?.querySelector('.cm-btn-lern-more');
            if (settings && buttons.lastElementChild !== settings) buttons.append(settings);
        }
        if (modal) {
            modal.setAttribute('role', 'dialog');
            modal.setAttribute('aria-modal', 'true');
            const title = modal.querySelector('.title');
            if (title) { title.id = 'festapp-consent-settings-title'; modal.setAttribute('aria-labelledby', title.id); }
            const footer = modal.querySelector('.cm-footer-buttons');
            const save = footer?.querySelector('.cm-btn-accept');
            // Klaro hides Decline after confirmation. Keep revocation one action.
            if (footer && !footer.querySelector('.cn-decline')) {
                const decline = win.document.createElement('button');
                decline.type = 'button';
                decline.className = 'cm-btn cm-btn-decline cm-btn-danger cn-decline';
                decline.textContent = FormStrings.measurementConsentDecline;
                decline.addEventListener('click', () => {
                    manager.updateConsent('analytics', false);
                    manager.updateConsent('marketing', false);
                    // Save directly even while Klaro disables Save during confirmation.
                    manager.saveAndApplyConsents('decline');
                    draft = {...manager.consents};
                    // Remount the hidden notice to clear Klaro's confirming state.
                    klaro.render(config, {show:false});
                });
                footer.prepend(decline);
            }
            if (save && footer.lastElementChild !== save) footer.append(save);
        }
        const layer = modal || noticeLayer;
        if (choices) choices.hidden = !!layer || !manager?.confirmed;
        if (layer) {
            for (const node of win.document.body.children) {
                if (node === root) continue;
                if (!inertNodes.has(node)) inertNodes.set(node, node.getAttribute('inert'));
                if (!node.hasAttribute('inert')) node.setAttribute('inert', '');
            }
            if (!locked) {
                locked = true;
                for (const {node} of scroll) node.style.overflow = 'hidden';
            }
        } else { restoreInert(); unlock(); }
        if (layer !== activeLayer) {
            const previous = activeLayer;
            activeLayer = layer;
            win.clearTimeout(focusTimer);
            focusTimer = win.setTimeout(() => {
                if (previous?.matches('.cm-modal') && opener) {
                    const target = opener.isConnected && !opener.hidden ? opener : rootNode()?.querySelector('.cm-btn-lern-more') || choices;
                    target?.focus();
                } else if (!layer) {
                    choices?.focus();
                } else if (layer?.matches('.cookie-modal-notice')) {
                    // Focus the notice itself: no focus ring on the privacy link
                    // at page load, and Tab still enters the first control.
                    layer.focus({preventScroll: true});
                } else if (layer) focusables(layer)[0]?.focus();
            }, 5);
        }
    };
    const rememberOpener = event => {
        const target = event.target.closest?.('.cm-btn-lern-more,.festapp-consent-fab');
        if (target) {
            opener = target;
            draft = {...manager.consents};
        }
        if (event.target.closest?.('.cm-modal .hide,.cookie-modal > .cm-bg') && activeLayer?.matches('.cm-modal')) {
            // Restore the draft without storing a cookie or confirming a choice.
            for (const [name, value] of Object.entries(draft || manager.savedConsents)) manager.updateConsent(name, value);
        }
    };
    const onKeydown = event => {
        if (!activeLayer) return;
        if (event.key === 'Escape' && activeLayer.matches('.cookie-modal-notice')) {
            event.preventDefault(); event.stopPropagation();
            activeLayer.focus({preventScroll: true});
        } else if (event.key === 'Escape' && activeLayer.matches('.cm-modal')) {
            event.preventDefault(); event.stopPropagation();
            activeLayer.querySelector('.hide')?.click();
        } else if (event.key === ' ' && event.target.matches('.cm-list-input:not(:disabled)')) {
            event.preventDefault();
            if (!event.repeat) event.target.click();
        } else if (event.key === 'Tab') {
            const controls = focusables(activeLayer);
            const index = controls.indexOf(win.document.activeElement);
            if (index < 0 || (event.shiftKey ? index === 0 : index === controls.length - 1)) {
                event.preventDefault();
                controls[event.shiftKey ? controls.length - 1 : 0]?.focus();
            }
        }
    };
    const observer = new win.MutationObserver(enhance);
    const importTtl = 24 * 60 * 60 * 1000;
    const metadataName = config.storageName + '-source';
    const retireImport = () => {
        imported = false;
        win.queueMicrotask(enhance);
        win.clearTimeout(expiryTimer);
    };
    const expireImportedChoice = () => {
        if (disposed || !imported || hasLocalChoice()) return;
        retireImport();
        applyKlaroVisitChoice(manager, null);
        showNormal();
    };
    const trackImport = metadata => {
        if (!isConsentLinkOrigin(metadata?.origin, isLocalConsentLink(win)) || !policy.approved_hosts?.includes(metadata.origin) ||
            metadata.session !== true || !Number.isFinite(metadata.importedAt) || metadata.importedAt > Date.now() || Date.now() - metadata.importedAt >= importTtl) {
            expireImportedChoice(); return;
        }
        win.clearTimeout(expiryTimer);
        expiryTimer = win.setTimeout(expireImportedChoice, Math.max(0, importTtl - (Date.now() - metadata.importedAt)));
    };
    const style = win.document.createElement('style');
    const colors = noticeColors(win);
    // Both layouts are the same blocking Klaro notice; the bar only docks it to the bottom.
    const layout = notice?.layout === 'modal' ? `
#festapp-measurement-consent .cookie-modal .cookie-modal-notice {box-sizing:border-box;left:0;right:0;width:calc(100% - 32px);max-width:428px;margin-left:auto;margin-right:auto}
` : `
#festapp-measurement-consent .cookie-modal .cookie-modal-notice {position:fixed;top:auto;bottom:0;left:0;right:0;width:100%;max-width:none;max-height:90dvh;overflow:auto;box-sizing:border-box;margin:0;transform:none;border-radius:12px 12px 0 0;padding:16px max(16px,calc((100vw - 960px)/2))}
@media (min-width:760px) {
#festapp-measurement-consent .cookie-modal-notice .cn-body {display:grid;grid-template-columns:minmax(0,1fr) minmax(260px,380px);grid-template-areas:"title buttons" "text buttons";column-gap:40px;align-items:center}
#festapp-measurement-consent .cookie-modal-notice .cn-body > h2 {grid-area:title;margin:0 0 4px}
#festapp-measurement-consent .cookie-modal-notice .cn-body > p {grid-area:text;margin:0}
#festapp-measurement-consent .cookie-modal-notice .cn-body > .cn-ok {grid-area:buttons;margin:0}
}
`;
    style.textContent = `
#festapp-measurement-consent {--notice-surface:${colors.surface};--notice-text:${colors.text};--notice-primary:${colors.primary};--notice-button:${colors.button};--notice-accent:${colors.accent}}
#festapp-measurement-consent .cookie-modal-notice,
#festapp-measurement-consent .cm-modal {background:var(--notice-surface);color:var(--notice-text);border-radius:12px;font-family:var(--font-family-base,inherit)}
#festapp-measurement-consent :is(p,strong,h1,h2,ul,li) {color:var(--notice-text)}
#festapp-measurement-consent .hide svg {stroke:var(--notice-text)}
#festapp-measurement-consent .cm-btn {background:var(--notice-primary);color:var(--notice-button);font:inherit;font-weight:500;padding:10px 18px;border:0;border-radius:6px;min-width:110px}
#festapp-measurement-consent .cookie-modal-notice .cn-body > p {line-height:1.5}
#festapp-measurement-consent .cn-ok {display:grid;grid-template-columns:1fr 1fr;gap:10px;align-items:stretch;margin:12px 0 0}
#festapp-measurement-consent .cn-ok .cn-buttons {display:contents}
#festapp-measurement-consent .cn-ok .cm-btn {width:100%;min-width:0;white-space:normal;margin:0;min-height:44px}
#festapp-measurement-consent .cn-ok .cm-btn-lern-more {grid-column:1 / -1}
#festapp-measurement-consent .cm-btn.cm-btn-lern-more {background:transparent;color:var(--notice-accent);box-shadow:inset 0 0 0 1.5px var(--notice-accent)}
#festapp-measurement-consent .cm-btn.cm-btn-lern-more:hover {background:color-mix(in srgb,var(--notice-primary) 8%,transparent)}
#festapp-measurement-consent .cookie-modal-notice:focus {outline:none}
#festapp-measurement-consent .cm-btn:focus-visible {outline:2px solid var(--notice-text);outline-offset:3px}
#festapp-measurement-consent .cm-services {list-style:none;margin:0;padding:0}
#festapp-measurement-consent .cm-services {display:flex;flex-direction:column;gap:10px}
#festapp-measurement-consent .cm-service {position:relative;padding:14px 16px;margin:0;border:1px solid color-mix(in srgb,var(--notice-text) 18%,transparent);border-radius:10px}
#festapp-measurement-consent .cm-service > div {position:relative}
#festapp-measurement-consent .cm-list-label,#festapp-measurement-consent .festapp-necessary-head {display:flex;align-items:center;justify-content:space-between;gap:16px;padding:0;margin:0;min-height:26px;cursor:pointer}
#festapp-measurement-consent .festapp-necessary-head {cursor:default}
#festapp-measurement-consent .cm-list-title {font-weight:600;font-size:1em;color:var(--notice-text)}
#festapp-measurement-consent .cm-list-label .cm-switch {position:relative;left:auto;top:auto;order:2;flex:0 0 44px;width:44px;height:24px}
#festapp-measurement-consent .cm-list-label .cm-switch .slider {position:absolute;top:0;left:0;width:44px;height:24px;border-radius:999px;background:color-mix(in srgb,var(--notice-text) 55%,var(--notice-surface));box-shadow:none;transition:background-color .15s}
#festapp-measurement-consent .cm-list-label .cm-switch .slider::before {content:'';position:absolute;left:2px;top:2px;bottom:auto;width:20px;height:20px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.3);transition:transform .15s}
#festapp-measurement-consent .cm-list-input {position:absolute;right:0;left:auto;top:1px;width:44px;height:24px;margin:0;opacity:0;z-index:1;cursor:pointer}
#festapp-measurement-consent .cm-list-input:checked + .cm-list-label .slider {background:var(--notice-accent)}
#festapp-measurement-consent .cm-list-input:checked + .cm-list-label .slider::before {transform:translateX(20px)}
#festapp-measurement-consent .cm-list-input:focus-visible + .cm-list-label .slider {outline:2px solid var(--notice-text);outline-offset:2px}
#festapp-measurement-consent .cm-list-description {margin:6px 0 0;padding:0;font-size:.875em;line-height:1.45;opacity:1}
#festapp-measurement-consent .festapp-always {position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
#festapp-measurement-consent .festapp-switch-locked {position:relative;flex:0 0 44px;width:44px;height:24px;border-radius:999px;background:color-mix(in srgb,var(--notice-text) 30%,transparent)}
#festapp-measurement-consent .festapp-switch-locked::before {content:'';position:absolute;left:22px;top:2px;width:20px;height:20px;border-radius:50%;background:#fff url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath d='M7 12.5l3.2 3.2L17 9' fill='none' stroke='%23333' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") center/16px no-repeat;opacity:.85}
#festapp-measurement-consent .cm-list-label .cm-switch .slider::before {background:#fff url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath d='M8 8l8 8M16 8l-8 8' stroke='%23333' stroke-width='2.4' stroke-linecap='round'/%3E%3C/svg%3E") center/16px no-repeat}
#festapp-measurement-consent .cm-list-input:checked + .cm-list-label .slider::before {background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath d='M7 12.5l3.2 3.2L17 9' fill='none' stroke='%23333' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E")}
#festapp-measurement-consent .cm-modal .cm-header {position:relative;padding:20px 24px 16px;border-bottom:1px solid color-mix(in srgb,var(--notice-text) 15%,transparent)}
#festapp-measurement-consent .cm-modal .cm-header .title {margin:0 40px 8px 0;font-size:1.25em;line-height:1.3}
#festapp-measurement-consent .cm-modal .cm-header p {margin:0;line-height:1.5;opacity:1}
#festapp-measurement-consent .cm-modal .cm-header .hide {position:absolute;top:6px;right:6px;width:44px;height:44px;display:grid;place-items:center;border-radius:8px}
#festapp-measurement-consent .cm-modal .cm-body {padding:16px 24px}
#festapp-measurement-consent .cm-modal .cm-footer {padding:14px 24px 18px;border-top:1px solid color-mix(in srgb,var(--notice-text) 15%,transparent)}
#festapp-measurement-consent .cm-modal .cm-footer-buttons {display:flex;flex-wrap:wrap;gap:10px;align-items:stretch}
#festapp-measurement-consent .cm-modal .cm-footer-buttons .cm-btn {flex:0 1 auto;min-width:120px;min-height:44px;margin:0}
#festapp-measurement-consent .cm-modal .cm-footer-buttons .cm-btn-accept {margin-left:auto;background:transparent;color:var(--notice-accent);box-shadow:inset 0 0 0 1.5px var(--notice-accent)}
@media (max-width:520px) {
#festapp-measurement-consent .cm-modal .cm-footer-buttons .cm-btn {flex:1 1 calc(50% - 5px);min-width:0}
#festapp-measurement-consent .cm-modal .cm-footer-buttons .cm-btn-accept {flex-basis:100%;margin-left:0}
}
#festapp-measurement-consent a {color:var(--notice-accent);text-decoration:underline;text-underline-offset:2px}
#festapp-measurement-consent .cookie-modal-notice {outline:none}
#festapp-measurement-consent .cm-header .hide svg {width:16px;height:16px}
.festapp-consent-fab[hidden] {display:none!important}
${layout}`;
    const scroll = [win.document.documentElement, win.document.body].map(node => ({node, value:node.style.overflow}));
    let locked = false;
    const unlock = () => {
        if (!locked) return;
        for (const {node,value} of scroll) node.style.overflow = value;
        locked = false;
    };
    const fail = (unavailable = false) => {
        disposed = true;
        // Revoke before touching a broken third-party manager's teardown.
        try { setConsent(unavailable ? null : false); } catch { /* Cleanup must still restore the page. */ }
        observer.disconnect(); necessary.remove();
        win.clearTimeout(focusTimer);
        win.document.removeEventListener('click', rememberOpener, true);
        win.document.removeEventListener('keydown', onKeydown, true);
        restoreInert();
        stopLink?.(); win.clearTimeout(expiryTimer);
        imported = false;
        unlock(); style.remove();
        if (!hadConsentSpace) win.document.body.classList.remove('festapp-consent-space');
        win.document.getElementById(config.elementID)?.remove();
        try { manager?.unwatch(watcher); } catch { /* A broken CMP cannot retain permission. */ }
        try { unbind?.(); } catch { /* Cleanup still restores the page. */ }
        if(unavailable)try { setConsent(null); } catch { /* Keep unavailable sources retryable. */ }
    };
    const watcher = {update:(_manager, event) => {
        win.queueMicrotask(enhance);
        if (event === 'saveConsents') { retireImport(); stopLink?.(); }
    }};
    try {
        win.document.head.append(style);
        observer.observe(win.document.body, {childList:true, subtree:true, attributes:true, attributeFilter:['tabindex']});
        win.document.addEventListener('click', rememberOpener, true);
        win.document.addEventListener('keydown', onKeydown, true);
        manager = klaro.getManager(config);
        // A browser-session cookie crosses visits. Discard every older import
        // before publishing a choice, including malformed source metadata.
        if (win.document.cookie.split('; ').some(value => value.startsWith(metadataName + '='))) {
            manager.resetConsents();
            win.document.cookie = `${metadataName}=; Max-Age=0; Path=/; SameSite=Lax`;
        }
        if (manager.store.get() === null) manager.resetConsents();
        else { manager.loadConsents(); manager.savedConsents = {...manager.consents}; }
        manager.watch(watcher);
        unbind = bindKlaroConsent(manager, granted => setConsent(granted));
    } catch {
        fail(true);
        return () => setConsent(false);
    }
    // Floating, unobtrusive way to change the choice later (the notice itself
    // links the privacy policy). Icon only; the label expands on hover/focus.
    choices = win.document.createElement('button');
    choices.hidden = true;
    choices.setAttribute('aria-haspopup', 'dialog');
    choices.type = 'button'; choices.className = 'festapp-consent-fab';
    choices.setAttribute('aria-label', FormStrings.measurementConsentChoices);
    choices.title = FormStrings.measurementConsentChoices;
    const svg = win.document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 -960 960 960'); svg.setAttribute('width', '24'); svg.setAttribute('height', '24'); svg.setAttribute('aria-hidden', 'true');
    const path = win.document.createElementNS(svg.namespaceURI, 'path'); path.setAttribute('fill', 'currentColor');
    path.setAttribute('d', 'M480-80q-83 0-156-31.5T197-197q-54-54-85.5-127T80-480q0-75 29-147t81-128.5q52-56.5 125-91T475-881q21 0 43 2t45 7q-9 45 6 85t45 66.5q30 26.5 71.5 36.5t85.5-5q-26 59 7.5 113t99.5 56q1 11 1.5 20.5t.5 20.5q0 82-31.5 154.5t-85.5 127q-54 54.5-127 86T480-80Zm-60-480q25 0 42.5-17.5T480-620q0-25-17.5-42.5T420-680q-25 0-42.5 17.5T360-620q0 25 17.5 42.5T420-560Zm-80 200q25 0 42.5-17.5T400-420q0-25-17.5-42.5T340-480q-25 0-42.5 17.5T280-420q0 25 17.5 42.5T340-360Zm260 40q17 0 28.5-11.5T640-360q0-17-11.5-28.5T600-400q-17 0-28.5 11.5T560-360q0 17 11.5 28.5T600-320ZM480-160q122 0 216.5-84T800-458q-50-22-78.5-60T683-603q-77-11-132-66t-68-132q-80-2-140.5 29t-101 79.5Q201-644 180.5-587T160-480q0 133 93.5 226.5T480-160Z');
    svg.append(path);
    const fabLabel = win.document.createElement('span');
    fabLabel.className = 'festapp-consent-fab-label'; fabLabel.textContent = FormStrings.measurementConsentChoices;
    choices.append(svg, fabLabel);
    choices.addEventListener('click', () => {
        try { klaro.show(config,true); } catch { fail(true); choices.remove(); }
    });
    // Body, not the form host: transformed form containers would anchor a
    // fixed element to themselves instead of the viewport.
    (win.document.body || host).append(choices);
    const showNormal = () => {
        if (manager.confirmed) return;
        try {
            klaro.show(config,false);
            locked = true;
            for (const {node} of scroll) node.style.overflow = 'hidden';
        } catch { fail(true); }
    };
    // Reload the cookie immediately before accepting: another tab's saved local
    // choice wins even when this manager was created before that choice.
    const hasLocalChoice = () => {
        if (manager.store.get() === null) return false;
        manager.loadConsents();
        manager.savedConsents = {...manager.consents};
        retireImport();
        manager.applyConsents();
        return manager.confirmed === true;
    };
    try {
        enhance();
        stopLink = requestLinkedConsent({win, policy, hasChoice:hasLocalChoice, settled:showNormal,
            accept:(choice, metadata) => {
                if (hasLocalChoice()) return;
                imported = true;
                applyKlaroVisitChoice(manager, choice);
                trackImport(metadata);
            }});
        if (!stopLink.pending) showNormal();
    } catch { showNormal(); }
    return () => {fail(); choices.remove();};
}
