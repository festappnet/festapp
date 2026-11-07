import {FormMeasurementRuntime} from '../../../src/components/forms/form_measurement_runtime.js';
window.marker='checkout-intact';window.receipts=[];window.attacks=[];
const p={privacy_url:"https://organizer.example/privacy",eligible:true,runtime_origin:window.fixtureRuntime,organization:1,unit:2,valid_for_seconds:60,processing_revision:'rev-a',runtime_revision:1,policy_revision:1,profile:'gtm-v1',required_purposes:['analytics','marketing']};
const model=link=>({link,data:{analytics:{...p}}});
window.contextSafe=true;window.a=new FormMeasurementRuntime({model:model('test'),local:true,canRun:()=>window.contextSafe});window.b=new FormMeasurementRuntime({model:model('other'),local:true});
window.addEventListener('message',e=>{if(e.origin!==window.fixtureRuntime)return;const owner=[a,b].find(r=>r.frame?.contentWindow===e.source);if(!owner)return;if(e.data?.receipt) receipts.push({owner:owner===a?'a':'b',...e.data.receipt});if(e.data?.attack)attacks.push({owner:owner===a?'a':'b',...e.data.attack});});

window.startRuntime=(runtime, expiresAt=Date.now()+60000)=>runtime.start({manifest:{organization:1,unit:2,form_link:runtime.model.link,processing_revision:'rev-a',runtime_revision:1,policy_revision:1,profile:'gtm-v1',required_purposes:['analytics','marketing']},generation:1,consent:{analytics:true,marketing:true},expiresAt,onReady:()=>{},onMismatch:()=>{}});
