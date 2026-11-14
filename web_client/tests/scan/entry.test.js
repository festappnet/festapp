import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const { ScannerApi } = await import('../../src/services/scanner_api.js');
const { ScanPage } = await import('../../src/components/scan/scan_page.js');

test('entry preserves drafts through offline/rejected exchanges and prevents duplicate submissions', async () => {
    const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
    const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
    globalThis.document=dom.window.document;
    Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
    try {
        const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
        page.route={page:'scan'};page.storageAvailable=true;page.render();
        const code=page.host.querySelector('[name=code]');
        code.value='incorrect-code';code.focus();code.setSelectionRange(3,6);
        page.host.querySelector('[name=device]').value='Main entrance';
        navigator.onLine=false;page.render();
        assert.equal(document.activeElement.name,'code');
        assert.equal(document.activeElement.selectionStart,3);
        assert.equal(page.host.querySelector('[name=device]').value,'Main entrance');
        assert.equal(page.host.querySelector('[data-open] button').disabled,true);
        navigator.onLine=true;page.render();
        let reject,calls=0;
        page.api={open:()=>{calls++;return new Promise((_,fail)=>{reject=fail;});}};
        const params={p_scan_code:'incorrect-code',p_device_name:'Main entrance'};
        const pending=page.open(params);
        assert.equal(page.host.querySelector('[data-open]').getAttribute('aria-busy'),'true');
        assert.equal(page.host.querySelector('[data-open] button').disabled,true);
        await page.open(params);assert.equal(calls,1);
        reject(new Error('invalid_scan_code'));await pending;
        assert.equal(document.activeElement.name,'code');
        assert.equal(document.activeElement.value,'incorrect-code');
        assert.equal(document.activeElement.getAttribute('aria-invalid'),'true');
        assert.match(document.activeElement.getAttribute('aria-describedby'),/scan-entry-error/);
        assert.equal(page.host.querySelector('[name=device]').value,'Main entrance');
        assert.equal(page.host.querySelector('[data-open] button').disabled,false);
        assert.equal(page.host.querySelector('.scan-saved'),null);
        page.api.open=async()=>{throw new Error('network_error');};await page.open(params);
        assert.equal(page.host.querySelector('[name=code]').getAttribute('aria-invalid'),'false');
        assert.equal(document.activeElement.id,'scan-entry-error');
        page.rows=[{locked:true,session:{title:'Saved event',device_name:'Door 2'}}];page.render();
        let selected;page.select=async row=>{selected=row;};page.host.querySelector('[data-session]').click();
        assert.equal(selected,page.rows[0]);assert.equal(page.authBlocked,true);
    } finally {
        dom.window.close();globalThis.document=previous.document;
        Object.defineProperty(globalThis,'navigator',previous.navigator);
    }
});

test('successful backend recovery overrides a stale browser offline hint', async()=>{
    const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
    const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
    globalThis.document=dom.window.document;
    Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:false}});
    try {
        const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
        page.route={page:'scan'};page.storageAvailable=true;
        page.row={partition:'scanner',session:{title:'Country bál',capabilities:{},settings:{}}};
        page.render=()=>{page.host.innerHTML=page.shell('');};
        let calls=0;
        page.api={summary:async()=>{calls++;return {eligible_total:90,used_current:0,snapshot_ticket_count:90};}};
        await page.recover();
        assert.equal(calls,1,'the browser hint must not prevent a bounded backend probe');
        assert(page.host.querySelector('.scan-connection.is-online'));
        assert.equal(page.host.querySelector('.scan-offline-notice'),null);
        assert.equal(page.summary.eligible_total,90);
    } finally {
        dom.window.close();globalThis.document=previous.document;
        Object.defineProperty(globalThis,'navigator',previous.navigator);
    }
});

test('failed transport recovery becomes offline and a later retry restores connection', async()=>{
    const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
    const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
    globalThis.document=dom.window.document;
    Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
    try {
        const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
        page.route={page:'scan'};page.storageAvailable=true;
        page.row={partition:'scanner',session:{title:'Country bál',capabilities:{},settings:{}}};
        page.render=()=>{page.host.innerHTML=page.shell('');};
        page.api={summary:async()=>{throw Object.assign(new Error('network_error'),{code:0});}};
        await page.recover();
        assert(page.host.querySelector('.scan-connection.is-offline'));
        navigator.onLine=false;page.summaryAt=0;
        page.api.summary=async()=>({eligible_total:90,used_current:0,snapshot_ticket_count:90});
        await page.recover();
        assert(page.host.querySelector('.scan-connection.is-online'));
        assert.equal(page.host.querySelector('.scan-offline-notice'),null);
    } finally {
        dom.window.close();globalThis.document=previous.document;
        Object.defineProperty(globalThis,'navigator',previous.navigator);
    }
});


test('scanner API keeps HTTP server and authorization failures distinct from transport failures',async()=>{
    for(const status of [401,403,500,503]){
        const api=new ScannerApi({rpc:async()=>({data:null,error:{message:'server_failure',code:'PGRST_FAILURE'},status})},{session_id:'session',token:'token'});
        await assert.rejects(api.summary(),error=>error.code===status);
    }
});

test('selecting a cached offline session never waits for a network probe',async()=>{
    const dom=new JSDOM('<div id="scanner"></div>',{url:'http://localhost/scan'});
    const previous={document:globalThis.document,navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator')};
    globalThis.document=dom.window.document;
    Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:false}});
    try {
        const page=new ScanPage(document.getElementById('scanner'),{client:{},store:null});
        page.route={page:'scan'};page.returnNavigation={location:{href:dom.window.location.href}};page.render=()=>{};
        let probes=0;page.recover=()=>{probes++;return new Promise(()=>{});};
        const selected=page.select({session:{title:'Cached event',capabilities:{},settings:{}}});
        assert.equal(await Promise.race([selected.then(()=>true),new Promise(resolve=>setTimeout(()=>resolve(false),50))]),true);
        assert.equal(probes,0,'the periodic background recovery owns the later connectivity probe');
        page.disposeControllers();
    } finally {
        dom.window.close();globalThis.document=previous.document;
        Object.defineProperty(globalThis,'navigator',previous.navigator);
    }
});
