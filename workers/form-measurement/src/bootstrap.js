import {measurementProtocol} from '../../../web_client/src/components/forms/form_measurement_contract.js';
import {measurementSignals, measurementHostIdentity, measurementDataLayerPayload, attributionContext, campaignKeys, measurementConsent, measurementPageLocation, measurementId, measurementNamespace, sameMeasurementManifest} from '../../../web_client/src/components/forms/form_measurement_contract.js';

const config = JSON.parse(document.getElementById('measurement-config').textContent);
let instance;
let generation;
let context;
let pageContext = null;
let consent;
const consentContext = () => ({...context, festapp_consent:{...consent}});
window.dataLayer = [];

// Consent commands must be Arguments objects, as in Google's gtag snippet;
// the tag library ignores a plain array.
function gtag() { dataLayer.push(arguments); }
const consentState = ({analytics, marketing}) => {
    const ads = marketing ? 'granted' : 'denied';
    // Explicit values for every Consent Mode type: unset types count as granted
    // in GTM. The owner keeps functionality and security storage granted;
    // personalization follows the marketing choice.
    return {analytics_storage:analytics ? 'granted' : 'denied',ad_storage:ads,ad_user_data:ads,ad_personalization:ads,
        functionality_storage:'granted',security_storage:'granted',personalization_storage:ads};
};

const identityName = name => /^_ga(?:_|$)/.test(name) || /^_gcl_/.test(name) || ['_fbp','_fbc'].includes(name);
let copiedCookies = new Set();
function cookiePairs() {
    try { return document.cookie.split(';').map(p => { const i=p.indexOf('='); return [p.slice(0,i).trim(),p.slice(i+1)]; }); }
    catch { return []; }
}
function deleteCookie(name) {
    // Old gtag cookies and CHIPS copies can coexist in all four variants.
    const paths = new Set(['/', location.pathname]);
    for (let i=location.pathname.indexOf('/',1);i>=0;i=location.pathname.indexOf('/',i+1))paths.add(location.pathname.slice(0,i));
    for (const path of paths) for (const domain of ['', '; Domain=' + location.hostname]) for (const partition of ['', '; Partitioned']) {
        try { document.cookie = name + '=; Max-Age=0; Path=' + path + '; SameSite=None; Secure' + domain + partition; } catch { /* Best effort. */ }
    }
    copiedCookies.delete(name);
}
function cookieAge(name, value) {
    if (name.startsWith('_ga')) return 63072000;
    const match = name.startsWith('_gcl_') ? /^GCL\.(\d+)\./.exec(value) : name === '_fbc' ? /^fb\.\d+\.(\d+)\./.exec(value) : null;
    const timestamp = match ? Number(match[1]) / (name === '_fbc' ? 1000 : 1) : NaN;
    return Number.isFinite(timestamp) ? Math.max(0, Math.min(7776000, Math.floor(timestamp + 7776000 - Date.now()/1000))) : 7776000;
}
function applyHostIdentity(input) {
    const identity = measurementHostIdentity(context?.form_embedded ? input : null, consent);
    // GA1.<n>.<a>.<b>: the domain-level prefix may differ (GA1.1 vs GA1.2) for the
    // same client; only a different <a>.<b> client ID means a different visitor.
    const clientId = value => /^GA\d+\.\d+\.(\d+\.\d+)$/.exec(value || '')?.[1] ?? value;
    const clientChanged = identity._ga && cookiePairs().filter(([name])=>name==='_ga').some(([,value])=>clientId(value)!==clientId(identity._ga));
    if (identity._ga && context.page_referrer) {
        delete context.page_referrer;
        if(instance)dataLayer.push({page_referrer:null});
    }
    if (!consent.marketing) {
        try {for (const key of Object.keys(localStorage))if(key.startsWith('_gcl_'))localStorage.removeItem(key);} catch { /* Storage can be blocked. */ }
    }
    const names = new Set([...copiedCookies, ...cookiePairs().map(([name])=>name).filter(identityName)]);
    for (const name of names) {
        const allowed = name.startsWith('_ga') ? consent.analytics : consent.marketing;
        if (!allowed || (clientChanged && consent.analytics && name.startsWith('_ga_') && !identity[name])) deleteCookie(name);
    }
    for (const [name,value] of Object.entries(identity)) {
        deleteCookie(name);
        try {
            document.cookie = name + '=' + value + '; Max-Age=' + cookieAge(name,value) + '; Domain=' + location.hostname + '; Path=/; SameSite=None; Secure; Partitioned';
            copiedCookies.add(name);
            const values = cookiePairs().filter(([key])=>key===name).map(([,v])=>v);
            if (name === '_ga' && (values.length !== 1 || values[0] !== value)) setClientId(value);
        } catch { if (name === '_ga') setClientId(value); }
    }
    // gtag has no documented reset for a global client_id. On revocation we
    // delete cookies only; already loaded tags may retain their in-memory ID.
}
function setClientId(value) {
    const match = /^GA1\.\d+\.(\d+)\.(\d+)$/.exec(value);
    if (match) gtag('set', {client_id:match[1]+'.'+match[2]});
}
function updateSignals(input) {
    const url = new URL(location.href);
    url.searchParams.delete('_gl');
    for (const key of campaignKeys) {
        url.searchParams.delete(key);
        if(context[key] && (key.startsWith('utm_') || consent.marketing))url.searchParams.set(key,context[key]);
    }
    if (!context.form_embedded) for (const [key,value] of Object.entries(measurementSignals(input))) {
        if (key !== '_gl' || consent.analytics && consent.marketing) url.searchParams.set(key,value);
    }
    history.replaceState(null, '', url);
}
function push(input) {
    const payload = measurementDataLayerPayload(input, {embedded: context.form_embedded, pageContext});
    if (!payload) return;
    if (!payload.event) pageContext = payload;
    if (payload.ecommerce || payload.event === 'generate_lead') dataLayer.push({ecommerce:null,user_data:null});
    dataLayer.push({...consentContext(),...payload});
    if (['purchase','generate_lead'].includes(payload.event)) dataLayer.push({user_data:null});
}
function reply(type) {
    parent.postMessage({namespace:measurementNamespace,protocol:measurementProtocol,type,instance,generation,manifest:config.manifest},config.parent_origin);
}
window.addEventListener('message', event => {
    const message = event.data;
    if (event.source !== parent || event.origin !== config.parent_origin || message?.namespace !== measurementNamespace ||
        message.protocol !== measurementProtocol || !sameMeasurementManifest(message.manifest,config.manifest) || !measurementId(message.instance)) return;
    if (message.type === 'init' && !instance) {
        consent = measurementConsent(message.consent);
        if(!Number.isSafeInteger(message.generation))return;
        generation=message.generation;
        context = attributionContext(message.context);
        if (!context || new URL(context.page_location).origin !== config.parent_origin ||
            new URL(context.page_location).pathname.replace(/\/$/,'') !== '/form/' + config.form_link) return;
        context.page_location = measurementPageLocation(context);
        // Ads and Meta tags read click IDs from this document's URL, not from dataLayer.
        gtag('consent','default',consentState(consent));
        applyHostIdentity(message.hostIdentity);
        updateSignals(message.context);
        // Every event carries the purposes for tags and Unit scripts that do not
        // read Consent Mode, which is the only consent check in this frame.
        instance = message.instance;
        // Queued before gtm.js exists, so the container reads it first. The update
        // keeps the saved choice when a container template sets its own default.
        gtag('consent','update',consentState(consent));
        gtag('set','ads_data_redaction',true);
        // This profile runs on a separate site inside the public form. Google's
        // default SameSite cookie setting prevents collection in that context.
        gtag('set',{cookie_flags:'SameSite=None;Secure;Partitioned'});
        dataLayer.push(consentContext());
        if (config.gtm_container) {
            dataLayer.push({'gtm.start':Date.now(),event:'gtm.js'});
            const script = document.createElement('script');
            script.src = 'https://www.googletagmanager.com/gtm.js?id=' + config.gtm_container;
            document.head.append(script);
        }
        if (config.scripts) {
            const parsed = new DOMParser().parseFromString(config.scripts,'text/html');
            const source = parsed.querySelectorAll('script');
            if (source.length) {
                for (const original of source) {
                    const script = document.createElement('script');
                    if (original.hasAttribute('src')) script.src = original.getAttribute('src');
                    else script.textContent = original.textContent;
                    document.head.append(script);
                }
            } else {
                const script = document.createElement('script');
                script.textContent = config.scripts; document.head.append(script);
            }
        }
        reply('ack');
    } else if (message.type === 'consent' && message.instance === instance && message.generation === generation) {
        const next = measurementConsent(message.consent);
        const changed = next.analytics !== consent.analytics || next.marketing !== consent.marketing;
        consent = next;
        applyHostIdentity(message.hostIdentity);
        updateSignals(message.signals);
        if (!changed) return;
        gtag('consent','update',consentState(consent));
        gtag('set','ads_data_redaction',true);
        dataLayer.push({event:'festapp_consent_update',festapp_consent:{...consent},...consent});
    } else if (message.type === 'identity' && message.instance === instance && message.generation === generation) {
        applyHostIdentity(message.hostIdentity);
    } else if (message.type === 'event' && message.instance === instance && message.generation === generation) {
        push(message.payload);
    }
});
reply('ready');
