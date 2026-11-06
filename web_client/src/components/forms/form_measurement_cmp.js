import klaro from 'klaro';
import {bindKlaroConsent} from './form_measurement_consent.js';
import {FormStrings} from './form_strings.js';
import {AppConfig} from '../../app_config.js';

export function startMeasurementConsent({win = window, model, transport, host}) {
    const policy = model.data?.analytics;
    if (!Number.isSafeInteger(policy?.organization) || !Number.isSafeInteger(policy?.unit)) return () => {};
    const lang = win.document.documentElement.lang?.slice(0,2) || AppConfig.defaultLanguage;
    const config = {
        version:1, elementID:'festapp-measurement-consent',
        storageName:`festapp-measurement-${policy.organization}-${policy.unit}`,
        storageMethod:'cookie', cookieExpiresAfterDays:180,
        lang, fallbackLang:lang,
        // In Klaro 0.7.21 mustConsent forces the detailed modal. The modal
        // notice itself has no close action or backdrop dismissal.
        noticeAsModal:true, mustConsent:false, acceptAll:true, hideLearnMore:true,
        disablePoweredBy:true, showNoticeTitle:true, groupByPurpose:false,
        privacyPolicy:AppConfig.privacyUrl,
        translations:{[lang]:{
            ok:FormStrings.measurementConsentAccept, acceptAll:FormStrings.measurementConsentAccept,
            acceptSelected:FormStrings.measurementConsentSave, save:FormStrings.measurementConsentSave,
            decline:FormStrings.measurementConsentDecline, close:FormStrings.measurementConsentClose,
            consentNotice:{title:FormStrings.measurementConsentTitle,
                description:FormStrings.measurementConsentDescription + ' {privacyPolicy}', changeDescription:''},
            consentModal:{title:FormStrings.measurementConsentTitle, description:FormStrings.measurementConsentDescription},
            privacyPolicy:{name:FormStrings.measurementConsentPrivacy, text:'{privacyPolicy}'},
        }},
        services:[{name:'analytics',title:FormStrings.measurementConsentService,
            description:FormStrings.measurementConsentDescription,purposes:[],default:false,required:false}],
    };
    let manager, unbind;
    const style = win.document.createElement('style');
    style.textContent = `
#festapp-measurement-consent .cookie-modal-notice,
#festapp-measurement-consent .cm-modal {background:var(--surface-color,#fff);color:var(--text-color,#000);border-radius:12px;font-family:inherit}
#festapp-measurement-consent :is(p,strong,h1,h2,ul,li) {color:var(--text-color,#000)}
#festapp-measurement-consent .hide svg {stroke:var(--text-color,#000)}
#festapp-measurement-consent .cm-btn {background:var(--primary-color,#4465a6);color:#fff;font:inherit;font-weight:500;padding:10px 18px;border:0;border-radius:6px;min-width:110px}
#festapp-measurement-consent .cn-buttons {display:flex;gap:12px}
#festapp-measurement-consent a {color:var(--primary-color,#4465a6)}
`;
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
        try { transport.setConsent(false); } catch { /* Measurement cannot block cleanup. */ }
    };
    const watcher = {update:() => { if (manager.confirmed) unlock(); }};
    try {
        win.document.head.append(style);
        manager = klaro.getManager(config);
        manager.watch(watcher);
        unbind = bindKlaroConsent(manager, granted => transport.setConsent(granted), {win});
        if (!manager.confirmed) {
            locked = true;
            for (const {node} of scroll) node.style.overflow = 'hidden';
            klaro.show(config,false);
        }
    } catch {
        fail();
        return () => {};
    }
    const choices = win.document.createElement('button');
    choices.type = 'button'; choices.className = 'btn-text';
    choices.textContent = FormStrings.measurementConsentChoices;
    choices.addEventListener('click', () => {
        try { klaro.show(config,true); } catch { fail(); choices.remove(); }
    });
    host.append(choices);
    return () => {fail(); choices.remove();};
}
