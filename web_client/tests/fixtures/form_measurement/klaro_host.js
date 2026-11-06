// Test-only integration: actual Klaro manager, production embed API, no GA/Ads destination.
window.dataLayer = window.dataLayer || [];
window.gtag = function () { window.dataLayer.push(arguments); };
const denied = {analytics_storage:'denied',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied'};
gtag('consent','default',denied);
window.klaroConfig = {
    version:1, noAutoLoad:true, lang:'en', storageMethod:'cookie', storageName:'festapp-cmp-test',
    services:[{name:'analytics',title:'Integration test analytics',purposes:['analytics'],default:false,required:false}],
};
window.cmpFailure = null;
window.cmpGtmState = 'not-requested';
try {
    if (location.search.includes('storage=denied')) {
        Object.defineProperty(document,'cookie',{get(){throw Error('storage denied')},set(){throw Error('storage denied')}});
    }
    const manager = window.cmpManager = klaro.getManager(klaroConfig);
    let granted = false;
    const sync = () => {
        const next = manager.confirmed === true && manager.savedConsents.analytics === true && manager.getConsent('analytics') === true;
        if (next === granted) return;
        granted = next;
        gtag('consent','update',{...denied,analytics_storage:next?'granted':'denied'});
        FestappEmbed.setMeasurementConsent(document.querySelector('iframe'),next);
        if (next && location.search.includes('live-gtm=1') && cmpGtmState === 'not-requested') {
            cmpGtmState = 'loading';
            dataLayer.push({'gtm.start':Date.now(),event:'gtm.js'});
            const script = document.createElement('script');
            script.src = 'https://www.googletagmanager.com/gtm.js?id=GTM-W9WRHWT9';
            script.onload = () => {cmpGtmState='loaded'};
            script.onerror = () => {cmpGtmState='blocked'};
            document.head.append(script);
        }
    };
    manager.watch({update:sync});
    sync();
    window.cmpChoose = choice => {manager.updateConsent('analytics',choice);manager.saveAndApplyConsents()};
} catch (error) {
    window.cmpFailure = error.message;
    FestappEmbed.setMeasurementConsent(document.querySelector('iframe'),false);
}
