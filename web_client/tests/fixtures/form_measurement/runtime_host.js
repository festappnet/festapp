import {FormMeasurementRuntime} from '../../../src/components/forms/form_measurement_runtime.js';
const origin=new URLSearchParams(location.search).get('runtime');
window.observed=[]; window.executed=0;
window.addEventListener('message',e=>{if(e.origin!==origin || e.source!==runtime.frame?.contentWindow)return;if(e.data?.fixtureTag)executed++;if(Array.isArray(e.data?.fixtureMeasurement))observed.push(...e.data.fixtureMeasurement);});
window.model={link:'test',data:{analytics:{privacy_url:'https://organizer.example/privacy',eligible:true,runtime_supported:true,runtime_origin:origin,organization:1,unit:2,processing_revision:'rev-a',measurement_protocol:3,runtime_revision:1,policy_revision:1,profile:'gtm-v1',required_purposes:['analytics','marketing'],valid_for_seconds:60}}};
window.runtime=new FormMeasurementRuntime({model,local:true});
window.grant=(revision='rev-a')=>({runtimeOrigin:origin,manifest:{organization:1,unit:2,form_link:'test',processing_revision:revision,measurement_protocol:3,runtime_revision:1,policy_revision:1,profile:'gtm-v1',required_purposes:['analytics','marketing']},generation:1,consent:{analytics:true,marketing:true},expiresAt:Date.now()+60000,onReady:()=>{window.ready=true},onMismatch:()=>{window.mismatch=true}});
window.event=name=>runtime.track(name==='page_view'?{event:name,email:'secret@example.com'}:{event:name,ecommerce:{currency:'CZK',items:[{item_id:'product_1',item_name:'Ticket',price:100,quantity:1,email:'secret@example.com'}],payment_type:'card',transaction_id:'12345678-1234-4234-8234-123456789abc'},user_data:{email:'buyer@example.com',phone_number:'+420601234567',first_name:'secret@example.com'}});
if(new URLSearchParams(location.search).has('cmp')) {
 const {LocalizationService}=await import('../../../src/services/localization_service.js');
 const params=new URLSearchParams(location.search);await LocalizationService.init({locale:params.get('lang')||'cs',persist:false});
 const {startMeasurementConsent}=await import('../../../src/components/forms/form_measurement_cmp.js');
 model.data.analytics.privacy_url=params.get('privacy')??'https://organizer.example/privacy';
 window.choices=[];window.cleanupCmp=startMeasurementConsent({model,setConsent:value=>choices.push(value),host:document.body});
}
