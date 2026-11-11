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
                assert.equal(page.host.querySelector('[data-ticket="old-user"]'),null);
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
