import {writeFileSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const p=(key,value,type='TEMPLATE')=>({type,key,value:String(value)});
const ref=name=>'{{'+name+'}}';
const folderId='1';
const withFolder=value=>({...value,parentFolderId:folderId});
const contextNames=['page_type','user_type','language'];
const leadNames=['currency','value','lead_source','event_id'];
// One destination specification, not another runtime event producer/validator.
const events=[
 {name:'form_page_view'}, {name:'form_start'}, {name:'form_submit_error'},
 {name:'view_item',ecommerce:true,meta:'ViewContent'},
 {name:'add_to_cart',ecommerce:true,meta:'AddToCart'},
 {name:'remove_from_cart',ecommerce:true},
 {name:'begin_checkout',ecommerce:true,meta:'InitiateCheckout'},
 {name:'add_payment_info',ecommerce:true,meta:'AddPaymentInfo'},
 {name:'purchase',ecommerce:true,contact:true,meta:'Purchase'},
 {name:'generate_lead',contact:true,meta:'Lead'},
];
const variables=[];
const variable=(name,type,parameter)=>{
 variables.push(withFolder({variableId:String(variables.length+1),name,type,parameter}));return name;
};
const dl=path=>'dl.'+path;
for(const path of ['form_embedded','ecommerce.value','ecommerce.currency','ecommerce.transaction_id','ecommerce.items',
 'user_data.email','user_data.phone_number',...contextNames,...leadNames]) {
 variable(dl(path),'v',[p('dataLayerVersion',2,'INTEGER'),p('setDefaultValue',false,'BOOLEAN'),p('name',path)]);
}
const constants={
 ga4:variable('GA4 ID - Festapp','c',[p('value','G-REPLACE0000')]),
 ads:variable('GAds ID - Festapp','c',[p('value','000000000')]),
 purchase:variable('GAds label - Festapp - Nákup vstupenek','c',[p('value','REPLACE_PURCHASE_LABEL')]),
 registration:variable('GAds label - Festapp - Registrace','c',[p('value','REPLACE_REGISTRATION_LABEL')]),
 meta:variable('FB Pixel ID - Festapp','c',[p('value','000000000000000')]),
};
const js=(name,body)=>variable('cjs - Festapp - '+name,'jsm',[p('javascript','function () { '+body+' }')]);
const contactGuard=`if (${ref(dl('form_embedded'))} !== true || ['purchase','generate_lead'].indexOf(${ref('Event')}) < 0) return;`;
const email=js('email',contactGuard+` var v=${ref(dl('user_data.email'))}; if (typeof v === 'string') return v;`);
const phone=js('phone',contactGuard+` var v=${ref(dl('user_data.phone_number'))}; if (typeof v === 'string' && v.charAt(0) === '+' && /^[1-9][0-9]{7,14}$/.test(v.substring(1))) return v;`);
const metaPhone=js('Meta phone',`var v=${ref(phone)}; if (typeof v === 'string') return v.substring(1);`);
const userProvided=variable('User-Provided Data - Festapp - manual','awec',[
 p('mode','MANUAL'),p('email',ref(email)),p('phone_number',ref(phone)),
]);
const leadVariables=Object.fromEntries(leadNames.map(name=>[name,js('lead '+name,
 `if (${ref(dl('form_embedded'))} === true && ${ref('Event')} === 'generate_lead') return ${ref(dl(name))};`)]));
const ecommerceNames=events.filter(event=>event.ecommerce).map(event=>event.name);
const metaProperties=js('Meta properties',`
 if (${ref(dl('form_embedded'))} !== true) return {};
 var event=${ref('Event')}, result={};
 if (event === 'generate_lead') {
  result.currency=${ref(leadVariables.currency)}; result.value=${ref(leadVariables.value)};
 } else if (${JSON.stringify(ecommerceNames)}.indexOf(event) >= 0) {
  result.currency=${ref(dl('ecommerce.currency'))}; result.value=${ref(dl('ecommerce.value'))};
  var items=${ref(dl('ecommerce.items'))};
  if (items instanceof Array) result.contents=items.slice(0,200).map(function (item) {
   return {id:item.item_id,quantity:item.quantity,item_price:item.price};
  });
 }
 return result;`);
const equals=(name,value)=>({type:'EQUALS',parameter:[p('arg0',ref(name)),p('arg1',value)]});
const triggers=events.map((event,index)=>withFolder({triggerId:String(index+1),name:'event - Festapp - '+event.name,
 type:'CUSTOM_EVENT',customEventFilter:[equals('_event',event.name)],filter:[equals(dl('form_embedded'),'true')]}));
// A completed free registration is narrower than waitlist/opening-interest leads.
const registrationTrigger=withFolder({triggerId:String(triggers.length+1),name:'event - Festapp - generate_lead - free_registration',
 type:'CUSTOM_EVENT',customEventFilter:[equals('_event','generate_lead')],
 filter:[equals(dl('form_embedded'),'true'),equals(dl('lead_source'),'free_registration')]});
triggers.push(registrationTrigger);
const triggerFor=name=>triggers[events.findIndex(event=>event.name===name)].triggerId;
const eventParameters=entries=>({type:'LIST',key:'eventSettingsTable',list:entries.map(([name,value])=>({type:'MAP',map:[p('parameter',name),p('parameterValue',ref(value))]}))});
const googleConsent={consentStatus:'NOT_NEEDED'};
const metaConsent={consentStatus:'NEEDED',consentType:{type:'LIST',list:[{type:'TEMPLATE',value:'ad_storage'}]}};
const tags=[];
const tag=(name,type,parameter,firingTriggerId,consentSettings)=>tags.push(withFolder({tagId:String(tags.length+1),name,type,
 parameter,firingTriggerId,tagFiringOption:'ONCE_PER_EVENT',paused:true,consentSettings}));
for(const event of events) {
 const parameters=contextNames.map(name=>[name,dl(name)]);
 if(event.name==='generate_lead')parameters.push(...leadNames.map(name=>[name,leadVariables[name]]));
 if(event.contact)parameters.push(['user_data',userProvided]);
 tag('GA4 - Festapp - '+event.name,'gaawe',[
  p('sendEcommerceData',!!event.ecommerce,'BOOLEAN'),
  ...(event.ecommerce?[p('getEcommerceDataFrom','dataLayer')]:[]),
  p('eventName',event.name),p('measurementIdOverride',ref(constants.ga4)),eventParameters(parameters),
 ],[triggerFor(event.name)],googleConsent);
}
for(const conversion of [
 {name:'Nákup vstupenek',label:constants.purchase,trigger:triggerFor('purchase'),id:dl('ecommerce.transaction_id'),value:dl('ecommerce.value'),currency:dl('ecommerce.currency')},
 {name:'Registrace',label:constants.registration,trigger:registrationTrigger.triggerId,id:leadVariables.event_id,value:leadVariables.value,currency:leadVariables.currency},
]) tag('GAds - Festapp - '+conversion.name,'awct',[
 p('conversionId',ref(constants.ads)),p('conversionLabel',ref(conversion.label)),p('orderId',ref(conversion.id)),
 p('conversionValue',ref(conversion.value)),p('currencyCode',ref(conversion.currency)),
 ...['enableNewCustomerReporting','enableProductReporting','enableShippingData','rdp'].map(key=>p(key,false,'BOOLEAN')),
 p('enableConversionLinker',true,'BOOLEAN'),eventParameters([['user_data',userProvided]]),
],[conversion.trigger],googleConsent);

const metaTemplate=JSON.parse(readFileSync(new URL('./meta-pixel-template.json',import.meta.url),'utf8'));
for(const event of events.filter(event=>event.meta)) {
 const matching=event.contact?[{type:'MAP',map:[p('name','em'),p('value',ref(email))]},
  {type:'MAP',map:[p('name','ph'),p('value',ref(metaPhone))]}]:[];
 tag('Meta Pixel - Festapp - '+event.meta,'cvt_0_1',[
  p('pixelId',ref(constants.meta)),p('eventName','standard'),p('standardEventName',event.meta),
  p('consent',true,'BOOLEAN'),p('optInMetaCAPI',false,'BOOLEAN'),
  p('advancedMatching',!!event.contact,'BOOLEAN'),
  ...(event.contact?[{type:'LIST',key:'advancedMatchingList',list:matching}]:[]),
  p('enhancedEcommerce',false,'BOOLEAN'),p('useGA4Ecommerce',false,'BOOLEAN'),
  p('objectPropertiesFromVariable',ref(metaProperties)),
 ],[triggerFor(event.name)],metaConsent);
}
export const preset={exportFormatVersion:2,exportTime:'2026-11-11 00:00:00',containerVersion:{
 name:'Festapp website measurement - paused setup preset',accountId:'0',containerId:'0',containerVersionId:'0',
 container:{accountId:'0',containerId:'0',name:'Festapp host preset',usageContext:['WEB']},
 tag:tags,trigger:triggers,variable:variables,folder:[{folderId,name:'Festapp'}],
 customTemplate:[metaTemplate],builtInVariable:[{type:'EVENT',name:'Event'}],
}};
const output=fileURLToPath(new URL('./festapp-host-gtm.json',import.meta.url));
const serialized=JSON.stringify(preset,null,2)+'\n';
if(process.argv[1]===fileURLToPath(import.meta.url)) {
 if(process.argv.includes('--check')) {if(readFileSync(output,'utf8')!==serialized)throw Error('Rebuild GTM preset');}
 else writeFileSync(output,serialized);
}
