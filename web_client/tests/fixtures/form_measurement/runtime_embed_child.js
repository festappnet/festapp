import {EmbedBridge} from '../../../src/services/embed_bridge.js';
import {FormDataLayer} from '../../../src/components/forms/form_datalayer.js';
import {FormMeasurementRuntime} from '../../../src/components/forms/form_measurement_runtime.js';
const policy={enabled:true,organization_allowed:true,runtime_supported:true,privacy_url:"https://organizer.example/privacy",eligible:true,valid_for_seconds:60,organization:1,unit:2,runtime_origin:window.fixtureRuntime};
const model={link:'test',data:{analytics:policy},visibleFields:[]};
const bridge=new EmbedBridge(); bridge.start();
const runtime=new FormMeasurementRuntime({model,local:true,campaign:()=>bridge.measurementCampaign || {}}); bridge.setMeasurementRuntime(runtime);
const layer=new FormDataLayer({model,bridge,entryAllowed:true,session:()=>false});
window.addEventListener('message',e=>{
 if(e.origin===window.fixtureRuntime && e.source===runtime.frame?.contentWindow && e.data?.nestedReceipt) parent.postMessage(e.data,window.fixtureHost);
 if(e.source!==parent || e.origin!==window.fixtureHost || !e.data?.testCall)return;
 const {id,action}=e.data; let result;
 if(action==='state') result={allowed:bridge.measurementAllowed(),ready:runtime.ready===true,hasFrame:!!runtime.frame,instance:runtime.instance,consent:runtime.consent};
 if(action==='view') result=layer.view();
 parent.postMessage({testReply:true,id,result},window.fixtureHost);
});
parent.postMessage({testReady:true},window.fixtureHost);
