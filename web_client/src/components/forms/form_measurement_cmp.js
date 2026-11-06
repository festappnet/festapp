import klaro from 'klaro';
import {bindKlaroConsent} from './form_measurement_consent.js';
import {FormStrings} from './form_strings.js';
import {AppConfig} from '../../app_config.js';

export function startMeasurementConsent({win = window, model, transport, host}) {
    const policy = model.data?.analytics;
    if (!Number.isSafeInteger(policy?.organization) || !Number.isSafeInteger(policy?.unit)) return () => {};
    const config = {
        version:1, elementID:'festapp-measurement-consent',
        storageName:`festapp-measurement-${policy.organization}-${policy.unit}`,
        storageMethod:'cookie', cookieExpiresAfterDays:180,
        lang:win.document.documentElement.lang?.slice(0,2) || AppConfig.defaultLanguage,
        privacyPolicy:AppConfig.privacyUrl,
        translations:{[win.document.documentElement.lang?.slice(0,2) || AppConfig.defaultLanguage]:{decline:FormStrings.measurementConsentDecline}},
        services:[{name:'analytics',title:FormStrings.measurementConsentService,
            description:FormStrings.measurementConsentDescription,purposes:['analytics'],default:false,required:false}],
    };
    let manager, unbind;
    try {
        manager = klaro.getManager(config);
        unbind = bindKlaroConsent(manager, granted => transport.setConsent(granted), {win});
        if (!manager.confirmed) klaro.show(config,true);
    } catch {
        transport.setConsent(false);
        win.document.getElementById(config.elementID)?.remove();
        return () => {};
    }
    const choices = win.document.createElement('button');
    choices.type = 'button'; choices.className = 'btn-text';
    choices.textContent = FormStrings.measurementConsentChoices;
    choices.addEventListener('click', () => klaro.show(config,true));
    host.append(choices);
    return () => {unbind(); choices.remove(); win.document.getElementById(config.elementID)?.remove();};
}
