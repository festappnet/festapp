import {FormMeasurementRuntime} from '../../../src/components/forms/form_measurement_runtime.js';
window.marker='checkout-intact';window.receipts=[];window.attacks=[];
const p={privacy_url:"https://organizer.example/privacy",eligible:true,runtime_origin:window.fixtureRuntime,organization:1,unit:2,valid_for_seconds:60};
const model=link=>({link,data:{analytics:{...p}}});
window.contextSafe=true;window.a=new FormMeasurementRuntime({model:model('test'),local:true,canRun:()=>window.contextSafe});window.b=new FormMeasurementRuntime({model:model('other'),local:true});
window.addEventListener('message',e=>{if(e.origin!==window.fixtureRuntime)return;const owner=[a,b].find(r=>r.frame?.contentWindow===e.source);if(!owner)return;if(e.data?.receipt) receipts.push({owner:owner===a?'a':'b',...e.data.receipt});if(e.data?.attack)attacks.push({owner:owner===a?'a':'b',...e.data.attack});});
