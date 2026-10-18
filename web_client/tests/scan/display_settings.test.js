import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {ScannerSettingsPage} from '../../src/components/scan/scanner_settings_page.js';
import {LocalizationService} from '../../src/services/localization_service.js';
import {readFile} from 'node:fs/promises';
test('editor selects products and order/ticket answers and saves the scoped settings',async()=>{
 const dom=new JSDOM('<div id="settings"></div>');
 const original={document:globalThis.document,translations:LocalizationService.translations};globalThis.document=dom.window.document;
 LocalizationService.translations=JSON.parse(await readFile(new URL('../../public/assets/translations/cs.json',import.meta.url),'utf8'));
 const data={revision:7,config:{products:{mode:'all',ids:[],order:[]},fields:[],manual_search:{tickets:true,users:false},sensitive:{price:true,hidden_note:false},offline:{enabled:false,max_hours:0}},products:[{id:3,title:'Guláš',type_title:'Večeře'}],fields:[{form_id:1,field_id:2,source:'order_field',form_title:'Objednávka',label:'Poznámka pořadatele'},{form_id:1,field_id:4,source:'ticket_field',form_title:'Host',label:'Stravovací omezení'}]};
 let saved;
 const api={async call(name,params,scoped){assert.equal(scoped,false);assert.equal(params.p_occasion,42);if(name==='update_scanner_settings'){saved=structuredClone(params);return {data:{...data,revision:8}};}return {data};}};
 try{
  const page=new ScannerSettingsPage(document.getElementById('settings'),{api,session:{occasion_id:42}});await page.init();
  const fixed=[...page.host.querySelectorAll('[data-fixed]')];
  assert.equal(fixed.length,4);assert.ok(fixed.every(input=>input.checked&&input.disabled));
  assert.equal(page.host.querySelector('[data-product]'),null,'all mode needs no individual selection');
  assert.equal(page.host.querySelector('option[value="builtin:holder_name"]'),null);
  let select=page.host.querySelector('[data-mode]');select.value='selected';select.onchange({target:select});
  const product=page.host.querySelector('[data-product="3"]');assert.equal(product.checked,true,'all -> selected preserves effective selection');assert.equal(product.disabled,false);product.checked=false;product.onchange();assert.deepEqual(page.draft.products.ids,[]);product.checked=true;product.onchange();
  for(const value of ['0','1']){select=page.host.querySelector('[data-add-field]');select.value=value;select.onchange({target:select});}
  assert.match(page.host.textContent,/Stravovací omezení/);assert.doesNotMatch(page.host.textContent,/order_field|ticket_field|order:1:2/);
  await page.host.querySelector('[data-settings]').onsubmit({preventDefault(){}});
  assert.equal(saved.p_expected_revision,7);assert.deepEqual(saved.p_config.products.ids,[3]);assert.deepEqual(saved.p_config.fields.map(f=>f.source),['order_field','ticket_field']);
 }finally{globalThis.document=original.document;LocalizationService.translations=original.translations;dom.window.close();}
});

test('none mode stays empty and existing hidden answers remain off',()=>{
 const dom=new JSDOM('<div id="settings"></div>');const old=globalThis.document;globalThis.document=dom.window.document;
 try{
  const page=new ScannerSettingsPage(document.getElementById('settings'),{api:{},session:{occasion_id:42}});
  page.data={products:[{id:3,title:'Dinner',type_title:'Food'}],fields:[]};
  page.draft={products:{mode:'none',ids:[3],order:[]},fields:[{key:'order:1:2',source:'order_field',label:'Optional',default_visible:false}],manual_search:{},sensitive:{},offline:{max_hours:0}};page.render();
  assert.equal(page.host.querySelector('[data-product]'),null);
  assert.equal(page.host.querySelector('[data-visible]').checked,false);
 }finally{globalThis.document=old;dom.window.close();}
});

test('core ticket identity, status, seat and notes remain visible with no optional fields',async()=>{
 const {scanResult}=await import('../../src/components/scan/scan_result.js');
 const html=scanResult({state:'result',ticket:{state:'sent',admission_allowed:true,holder_name:'Host',purchaser_name:'Purchaser',symbol:'CODE',spot:'7A',note:'Ticket note',order_note:'Order note',products:[],fields:[{key:'holder_name',value:'Duplicate host',default_visible:true}]}},true);
 const dom=new JSDOM(html);
 try{assert.ok(dom.window.document.querySelector('.scan-result.allowed'));for(const text of ['Host','Purchaser','7A','Ticket note','Order note'])assert.ok(dom.window.document.body.textContent.includes(text));assert.ok(!dom.window.document.body.textContent.includes('Duplicate host'));assert.ok(dom.window.document.querySelector('[data-confirm]'));}finally{dom.window.close();}
});


test('direct settings link returns to this event tickets and uses current event title',()=>{
 const dom=new JSDOM('<div id="settings"></div>');const old=globalThis.document;globalThis.document=dom.window.document;
 try{
  const page=new ScannerSettingsPage(document.getElementById('settings'),{api:{},session:{occasion_id:42,title:'Cached title'},returnPath:'/'});
  page.data={occasion_link:'ples 2026',occasion_title:'Current event title',products:[],fields:[]};
  page.draft={products:{mode:'all',ids:[],order:[]},fields:[],manual_search:{},sensitive:{},offline:{max_hours:0}};page.render();
  assert.equal(page.host.querySelector('.scan-settings-nav a').getAttribute('href'),'/ples%202026/reservations/tickets');
  assert.equal(page.host.querySelector('.scan-settings-event').textContent,'Current event title');
  page.returnPath='/ples%202026/reservations/tickets?filter=paid#table';page.render();
  assert.equal(page.host.querySelector('.scan-settings-nav a').getAttribute('href'),page.returnPath);
  page.returnPath='/different-event/reservations/tickets';page.render();
  assert.equal(page.host.querySelector('.scan-settings-nav a').getAttribute('href'),'/ples%202026/reservations/tickets');
  page.returnPath='/';delete page.data.occasion_link;page.render();
  assert.equal(page.host.querySelectorAll('.scan-settings-nav a').length,1);
  assert.equal(page.host.querySelector('.scan-settings-nav a').getAttribute('href'),'/scan');
 }finally{globalThis.document=old;dom.window.close();}
});
