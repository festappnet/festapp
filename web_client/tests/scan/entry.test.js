import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
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
