import {writeFileSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const p=(key,value,type='TEMPLATE')=>({type,key,value:String(value)});
const ref=name=>'{{'+name+'}}';
const consent=(...types)=>({consentStatus:'NEEDED',consentType:{type:'LIST',list:types.map(value=>({type:'TEMPLATE',value}))}});
const events=['form_page_view','form_start','form_submit_error','view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','purchase','generate_lead'];
const variables=['form_embedded','ecommerce','ecommerce.value','ecommerce.currency','ecommerce.transaction_id','user_data','page_type','user_type','language','currency','value','lead_source','event_id'].map((name,i)=>({variableId:String(i+1),name:'Festapp '+name,type:'v',parameter:[p('dataLayerVersion',2,'INTEGER'),p('setDefaultValue',false,'BOOLEAN'),p('name',name)]}));
variables.push({variableId:'30',name:'Festapp user provided data',type:'awec',parameter:[p('mode','CODE'),p('dataSource',ref('Festapp user_data'))]});
for (const name of ['currency','value','lead_source','event_id']) variables.push({variableId:String(40+variables.length),name:'Festapp lead '+name,type:'jsm',parameter:[p('javascript',`function () { if ({{Event}} === 'generate_lead') return {{Festapp ${name}}}; }`)]});
const eventParameters=names=>({type:'LIST',key:'eventSettingsTable',list:names.map(([name,variable])=>({type:'MAP',map:[p('parameter',name),p('parameterValue',ref(variable))]}))});
const contextParameters=['page_type','user_type','language'].map(name=>[name,'Festapp '+name]);
const leadParameters=['currency','value','lead_source','event_id'].map(name=>[name,'Festapp lead '+name]);
const filter=(variable,value)=>({type:'EQUALS',parameter:[p('arg0',ref(variable)),p('arg1',value)]});
const triggers=events.map((event,i)=>({triggerId:String(i+1),name:'Festapp host '+event,type:'CUSTOM_EVENT',customEventFilter:[filter('_event',event)],filter:[filter('Festapp form_embedded','true')]}));
// Use only the site's already initialized pixel. No contact data, loader, DOM
// lookup, automatic advanced matching or account settings are installed here.
export const metaHtml=`<script>
(function () {
  if (typeof window.fbq !== 'function') return;
  var event = {{Event}}, ecommerce = {{Festapp ecommerce}};
  if (['view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','purchase'].indexOf(event) < 0) ecommerce = null;
  var names = {purchase:'Purchase',begin_checkout:'InitiateCheckout',add_to_cart:'AddToCart',view_item:'ViewContent',generate_lead:'Lead'};
  var data = {}, options = {}, items = ecommerce && ecommerce.items;
  if (ecommerce && typeof ecommerce.currency === 'string' && /^[A-Z]{3}$/.test(ecommerce.currency)) data.currency = ecommerce.currency;
  if (ecommerce && typeof ecommerce.value === 'number' && isFinite(ecommerce.value)) data.value = ecommerce.value;
  if (items instanceof Array) data.contents = items.slice(0,200).map(function (item) {
    return {id:String(item.item_id).slice(0,80),quantity:Number(item.quantity),item_price:Number(item.price)};
  });
  if (event === 'purchase' && ecommerce && typeof ecommerce.transaction_id === 'string') options.eventID = ecommerce.transaction_id;
  if (event === 'generate_lead') { data.currency = {{Festapp lead currency}}; data.value = {{Festapp lead value}}; options.eventID = {{Festapp lead event_id}}; }
  if (names[event]) window.fbq('track',names[event],data,options);
  else window.fbq('trackCustom','Festapp_' + event,data);
})();
</script>`;
const ecommerceEvents=['view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','purchase'];
const triggerIds=ecommerce=>triggers.filter(t=>ecommerceEvents.includes(t.customEventFilter[0].parameter[1].value)===ecommerce).map(t=>t.triggerId);
const tag=(id,name,type,parameter,triggerIds,consentSettings)=>({tagId:id,name,type,parameter,firingTriggerId:triggerIds,tagFiringOption:'ONCE_PER_EVENT',paused:true,consentSettings});
export const preset={exportFormatVersion:2,exportTime:'2026-11-10 00:00:00',containerVersion:{
 name:'Festapp first-party host measurement - paused setup preset',
 accountId:'0',containerId:'0',containerVersionId:'0',container:{accountId:'0',containerId:'0',name:'Festapp host preset',usageContext:['WEB']},
 tag:[
 tag('1','Festapp GA4 ecommerce - CONFIGURE AND UNPAUSE','gaawe',[
 p('sendEcommerceData',true,'BOOLEAN'),p('getEcommerceDataFrom','dataLayer'),p('eventName',ref('Event')),p('measurementIdOverride','G-REPLACE0000'),eventParameters(contextParameters)
 ],triggerIds(true),consent('analytics_storage')),
 tag('4','Festapp GA4 form events - CONFIGURE AND UNPAUSE','gaawe',[p('sendEcommerceData',false,'BOOLEAN'),p('eventName',ref('Event')),p('measurementIdOverride','G-REPLACE0000'),eventParameters([...contextParameters,...leadParameters])],triggerIds(false),consent('analytics_storage')),
 tag('2','Festapp Ads purchase - CONFIGURE AND UNPAUSE','awct',[
 p('conversionId','000000000'),p('conversionLabel','REPLACE_CONVERSION_LABEL'),p('orderId',ref('Festapp ecommerce.transaction_id')),p('conversionValue',ref('Festapp ecommerce.value')),p('currencyCode',ref('Festapp ecommerce.currency')),
 ...['enableNewCustomerReporting','enableProductReporting','enableShippingData','rdp'].map(k=>p(k,false,'BOOLEAN')),p('enableConversionLinker',true,'BOOLEAN'),
 {type:'LIST',key:'eventSettingsTable',list:[{type:'MAP',map:[p('parameter','user_data'),p('parameterValue',ref('Festapp user provided data'))]}]}
 ],[triggers.find(t=>t.name.endsWith(' purchase')).triggerId],consent('ad_storage','ad_user_data','ad_personalization')),
 tag('3','Festapp Meta public events - INITIALIZE PIXEL AND UNPAUSE','html',[p('html',metaHtml),p('supportDocumentWrite',false,'BOOLEAN')],triggers.map(t=>t.triggerId),consent('ad_storage','ad_user_data','ad_personalization')),
 ],trigger:triggers,variable:variables,builtInVariable:[{type:'EVENT',name:'Event'}]}};
const output=fileURLToPath(new URL('./festapp-host-gtm.json',import.meta.url));
const serialized=JSON.stringify(preset,null,2)+'\n';
if(process.argv[1] === fileURLToPath(import.meta.url)) {
if(process.argv.includes('--check')) {if(readFileSync(output,'utf8')!==serialized) throw Error('Rebuild GTM preset');}
else writeFileSync(output,serialized);

}
