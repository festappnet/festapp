import {analyticsPayload, attributionContext, measurementId, measurementNamespace} from '../../../web_client/src/components/forms/form_measurement_contract.js';

const config = JSON.parse(document.getElementById('measurement-config').textContent);
let instance;
let context;
window.dataLayer = [];

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
        context = attributionContext(message.context);
        if (!context || new URL(context.page_location).origin !== config.parent_origin ||
            new URL(context.page_location).pathname.replace(/\/$/,'') !== '/form/' + config.form_link) return;
        instance = message.instance;
        dataLayer.push(context);
        // This profile requires the supplied GTM Consent Initialization template.
        // The whole document is basic-gated by saved analytics consent; Ads stay
        // denied in the template, and revoke destroys this browsing context.
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
    } else if (message.type === 'event' && message.instance === instance) {
        const payload = analyticsPayload(message.payload);
        if (payload) push(payload);
    }
});
reply('ready');
