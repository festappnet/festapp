import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {preset,metaHtml} from '../../../integrations/measurement/build_gtm_preset.mjs';
const cv=preset.containerVersion;
test('paused import has no account/settings mutation and every trigger is a scoped host event',()=>{
 assert.equal(cv.tag.length,4);assert.ok(cv.tag.every(t=>t.paused));
 for(const trigger of cv.trigger) {
  assert.equal(trigger.type,'CUSTOM_EVENT');assert.equal(trigger.filter[0].parameter[0].value,'{{Festapp form_embedded}}');assert.equal(trigger.filter[0].parameter[1].value,'true');
 }
 assert.ok(cv.tag.every(t=>t.firingTriggerId.every(id=>cv.trigger.some(tr=>tr.triggerId===id))));
 const text=JSON.stringify(preset);assert.doesNotMatch(text,/autoEvent|enableAuto|GTM-W9WRHWT9|6402899907/);
 assert.deepEqual(JSON.parse(readFileSync(new URL('../../../integrations/measurement/festapp-host-gtm.json',import.meta.url))),preset);
});
test('Ads purchase uses bounded native user data with all advertising gates; GA4 excludes it',()=>{
 const ads=cv.tag.find(t=>t.type==='awct'),ga=cv.tag.find(t=>t.type==='gaawe');
 assert.equal(ads.firingTriggerId.length,1);assert.ok(cv.trigger.find(t=>t.triggerId===ads.firingTriggerId[0]).name.endsWith(' purchase'));
 assert.deepEqual(ads.consentSettings.consentType.list.map(p=>p.value),['ad_storage','ad_user_data','ad_personalization']);
 assert.match(JSON.stringify(ads),/Festapp user provided data/);assert.doesNotMatch(JSON.stringify(ga),/user_data|user provided/);
});
test('Meta sends public purchase fields and event identity without contacts or arbitrary ecommerce fields',()=>{
 const calls=[];const ecommerce={currency:'CZK',value:200,transaction_id:'order',email:'private@example.test',user_data:{email:'secret'},items:[{item_id:'product_1',quantity:2,price:100,email:'private'}]};
 const code=metaHtml.replace('<script>','').replace('</script>','').replace('{{Event}}',JSON.stringify('purchase')).replace('{{Festapp ecommerce}}',JSON.stringify(ecommerce)).replaceAll(/\{\{Festapp lead [^}]+\}\}/g,'undefined');
 vm.runInNewContext(code,{window:{fbq:(...args)=>calls.push(JSON.parse(JSON.stringify(args)))}});
 assert.deepEqual(calls,[['track','Purchase',{currency:'CZK',value:200,contents:[{id:'product_1',quantity:2,item_price:100}]},{eventID:'order'}]]);
 assert.doesNotMatch(JSON.stringify(calls),/private|secret|email|phone/);
});

test('preset includes each canonical host event including payment and errors',()=>{
 const actual=cv.trigger.map(t=>t.customEventFilter[0].parameter[1].value).sort();
 assert.deepEqual(actual,['form_page_view','form_start','form_submit_error','view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','purchase','generate_lead'].sort());
});

test('generic events never inherit native website ecommerce and lead variables are event scoped',()=>{
 const calls=[],code=metaHtml.replace('<script>','').replace('</script>','').replace('{{Event}}',JSON.stringify('form_start')).replace('{{Festapp ecommerce}}',JSON.stringify({currency:'USD',value:999,transaction_id:'native',items:[{item_id:'native',price:999,quantity:1}]})).replaceAll(/\{\{Festapp lead [^}]+\}\}/g,'undefined');
 vm.runInNewContext(code,{window:{fbq:(...args)=>calls.push(JSON.parse(JSON.stringify(args)))}});
 assert.deepEqual(calls,[['trackCustom','Festapp_form_start',{}]]);
 const ga=cv.tag.filter(t=>t.type==='gaawe');
 for(const tag of ga){const enabled=tag.parameter.find(p=>p.key==='sendEcommerceData').value==='true';
 for(const id of tag.firingTriggerId){const event=cv.trigger.find(t=>t.triggerId===id).customEventFilter[0].parameter[1].value;
 assert.equal(enabled,['view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','purchase'].includes(event));}}
 for(const name of ['value','currency','lead_source','event_id']){
 const variable=cv.variable.find(v=>v.name==='Festapp lead '+name),script='('+variable.parameter[0].value+')()';
 assert.equal(vm.runInNewContext(script.replace('{{Event}}',JSON.stringify('form_start')).replace('{{Festapp '+name+'}}',JSON.stringify('native-stale'))),undefined);
 assert.equal(vm.runInNewContext(script.replace('{{Event}}',JSON.stringify('generate_lead')).replace('{{Festapp '+name+'}}',JSON.stringify('lead-value'))),'lead-value');
 }
});
