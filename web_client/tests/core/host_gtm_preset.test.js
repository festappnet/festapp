import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {preset} from '../../../integrations/measurement/build_gtm_preset.mjs';
const root=new URL('../../../',import.meta.url),cv=preset.containerVersion;
const parameters=object=>Object.fromEntries((object.parameter??[]).map(entry=>[entry.key,entry]));
const simple=object=>Object.fromEntries((object.parameter??[]).filter(entry=>'value'in entry).map(entry=>[entry.key,entry.type==='BOOLEAN'?entry.value==='true':entry.value]));
const eventNames=['form_page_view','form_start','form_submit_error','view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','purchase','generate_lead'];
const ecommerceEvents=['view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','purchase'];
const contactEvents=['purchase','generate_lead'];
const clean=value=>JSON.parse(JSON.stringify(value));
const get=(object,path)=>path.split('.').reduce((value,key)=>value?.[key],object);

// Resolve generated GTM variables against an event snapshot. Actual GTM import
// and native consent/SDK behavior are validated separately, never assumed here.
function resolver(event,layer={},overrides={}) {
 const values={Event:event,...overrides},vars=new Map(cv.variable.map(value=>[value.name,value]));
 const read=name=>{
  if(Object.hasOwn(values,name))return values[name];
  if(name==='_event')return event;
  const variable=vars.get(name);assert.ok(variable,'known reference '+name);
  const params=simple(variable);
  if(variable.type==='v')return get(layer,params.name);
  if(variable.type==='c')return params.value;
  if(variable.type==='jsm') {
   const source=params.javascript.replace(/\{\{([^}]+)\}\}/g,(_,key)=>JSON.stringify(read(key))??'undefined');
   return vm.runInNewContext('('+source+')()',{});
  }
  throw Error('Unsupported variable in projection test '+variable.type);
 };
 return read;
}
const triggerMatches=(trigger,event,layer)=>{
 const read=resolver(event,layer);
 return [...trigger.customEventFilter,...trigger.filter].every(filter=>{
  const args=Object.fromEntries(filter.parameter.map(param=>[param.key,param.value]));
  return String(read(args.arg0.slice(2,-2)))===args.arg1;
 });
};
const conversionLayer=()=>({form_embedded:true,page_type:'confirmation',user_type:'b2c',language:'cs',
 ecommerce:{currency:'CZK',value:200,transaction_id:'order',items:[{item_id:'product_1',quantity:2,price:100,email:'never-export'}]},
 user_data:{email:'buyer@example.test',phone_number:'+420777123456'},currency:'CZK',value:0,lead_source:'free_registration',event_id:'lead-id'});

test('paused import owns one folder, constants, valid references and scoped event triggers',()=>{
 assert.equal(cv.tag.length,18);assert.ok(cv.tag.every(tag=>tag.paused));
 assert.deepEqual(cv.folder,[{folderId:'1',name:'Festapp'}]);
 for(const item of [...cv.tag,...cv.trigger,...cv.variable])assert.equal(item.parentFolderId,'1');
 for(const trigger of cv.trigger){assert.equal(trigger.type,'CUSTOM_EVENT');assert.equal(triggerMatches(trigger,'purchase',{form_embedded:false}),false);}
 assert.ok(cv.tag.every(tag=>tag.firingTriggerId.every(id=>cv.trigger.some(trigger=>trigger.triggerId===id))));
 const names=new Set([...cv.variable.map(variable=>variable.name),'Event','_event']);
 const config=JSON.stringify({tags:cv.tag,triggers:cv.trigger,variables:cv.variable});
 for(const [,name]of config.matchAll(/\{\{([^}]+)\}\}/g))assert.ok(names.has(name),name);
 assert.equal(cv.variable.filter(variable=>variable.type==='c').length,5);
 for(const tag of cv.tag){const p=simple(tag);for(const key of ['measurementIdOverride','conversionId','conversionLabel','pixelId'])if(p[key])assert.match(p[key],/^\{\{.+\}\}$/);}
 assert.ok(cv.tag.every(tag=>tag.type!=='html'));
 assert.doesNotMatch(JSON.stringify(preset),/GTM-W9WRHWT9|6402899907|285468732/);
 assert.deepEqual(JSON.parse(readFileSync(new URL('integrations/measurement/festapp-host-gtm.json',root),'utf8')),preset);
});
test('GA4 uses fixed per-event names and ecommerce only on ecommerce events',()=>{
 const ga=cv.tag.filter(tag=>tag.type==='gaawe');assert.equal(ga.length,10);
 assert.deepEqual(ga.map(tag=>simple(tag).eventName).sort(),[...eventNames].sort());
 for(const tag of ga){const p=simple(tag),event=p.eventName;
  assert.equal(p.sendEcommerceData,ecommerceEvents.includes(event));
  assert.equal(tag.firingTriggerId.length,1);
  const trigger=cv.trigger.find(trigger=>trigger.triggerId===tag.firingTriggerId[0]);
  assert.equal(triggerMatches(trigger,event,{form_embedded:true}),true);
  assert.equal(triggerMatches(trigger,'native_event',{form_embedded:true}),false);
 }
});
test('native Google tags use built-in consent; Meta explicitly requires ad_storage',()=>{
 for(const tag of cv.tag){
  if(['gaawe','awct'].includes(tag.type))assert.deepEqual(tag.consentSettings,{consentStatus:'NOT_NEEDED'});
  else assert.deepEqual(tag.consentSettings,{consentStatus:'NEEDED',consentType:{type:'LIST',list:[{type:'TEMPLATE',value:'ad_storage'}]}});
 }
});
test('Google contact mapping is native/manual and present only on conversion tags',()=>{
 const upd=cv.variable.find(variable=>variable.type==='awec');assert.ok(upd);assert.deepEqual(simple(upd),{mode:'MANUAL',email:'{{cjs - Festapp - email}}',phone_number:'{{cjs - Festapp - phone}}'});
 assert.doesNotMatch(JSON.stringify(upd),/dom|selector|autoDetect/i);
 for(const tag of cv.tag.filter(tag=>['gaawe','awct'].includes(tag.type))){
  const list=parameters(tag).eventSettingsTable.list;
  const hasContact=list.some(row=>row.map.some(field=>field.key==='parameter'&&field.value==='user_data'));
  assert.equal(hasContact,tag.type==='awct'||contactEvents.includes(simple(tag).eventName));
 }
});
test('Ads Registration excludes waitlist/opening-interest leads and keeps a separate action label',()=>{
 const ads=cv.tag.filter(tag=>tag.type==='awct');assert.equal(ads.length,2);
 const registration=ads.find(tag=>tag.name.endsWith('Registrace')),purchase=ads.find(tag=>tag.name.endsWith('Nákup vstupenek'));
 assert.notEqual(simple(registration).conversionLabel,simple(purchase).conversionLabel);
 const trigger=cv.trigger.find(trigger=>trigger.triggerId===registration.firingTriggerId[0]);
 for(const lead_source of ['free_registration','waitlist','sale_opening_notification'])
  assert.equal(triggerMatches(trigger,'generate_lead',{form_embedded:true,lead_source}),lead_source==='free_registration');
 assert.equal(triggerMatches(trigger,'purchase',{form_embedded:true,lead_source:'free_registration'}),false);
 const generic=cv.trigger.find(trigger=>trigger.name==='event - Festapp - generate_lead');
 for(const lead_source of ['free_registration','waitlist','sale_opening_notification'])assert.equal(triggerMatches(generic,'generate_lead',{form_embedded:true,lead_source}),true);
});
test('contact projections retain Google E.164 and transform only Meta, with event/host scoping',()=>{
 const layer=conversionLayer();
 for(const event of contactEvents){const read=resolver(event,layer);assert.equal(read('cjs - Festapp - email'),'buyer@example.test');assert.equal(read('cjs - Festapp - phone'),'+420777123456');assert.equal(read('cjs - Festapp - Meta phone'),'420777123456');}
 for(const event of eventNames.filter(event=>!contactEvents.includes(event)))assert.equal(resolver(event,layer)('cjs - Festapp - email'),undefined);
 assert.equal(resolver('purchase',{...layer,form_embedded:false})('cjs - Festapp - phone'),undefined);
 for(const phone_number of [undefined,'777123456','+not-a-number','+0123456789'])assert.equal(resolver('purchase',{...layer,user_data:{phone_number}})('cjs - Festapp - Meta phone'),undefined);
 assert.equal(layer.user_data.phone_number,'+420777123456','source is never rewritten');
});
test('Meta projection is allowlisted and generic/lead events cannot inherit ecommerce/contact',()=>{
 const layer=conversionLayer();
 assert.deepEqual(clean(resolver('purchase',layer)('cjs - Festapp - Meta properties')),{currency:'CZK',value:200,contents:[{id:'product_1',quantity:2,item_price:100}]});
 assert.deepEqual(clean(resolver('generate_lead',layer)('cjs - Festapp - Meta properties')),{currency:'CZK',value:0});
 assert.deepEqual(clean(resolver('form_start',layer)('cjs - Festapp - Meta properties')),{});
 assert.deepEqual(clean(resolver('purchase',{...layer,form_embedded:false})('cjs - Festapp - Meta properties')),{});
 assert.equal(resolver('form_start',layer)('cjs - Festapp - lead value'),undefined);
 assert.equal(resolver('generate_lead',layer)('cjs - Festapp - lead value'),0);
 assert.doesNotMatch(JSON.stringify(resolver('purchase',layer)('cjs - Festapp - Meta properties')),/email|never-export|phone/);
});
test('official Meta template keeps upstream executable/permissions and genuine gallery identity',()=>{
 const template=cv.customTemplate[0],source=readFileSync(new URL('integrations/measurement/vendor/meta-pixel/template.tpl',root),'utf8');
 const provenance=JSON.parse(readFileSync(new URL('integrations/measurement/vendor/meta-pixel/provenance.json',root),'utf8'));
 assert.equal(createHash('sha256').update(source).digest('hex'),provenance.templateSha256);
 assert.equal(template.galleryReference.version,provenance.commit);assert.equal(provenance.version,'2.0.9');
 assert.equal(template.galleryReference.host,'github.com');assert.match(template.galleryReference.signature,/^[a-f0-9]{64}$/);
 for(const section of ['SANDBOXED_JS_FOR_WEB_TEMPLATE','TEMPLATE_PARAMETERS','WEB_PERMISSIONS']){
  const part=text=>text.split('___'+section+'___')[1].split(/___[A-Z_]+___/)[0].trim();
  if(section==='SANDBOXED_JS_FOR_WEB_TEMPLATE')assert.equal(part(template.templateData),part(source),section+' is unmodified');
  else assert.deepEqual(JSON.parse(part(template.templateData)),JSON.parse(part(source)),section+' is unchanged after GTM serialization');
 }
 assert.equal(cv.tag.filter(tag=>tag.type==='cvt_0_'+template.templateId).length,6);
});
test('Meta matching inputs belong only to Purchase/Lead; CAPI and automatic ecommerce stay off',()=>{
 const tags=cv.tag.filter(tag=>tag.type.startsWith('cvt_'));
 assert.deepEqual(tags.map(tag=>simple(tag).standardEventName).sort(),['ViewContent','AddToCart','InitiateCheckout','AddPaymentInfo','Purchase','Lead'].sort());
 for(const tag of tags){const p=simple(tag),contact=['Purchase','Lead'].includes(p.standardEventName);
  assert.equal(p.optInMetaCAPI,false);assert.equal(p.enhancedEcommerce,false);assert.equal(p.useGA4Ecommerce,false);
  assert.equal(p.advancedMatching,contact);assert.equal(Boolean(parameters(tag).advancedMatchingList),contact);
  assert.equal(p.eventId,undefined);
 }
});

function templateData(tag,event,layer){
 const read=resolver(event,layer),replace=value=>value.replace(/\{\{([^}]+)\}\}/g,(_,name)=>String(read(name)??''));
 const resolve=param=>{
  if(param.type==='BOOLEAN')return param.value==='true';
  if(param.type==='MAP')return Object.fromEntries(param.map.map(entry=>[entry.key,resolve(entry)]));
  if(param.type==='LIST')return param.list.map(resolve);
  const exact=param.value.match(/^\{\{([^}]+)\}\}$/);return exact?read(exact[1]):replace(param.value);
 };
 return Object.fromEntries(tag.parameter.map(param=>[param.key,resolve(param)]));
}
// Execute pristine upstream sandboxed JavaScript. Only public GTM/SDK I/O is
// modeled; this does not assert Meta network delivery or replace real GTM import.
function metaHarness({hasPixel=true,builderGate=false}={}){
 const calls=[],scripts=[],globals={};let success=0,failure=0;
 const set=(path,value)=>{const parts=path.split('.');const key=parts.pop();let current=globals;for(const part of parts)current=current[part]??={};current[key]=value;};
 const lookup=path=>get(globals,path);
 const fbq=(...args)=>{calls.push(args);if(args[0]==='gateCheck'){const callback=builderGate?args[2]:args[3];callback?.(args[1],args.at(-1));}};
 if(hasPixel)globals.fbq=fbq;
 const source=cv.customTemplate[0].templateData.split('___SANDBOXED_JS_FOR_WEB_TEMPLATE___')[1].split('___WEB_PERMISSIONS___')[0];
 const apis={createQueue:path=>{const array=[];set(path,array);return value=>array.push(value);},
  callInWindow:(path,...args)=>{const parts=path.split('.'),name=parts.pop(),parent=parts.length?lookup(parts.join('.')):globals;return parent?.[name]?.apply(parent,args);},
  aliasInWindow:(alias,path)=>set(alias,lookup(path)),copyFromWindow:lookup,setInWindow:(path,value)=>{set(path,value);return true;},
  injectScript:(url,onSuccess)=>{scripts.push(url);if(url.includes('fbevents.js')&&hasPixel)onSuccess();},
  makeTableMap:(list,key,value)=>Object.fromEntries(list.map(row=>[row[key],row[value]])),makeNumber:Number,
  getType:value=>Array.isArray(value)?'array':value===null?'null':typeof value,
  copyFromDataLayer:()=>({user_data:{email_address:'never-export'},items:[{item_id:'native'}]}),
  Math,logToConsole:()=>{},getUrl:()=> 'https://organizer.example/tickets',
 };
 return {calls,scripts,globals,get success(){return success},get failure(){return failure},run(data){
  vm.runInNewContext('(function(){'+source+'})()',{require:name=>{assert.ok(name in apis,name);return apis[name];},data:{...data,gtmOnSuccess:()=>success++,gtmOnFailure:()=>failure++}});
 }};
}
test('real Meta template uses projected purchase/matching and never opts into CAPI',()=>{
 const harness=metaHarness(),tag=cv.tag.find(tag=>tag.name==='Meta Pixel - Festapp - Purchase');
 harness.run(templateData(tag,'purchase',conversionLayer()));
 const event=harness.calls.find(call=>call[0]==='trackSingle');
 assert.deepEqual(clean(event),['trackSingle','000000000000000','Purchase',{currency:'CZK',value:200,contents:[{id:'product_1',quantity:2,item_price:100}]}]);
 assert.ok(harness.calls.some(call=>call[0]==='init'&&call[2].em==='buyer@example.test'&&call[2].ph==='420777123456'));
 assert.ok(harness.calls.every(call=>call[0]!=='optinMetaEnabledCapi'));assert.equal(harness.success,1);
 assert.doesNotMatch(JSON.stringify(harness.calls),/never-export|native/);
});
test('real Meta template retains zero-valued lead and public tags supply no matching data',()=>{
 const harness=metaHarness();
 for(const [name,event]of [['Lead','generate_lead'],['ViewContent','view_item']]){
  const data=templateData(cv.tag.find(tag=>tag.name==='Meta Pixel - Festapp - '+name),event,conversionLayer());
  harness.run(data);
 }
 const lead=harness.calls.find(call=>call[0]==='trackSingle'&&call[2]==='Lead');
 assert.deepEqual(clean(lead[3]),{currency:'CZK',value:0});
 assert.equal(harness.calls.filter(call=>call[0]==='trackSingle').length,2);
 assert.equal(harness.calls.some(call=>call[0]==='trackSingle'&&call[2]==='PageView'),false);
});
test('real template can queue a missing SDK and CAPI opt-out is not a no-dependencies claim',()=>{
 const tag=cv.tag.find(tag=>tag.name==='Meta Pixel - Festapp - ViewContent'),data=templateData(tag,'view_item',conversionLayer());
 const queued=metaHarness({hasPixel:false});queued.run(data);
 assert.equal(typeof queued.globals.fbq,'function');assert.ok(queued.globals.fbq.queue.some(args=>args[0]==='trackSingle'));
 assert.ok(queued.scripts.includes('https://connect.facebook.net/en_US/fbevents.js'));
 const builder=metaHarness({builderGate:true});builder.run(data);
 assert.ok(builder.scripts.some(url=>url.startsWith('https://cdn.jsdelivr.net/')));
 assert.ok(builder.calls.every(call=>call[0]!=='optinMetaEnabledCapi'));
});
