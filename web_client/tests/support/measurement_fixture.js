import {JSDOM} from 'jsdom';
import {FormMeasurementSession} from '../../src/components/forms/form_measurement_session.js';
import {FormDataLayer} from '../../src/components/forms/form_datalayer.js';
import {analyticsPayload} from '../../src/components/forms/form_measurement_contract.js';
export const policy={measurement_protocol:3,enabled:true,organization_allowed:true,runtime_supported:true,eligible:true,organization:1,unit:2,
 form_link:'summer',runtime_origin:'https://unit-measurement.pages.dev',privacy_url:'https://organizer.example/privacy',
 processing_revision:'processing-a',runtime_revision:1,policy_revision:1,profile:'gtm-v1',required_purposes:['analytics','marketing'],valid_for_seconds:60,visitor_role:'anonymous'};
export const settle=()=>new Promise(resolve=>setImmediate(resolve));
export const purchase={event:'purchase',ecommerce:{currency:'CZK',transaction_id:'c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44',payment_type:'bank_transfer',items:[{item_id:'product_11',item_name:'Concert',price:100,quantity:2}]}};
export function fixture(t,{source=async()=>({...policy}),identity='anonymous',consent={analytics:true,marketing:true},url='https://tickets.test/form/summer',autoReady=true,modelData={},clock}={}) {
 const dom=new JSDOM('<html lang="cs"><body></body></html>',{url,pretendToBeVisual:true});
 let currentIdentity=identity,notifyIdentity,notifyConsent,deliver=true;const sent=[],starts=[];
 const transport={activate(grant){this.grant=grant;starts.push(grant);if(autoReady)grant.onReady();},stop(){this.grant=null;},renew(){},
  track(p){if(!deliver)return false;sent.push(analyticsPayload(p));return true;}};
 const model={link:'summer',occasionTitle:'Letní fest',data:{analytics:{...policy},...modelData},visibleFields:[
  {id:4,type:'product_type',productTypeData:{title:'Vstupenky'},options:[{id:11,title:'Concert',price:100,currency:'CZK'},{id:12,title:'Free',price:0,currency:'CZK'}]},
  {id:5,type:'email'},{id:6,type:'phone'}]};
 const checkout={payload:{fields:[]}};let session;
 const layer=new FormDataLayer({win:dom.window,model,sink:{record:p=>session.record(p),capture:()=>session.capture()}});
 session=new FormMeasurementSession({win:dom.window,model,transport,policySource:source,clock,
  identitySource:{read:()=>currentIdentity,subscribe:fn=>{notifyIdentity=fn;return ()=>notifyIdentity=null;}},
  consentSource:{connect(_policy,notify){notifyConsent=notify;notify(consent);return ()=>{notifyConsent=null;};}},
  onActive:()=>layer.activate(checkout)});
 t?.after(()=>{session.dispose();layer.dispose();dom.window.close();});
 return {dom,model,session,layer,transport,sent,starts,checkout,
  choose(value){consent=value;notifyConsent?.(value);},identity(value){currentIdentity=value;notifyIdentity?.();},
  delivery(value){deliver=value;},start:async()=>{session.start();await settle();}};
}
