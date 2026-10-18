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
  let select=page.host.querySelector('[data-mode]');select.value='selected';select.onchange({target:select});
  const product=page.host.querySelector('[data-product="3"]');product.checked=true;product.onchange();
  for(const value of ['0','1']){select=page.host.querySelector('[data-add-field]');select.value=value;select.onchange({target:select});}
  assert.match(page.host.textContent,/Stravovací omezení/);assert.doesNotMatch(page.host.textContent,/order_field|ticket_field|order:1:2/);
  await page.host.querySelector('[data-settings]').onsubmit({preventDefault(){}});
  assert.equal(saved.p_expected_revision,7);assert.deepEqual(saved.p_config.products.ids,[3]);assert.deepEqual(saved.p_config.fields.map(f=>f.source),['order_field','ticket_field']);
 }finally{globalThis.document=original.document;LocalizationService.translations=original.translations;dom.window.close();}
});
