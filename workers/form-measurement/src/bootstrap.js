import {analyticsPayload, attributionContext, campaignKeys, measurementConsent, measurementPageLocation, measurementId, measurementNamespace} from '../../../web_client/src/components/forms/form_measurement_contract.js';

const config = JSON.parse(document.getElementById('measurement-config').textContent);
let instance;
let context;
window.dataLayer = [];

// Consent commands must be Arguments objects, as in Google's gtag snippet;
// the tag library ignores a plain array.
function gtag() { dataLayer.push(arguments); }
const consentState = ({analytics, marketing}) => {
    const ads = marketing ? 'granted' : 'denied';
    return {analytics_storage:analytics ? 'granted' : 'denied',ad_storage:ads,ad_user_data:ads,ad_personalization:ads};
};

function push(payload) {
    if (payload.ecommerce || payload.event === 'generate_lead') dataLayer.push({ecommerce:null,user_data:null});
    dataLayer.push({...context,...payload});
    if (['purchase','generate_lead'].includes(payload.event)) dataLayer.push({user_data:null});
}
function reply(type) {
    parent.postMessage({namespace:measurementNamespace,protocol:1,type,instance},config.parent_origin);
}
window.addEventListener('message', event => {
    const message = event.data;
    if (event.source !== parent || event.origin !== config.parent_origin || message?.namespace !== measurementNamespace ||
        message.protocol !== 1 || !measurementId(message.instance)) return;
    if (message.type === 'init' && !instance) {
        const consent = measurementConsent(message.consent);
        context = attributionContext(message.context);
        if (!context || new URL(context.page_location).origin !== config.parent_origin ||
            new URL(context.page_location).pathname.replace(/\/$/,'') !== '/form/' + config.form_link) return;
        context.page_location = measurementPageLocation(context);
        // Ads and Meta tags read click IDs from this document's URL, not from dataLayer.
        const frameUrl = new URL(location.href);
        for (const key of campaignKeys) if (context[key]) frameUrl.searchParams.set(key, context[key]);
        history.replaceState(null, '', frameUrl);
        // Every event carries the purposes for tags and Unit scripts that do not
        // read Consent Mode, which is the only consent check in this frame.
        context.festapp_consent = {...consent};
        instance = message.instance;
        // Queued before gtm.js exists, so the container reads it first. The update
        // keeps the saved choice when a container template sets its own default.
        gtag('consent','default',consentState(consent));
        gtag('consent','update',consentState(consent));
        dataLayer.push(context);
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
    } else if (message.type === 'consent' && message.instance === instance) {
        const consent = measurementConsent(message.consent);
        context.festapp_consent = {...consent};
        gtag('consent','update',consentState(consent));
        dataLayer.push({event:'festapp_consent_update',...consent});
    } else if (message.type === 'event' && message.instance === instance) {
        const payload = analyticsPayload(message.payload);
        if (payload) push(payload);
    }
});
reply('ready');
