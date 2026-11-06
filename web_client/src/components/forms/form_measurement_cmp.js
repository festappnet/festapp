import klaro from 'klaro';
import {bindKlaroConsent} from './form_measurement_consent.js';
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
    return safe && contrast(colors.text, colors.surface) >= 4.5 && contrast(colors.button, colors.primary) >= 4.5 ? colors
        : {surface:'var(--surface-color,#fff)', text:'var(--text-color,#000)', primary:'var(--primary-color,#4465a6)', button:'#fff'};
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

export function startMeasurementConsent({win = window, model, transport, host}) {
    const policy = model.data?.analytics;
    if (!Number.isSafeInteger(policy?.organization) || !Number.isSafeInteger(policy?.unit)) return () => {};
    const privacy = privacyUrl(policy.privacy_url);
    if (!privacy) {
        return () => {};
    }
    const lang = win.document.documentElement.lang?.slice(0,2) || AppConfig.defaultLanguage;
    const notice = policy.consent_notice;
    const title = customText(notice?.title, 80) ?? FormStrings.measurementConsentTitle;
    const description = customText(notice?.text, 500) ?? FormStrings.measurementConsentDescription;
    const config = {
        version:1, elementID:'festapp-measurement-consent',
        storageName:`festapp-measurement-${policy.organization}-${policy.unit}`,
        storageMethod:'cookie', cookieExpiresAfterDays:180,
        lang, fallbackLang:lang,
        // In Klaro 0.7.21 mustConsent forces the detailed modal. The modal
        // notice itself has no close action or backdrop dismissal.
        noticeAsModal:true, mustConsent:false, acceptAll:true, hideLearnMore:true,
        disablePoweredBy:true, showNoticeTitle:true, groupByPurpose:false, hideToggleAll:true, htmlTexts:false,
        privacyPolicy:privacy,
        translations:{[lang]:{
            ok:FormStrings.measurementConsentAccept, acceptAll:FormStrings.measurementConsentAccept,
            acceptSelected:FormStrings.measurementConsentSave, save:FormStrings.measurementConsentSave,
            decline:FormStrings.measurementConsentDecline, close:FormStrings.measurementConsentClose,
            consentNotice:{title, description:description + ' {privacyPolicy}', changeDescription:''},
            consentModal:{title, description},
            privacyPolicy:{name:FormStrings.measurementConsentPrivacy, text:'{privacyPolicy}'},
        }},
        services:[
            {name:'analytics',title:FormStrings.measurementConsentService,
                description:FormStrings.measurementConsentAnalyticsDescription,purposes:[],default:false,required:false},
            {name:'marketing',title:FormStrings.measurementConsentMarketing,
                description:FormStrings.measurementConsentMarketingDescription,purposes:[],default:false,required:false},
        ],
    };
    let manager, unbind;
    const style = win.document.createElement('style');
    const colors = noticeColors(win);
    // Both layouts are the same blocking Klaro notice; the bar only docks it to the bottom.
    const layout = notice?.layout === 'modal' ? `
#festapp-measurement-consent .cookie-modal .cookie-modal-notice {box-sizing:border-box;left:0;right:0;width:calc(100% - 32px);max-width:428px;margin-left:auto;margin-right:auto}
` : `
#festapp-measurement-consent .cookie-modal .cookie-modal-notice {position:fixed;top:auto;bottom:0;left:0;right:0;width:100%;max-width:none;max-height:90vh;overflow:auto;box-sizing:border-box;margin:0;transform:none;border-radius:12px 12px 0 0;padding:12px max(16px,calc((100vw - 960px)/2)) 16px}
`;
    style.textContent = `
#festapp-measurement-consent {--notice-surface:${colors.surface};--notice-text:${colors.text};--notice-primary:${colors.primary};--notice-button:${colors.button}}
#festapp-measurement-consent .cookie-modal-notice,
#festapp-measurement-consent .cm-modal {background:var(--notice-surface);color:var(--notice-text);border-radius:12px;font-family:var(--font-family-base,inherit)}
#festapp-measurement-consent :is(p,strong,h1,h2,ul,li) {color:var(--notice-text)}
#festapp-measurement-consent .hide svg {stroke:var(--notice-text)}
#festapp-measurement-consent .cm-btn {background:var(--notice-primary);color:var(--notice-button);font:inherit;font-weight:500;padding:10px 18px;border:0;border-radius:6px;min-width:110px}
#festapp-measurement-consent .cn-buttons {display:flex;gap:12px}
#festapp-measurement-consent a {color:var(--notice-primary)}
${layout}`;
    const scroll = [win.document.documentElement, win.document.body].map(node => ({node, value:node.style.overflow}));
    let locked = false;
    const unlock = () => {
        if (!locked) return;
        for (const {node,value} of scroll) node.style.overflow = value;
        locked = false;
    };
    const fail = () => {
        unlock(); style.remove();
        win.document.getElementById(config.elementID)?.remove();
        manager?.unwatch(watcher);
        try { unbind?.(); } catch { /* Cleanup still restores the page. */ }
        try { transport.setConsent(false); } catch { /* Reporting cannot block cleanup. */ }
    };
    const watcher = {update:() => { if (manager.confirmed) unlock(); }};
    try {
        win.document.head.append(style);
        manager = klaro.getManager(config);
        manager.watch(watcher);
        unbind = bindKlaroConsent(manager, granted => transport.setConsent(granted));
        if (!manager.confirmed) {
            locked = true;
            for (const {node} of scroll) node.style.overflow = 'hidden';
            klaro.show(config,false);
        }
    } catch {
        fail();
        transport.start?.();
        return () => {};
    }
    // The frame starts with the saved choice already known. The notice blocks nothing else.
    transport.start?.();
    const choices = win.document.createElement('button');
    choices.type = 'button'; choices.className = 'btn-text';
    choices.textContent = FormStrings.measurementConsentChoices;
    choices.addEventListener('click', () => {
        try { klaro.show(config,true); } catch { fail(); choices.remove(); }
    });
    host.append(choices);
    return () => {fail(); choices.remove();};
}
