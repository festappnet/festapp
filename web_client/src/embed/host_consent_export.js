import {createWixConsentSource} from './host_wix_consent.js';
import {createComplianzSource} from './host_complianz.js';
import {createCookiebotSource} from './host_cookiebot.js';
import {createCookieConsentSource} from './host_cookieconsent.js';
import {validConsentBinding, sameConsentBinding} from '../components/forms/measurement_consent_source.js';
import {isConsentLinkOrigin} from '../components/forms/form_consent_link.js';

export function parseConsentExport(input, {serviceOrigin, websiteOrigin} = {}) {
    try {
        if (typeof input === 'string' && input.length > 16384) return null;
        const value = typeof input === 'string' ? JSON.parse(input) : input;
        if (value?.schemaVersion !== 1 || !validConsentBinding(value.binding) ||
            !isConsentLinkOrigin(value.serviceOrigin) || !isConsentLinkOrigin(value.websiteOrigin) ||
            (serviceOrigin && value.serviceOrigin !== serviceOrigin) || (websiteOrigin && value.websiteOrigin !== websiteOrigin)) return null;
        const c = value.providerConfig;
        if (!['complianz','cookiebot','cookieconsent','wix'].includes(c?.provider) ||
            ![c.organization,c.unit].every(v => Number.isSafeInteger(v) && v > 0) ||
            typeof c.consentRevision !== 'string' || !/^[a-f0-9]{32}$/.test(c.consentRevision) || c.origin !== value.websiteOrigin) return null;
        return value;
    } catch { return null; }
}
export function createManagedConsentSource(win, input, serviceOrigin) {
    const value = parseConsentExport(input, {serviceOrigin, websiteOrigin:win.location.origin});
    const create = {complianz:createComplianzSource, cookiebot:createCookiebotSource, cookieconsent:createCookieConsentSource, wix:createWixConsentSource}[value?.providerConfig.provider];
    const source = create?.(win, value.providerConfig);
    return {
        read(scope) {
            if (!value || !sameConsentBinding(scope?.binding, value.binding) || scope?.websiteOrigin !== value.websiteOrigin) return null;
            const choice = source.read(scope);
            return choice ? {...choice, binding:{...value.binding}} : null;
        },
        subscribe:listener => source ? source.subscribe(listener) : () => {},
    };
}
