import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { AppConfig } from '../../src/app_config.js';
const { ScanPage } = await import('../../src/components/scan/scan_page.js');
const { ScannerSettingsPage } = await import('../../src/components/scan/scanner_settings_page.js');

for (const supported of [false,true]) for (const tickets of [false,true]) for (const users of [false,true]) {
    test(`manual search choices respect app=${supported}, tickets=${tickets}, users=${users}`,async()=>{
        const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
        const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator'),supported:AppConfig.isAppSupported};
        globalThis.document=dom.window.document;
        Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
        AppConfig.isAppSupported=supported;
        try {
            const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
            page.route={page:'scan'};page.mode='manual';page.storageAvailable=true;
            page.row={session:{title:'Ples',capabilities:{search_tickets:tickets,search_users:users},settings:{fields:[]}}};
            page.controller={state:'ready'};
            page.searchScope='users';page.searchResults=[{symbol:'old-user',holder_name:'Old user'}];
            const calls=[];
            page.api={async search(query){calls.push(['tickets',query]);return [];},async call(name,params){calls.push([name,params.p_query]);return {data:[]};}};
            page.render();
            const form=page.host.querySelector('[data-search]');
            assert.equal(Boolean(form),tickets || supported && users);
            assert.equal(Boolean(page.host.querySelector('[data-search-scope]')),tickets && supported && users);
            if (!supported || !users) {
                assert.equal(page.searchScope,'tickets');
                assert.equal(page.host.querySelector('[data-search-ticket]'),null);
            }
            if(form){
                form.elements.query.value='Novák';
                form.dispatchEvent(new dom.window.Event('submit',{cancelable:true}));
                await new Promise(resolve=>setImmediate(resolve));
                assert.deepEqual(calls,[[supported && users?'search_scanner_users':'tickets','Novák']]);
            }
            if(!supported && tickets){
                page.searchScope='users';page.searchQuery='Novák';
                await page.search(0);
                assert.equal(calls.at(-1)[0],'tickets','stale user selection cannot dispatch participant search');
            }
        } finally {
            AppConfig.isAppSupported=previous.supported;globalThis.document=previous.document;
            Object.defineProperty(globalThis,'navigator',previous.navigator);dom.window.close();
        }
    });
}

for(const supported of [false,true]) test(`settings participant search visibility respects app=${supported}`,()=>{
    const dom=new JSDOM('<div id="settings"></div>');
    const previous={document:globalThis.document,supported:AppConfig.isAppSupported};
    globalThis.document=dom.window.document;AppConfig.isAppSupported=supported;
    try {
        const page=new ScannerSettingsPage(document.getElementById('settings'),{api:{},session:{occasion_id:42}});
        page.data={revision:1,products:[],fields:[]};
        page.draft={products:{mode:'all',ids:[],order:[]},fields:[],manual_search:{tickets:true,users:true},sensitive:{price:true,hidden_note:false},offline:{enabled:false,max_hours:0}};
        page.render();
        assert.equal(Boolean(page.host.querySelector('[data-option="manual_search.users"]')),supported);
        assert.ok(page.host.querySelector('[data-option="manual_search.tickets"]'));
    } finally {globalThis.document=previous.document;AppConfig.isAppSupported=previous.supported;dom.window.close();}
});


test('search previews show customer, seat, products and actual status with one symbol; selection uses ticket identity',async()=>{
 const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
 const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
 globalThis.document=dom.window.document;Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 try {
  const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
  page.route={page:'scan'};page.mode='manual';page.storageAvailable=true;
  page.row={session:{title:'Skautský ples',capabilities:{search_tickets:true},settings:{fields:[]}}};
  let selected,navigations=0;
  page.controller={state:'ready',loadTicket:row=>{selected=row;page.controller.state='result';}};
  page.searchResults=[{ticket_id:1,symbol:'AB123',holder_name:'AB123',purchaser_name:'Jana Nováková',state:'sent',admission_allowed:true,spot:'4B',spot_group:{title:'4'},products:[{title:'Guláš',type:'food',type_title:'Večeře'}]},
   {ticket_id:2,symbol:null,holder_name:null,purchaser_name:'Petr Novák',state:'storno',products:[]},
   {ticket_id:3,symbol:null,purchaser_name:'Eva Nováková',state:'waitlisted',products:[]}];
  page.render();
  page.host.querySelector('.scan-layout').scrollIntoView=()=>{navigations++;};
  const rows=[...page.host.querySelectorAll('[data-search-ticket]')];
  assert.equal(rows.length,3);assert.equal(rows[0].textContent.match(/AB123/g).length,1);
  assert.match(rows[0].textContent,/Jana Nováková/);assert.match(rows[0].textContent,/table 4/);assert.match(rows[0].textContent,/4B/);assert.match(rows[0].textContent,/Večeře: Guláš/);
  assert.match(rows[1].textContent,/ticket_cancelled/);assert.match(rows[2].textContent,/ticket_waitlisted/);
  assert.doesNotMatch(rows[1].textContent,/null|no_products/);
  assert.match(page.host.querySelector('.scan-search-context').textContent,/Skautský ples/);
  rows[1].click();await new Promise(resolve=>setImmediate(resolve));assert.equal(navigations,1);assert.equal(selected,page.searchResults[1],'symbol-less selection reaches authoritative ticket lookup');
  rows[0].click();assert.equal(selected,page.searchResults[0],'another search result can be selected by its own identity');
 }finally{globalThis.document=previous.document;Object.defineProperty(globalThis,'navigator',previous.navigator);dom.window.close();}
});


test('participant search previews do not imply a ticket admission status',async()=>{
 const {scannerSearchPreview}=await import('../../src/components/scan/scanner_presentation.js');
 const html=scannerSearchPreview({user_id:9,symbol:'user-reference',holder_name:'Petra Svobodová'});
 assert.match(html,/Petra Svobodová/);assert.doesNotMatch(html,/not_allowed|scan-ticket-status/);
});

test('late searches cannot replace a newer query or a newly selected event',async()=>{
 const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
 const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
 globalThis.document=dom.window.document;Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 try {
  const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
  page.route={page:'scan'};page.mode='manual';page.storageAvailable=true;
  const event=title=>({session:{title,capabilities:{search_tickets:true},settings:{fields:[]}}});
  const rowA=event('Ples A'),rowB=event('Skautský ples');
  const pending=new Map();
  page.api={search:query=>new Promise((resolve,reject)=>pending.set(query,{resolve,reject}))};
  page.recover=async()=>{};
  await page.select(rowA);
  let renders=0;const render=page.render.bind(page);page.render=()=>{renders++;render();};
  page.searchQuery='old';const old=page.search(0);
  page.searchQuery='latest';const latest=page.search(0);
  const latestResult={ticket_id:2,symbol:'LATEST',holder_name:'Current customer',state:'sent',admission_allowed:true};
  pending.get('latest').resolve([latestResult]);await latest;
  const currentRenders=renders;
  pending.get('old').resolve([{ticket_id:1,symbol:'OLD',holder_name:'Old customer'}]);await old;
  assert.deepEqual(page.searchResults,[latestResult]);assert.equal(renders,currentRenders);
  assert.equal(page.host.querySelectorAll('[data-search-ticket]').length,1);
  assert.match(page.host.querySelector('[data-search-ticket]').textContent,/Current customer/);

  page.searchQuery='old event';const oldEvent=page.search(0);
  page.host.querySelector('[name=query]').value='old event';
  await page.select(rowB);
  assert.equal(page.searchQuery,'');assert.deepEqual(page.searchResults,[]);
  assert.equal(page.host.querySelector('[name=query]').value,'','previous event draft must not survive selection');
  const newEventRenders=renders;
  pending.get('old event').resolve([{ticket_id:3,symbol:'EVENT-A',holder_name:'Wrong event customer'}]);await oldEvent;
  assert.equal(page.row,rowB);assert.deepEqual(page.searchResults,[]);assert.equal(renders,newEventRenders);
  assert.equal(page.host.querySelector('[data-search-ticket]'),null);

  page.searchQuery='old error';const oldError=page.search(0);
  page.searchQuery='new query';const newQuery=page.search(0);
  pending.get('new query').resolve([latestResult]);await newQuery;
  const beforeError=renders;
  pending.get('old error').reject(new Error('network_error'));await oldError;
  assert.equal(page.searchError,null);assert.deepEqual(page.searchResults,[latestResult]);assert.equal(renders,beforeError);
  page.disposeControllers();
 }finally{globalThis.document=previous.document;Object.defineProperty(globalThis,'navigator',previous.navigator);dom.window.close();}
});
