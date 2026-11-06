import {FormMeasurementRuntime} from '../../../src/components/forms/form_measurement_runtime.js';
const origin = new URLSearchParams(location.search).get('runtime');
window.consentReceipts=[];window.addEventListener('message',e=>{if(e.origin===origin && e.source===runtime.frame?.contentWindow && e.data?.fixtureConsent)window.consentReceipts.push(e.data.fixtureConsent)});
window.gtmReceipts=[]; window.addEventListener('message',e=>{if(e.origin===origin && e.source===runtime.frame?.contentWindow && e.data?.namespace==='festapp-test-gtm') window.gtmReceipts.push(e.data)});
window.diagnostics=[];window.addEventListener('message',e=>{if(e.origin===origin && (e.data?.fixtureViolation || e.data?.fixtureScript || 'fixtureGtm' in (e.data||{}))) window.diagnostics.push(e.data)});
window.observed=[]; window.addEventListener('message',e=>{if(e.origin===origin && Array.isArray(e.data?.fixtureMeasurement)) window.observed.push(...e.data.fixtureMeasurement);});
window.model = {link:'test',data:{analytics:{eligible:true,runtime_supported:true,runtime_origin:origin,organization:1,unit:2,configuration_revision:1,policy_revision:1,valid_for_seconds:60}}};
window.runtime = new FormMeasurementRuntime({model,local:true,onReady:()=>{window.ready=true;}});
window.event = (name) => runtime.track(name === 'page_view' ? {event:name,email:'secret@example.com'} : {event:name,ecommerce:{currency:'CZK',items:[{item_id:'product_1',item_name:'Ticket',price:100,quantity:1,email:'secret@example.com'}],...(name==='purchase'?{payment_type:'card',transaction_id:'12345678-1234-4234-8234-123456789abc'}:{})}});
if (new URLSearchParams(location.search).has('cmp')) {
    const {LocalizationService} = await import('../../../src/services/localization_service.js');
    await LocalizationService.init({locale:'cs',persist:false});
    const {startMeasurementConsent} = await import('../../../src/components/forms/form_measurement_cmp.js');
    window.cleanupCmp = startMeasurementConsent({model,transport:runtime,host:document.body});
}
