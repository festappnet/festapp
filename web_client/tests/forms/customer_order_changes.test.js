import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {LocalizationService} from '../../src/services/localization_service.js';
import {renderCustomerOrderChanges,takeCustomerChangeToken} from '../../src/components/forms/customer_order_changes.js';
const scope={orderId:1,token:'a'.repeat(64)};
const base=()=>({root:{id:1},people:[],changeRequests:[],allowedActions:[{operation:'cancel',enabled:true,reasonRequired:true,mode:'approval_required'}]});
const tick=()=>new Promise(resolve=>setTimeout(resolve,0));
function setup(t){const dom=new JSDOM('<main></main>',{url:'https://example.test/order?order_id=1&token='+scope.token});globalThis.window=dom.window;globalThis.document=dom.window.document;
 LocalizationService.currentLocale='cs';LocalizationService.translations=JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url)));
 t.after(()=>dom.window.close());return document.querySelector('main');}
const find=(host,label)=>[...host.querySelectorAll('button')].find(b=>b.textContent===label);
test('a cancellation request validates its required reason and never claims the order is cancelled',async t=>{
 const host=setup(t);const calls=[];const client={functions:{invoke:async(_,{body})=>{calls.push(body);return {data:{code:202}};}}};
 renderCustomerOrderChanges(host,base(),scope,client,async()=>{});
 find(host,'Stornovat objednávku').click();const form=host.querySelector('form');form.dispatchEvent(new window.Event('submit',{cancelable:true}));await tick();assert.equal(calls.length,0);
 host.querySelector('textarea').value='Nemohu přijet';form.dispatchEvent(new window.Event('submit',{cancelable:true}));await tick();
 assert.equal(calls.length,1);assert.equal(calls[0].action,'challenge');assert.deepEqual(calls[0].payload,{reason:'Nemohu přijet'});assert.match(host.textContent,/Pokud lze pokračovat/);assert.doesNotMatch(host.textContent,/Výsledek byl uložen/);
});
test('confirmation waits for explicit click; uncertain transport retries the identical command',async t=>{
 const host=setup(t);window.__festappCustomerChangeToken='b'.repeat(64);const commands=[];let fail=true;let refreshed=0;
 const client={functions:{invoke:async(_,{body})=>{
  if(body.action==='resolve')return{data:{code:200,orderId:1,operation:'cancel',payload:{reason:'Nemohu přijet'}}};
  if(body.action==='preview')return{data:{code:200,effect:'request_cancel',fingerprint:'c'.repeat(64)}};
  commands.push(body);return fail?{error:new Error('network')}:{data:{code:200}};
 }}};
 renderCustomerOrderChanges(host,base(),scope,client,async()=>{refreshed++;});await tick();await tick();assert.equal(commands.length,0);
 assert.equal(window.__festappCustomerChangeToken,undefined);assert.match(host.textContent,/Do schválení pořadatelem/);
 const confirm=find(host,'Odeslat žádost');confirm.click();confirm.click();await tick();assert.equal(commands.length,1);assert.equal(refreshed,0);
 fail=false;confirm.click();await tick();assert.equal(commands.length,2);assert.deepEqual(commands[0],commands[1]);assert.equal(refreshed,1);
 assert.equal(host._customerChangeSession,undefined);
});
test('409 removes stale confirmation and requires a fresh preview and confirmation',async t=>{
 const host=setup(t);window.__festappCustomerChangeToken='b'.repeat(64);let previews=0;let writes=0;
 const client={functions:{invoke:async(_,{body})=>{
  if(body.action==='resolve')return{data:{code:200,orderId:1,operation:'cancel',payload:{reason:'Nemohu přijet'}}};
  if(body.action==='preview'){previews++;return{data:{code:200,effect:'request_cancel',fingerprint:String(previews).repeat(64)}};}
  writes++;return{data:{code:409}};
 }}};
 renderCustomerOrderChanges(host,base(),scope,client,async()=>{});await tick();await tick();find(host,'Odeslat žádost').click();await tick();
 assert.equal(writes,1);assert.equal(find(host,'Odeslat žádost'),undefined);find(host,'Obnovit náhled').click();await tick();assert.equal(previews,2);assert.equal(writes,1);assert.ok(find(host,'Odeslat žádost'));
});
test('captured token is consumed once and never enters location or persistent storage',t=>{
 const host=setup(t);window.__festappCustomerChangeToken='b'.repeat(64);assert.equal(takeCustomerChangeToken(), 'b'.repeat(64));assert.equal(takeCustomerChangeToken(),null);assert.equal(window.location.hash,'');assert.equal(window.localStorage.length,0);assert.ok(host);
});

test('move selector and confirmation retain target name, date and product breakdown',async t=>{
 const host=setup(t),target={formId:2,title:'Večerní termín',startsAt:'2026-12-10T18:00:00Z',automatic:true,tickets:[{products:[{title:'Vstup na večer',price:1000,currency_code:'CZK'}]}]};
 const data=base();data.allowedActions=[{operation:'move',enabled:true,targets:[target]}];
 renderCustomerOrderChanges(host,data,scope,{functions:{invoke:async()=>({data:{code:202}})}},async()=>{});
 find(host,'Změnit termín').click();
 const option=host.querySelector('select option[value="2"]');assert.match(option.textContent,/Večerní termín/);assert.match(option.textContent,/2026/);
 host.replaceChildren();window.__festappCustomerChangeToken='b'.repeat(64);
 renderCustomerOrderChanges(host,data,scope,{functions:{invoke:async(_,{body})=>({data:body.action==='resolve'?{code:200,orderId:1,operation:'move',payload:{targetFormId:2}}:{code:200,effect:'move',target,fingerprint:'f'.repeat(64)}})}},async()=>{});
 await tick();await tick();assert.match(host.textContent,/Večerní termín.*2026/);assert.match(host.textContent,/Vstup na večer: 1000 CZK/);
});
