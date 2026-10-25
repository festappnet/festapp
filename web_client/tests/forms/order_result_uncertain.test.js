import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { OrderResult } from '../../src/components/forms/order_result.js';
import { LocalizationService } from '../../src/services/localization_service.js';
for (const locale of ['cs','en','sk','pl','de','uk']) {
    test(`unknown transport outcome is distinguished from rejection in ${locale}`, () => {
        const dom = new JSDOM('<div id="host"></div>');
        globalThis.document = dom.window.document;
        const original = LocalizationService.translations;
        try {
            const catalog = JSON.parse(readFileSync(new URL(`../../../assets/translations/${locale}.json`,import.meta.url)));
            LocalizationService.translations = catalog;
            const host = document.querySelector('#host');
            let returned = false;
            OrderResult.render(host,false,{code:503,errorCode:'ORDER_OUTCOME_UNKNOWN'},{visibleFields:[]},()=>{returned=true;});
            assert.equal(host.querySelector('.result-title').textContent,catalog.PublicOrder.outcomeUnknownTitle);
            assert.equal(host.querySelector('.result-subtitle').textContent,catalog.PublicOrder.outcomeUnknownHint);
            assert.notEqual(host.querySelector('.result-title').textContent,catalog.PublicOrder.orderFailed ?? 'PublicOrder.orderFailed');
            host.querySelector('.btn-back-to-form').click();
            assert.equal(returned,true);
            OrderResult.render(host,false,{code:400},{visibleFields:[]},()=>{});
            assert.equal(host.querySelector('.result-title').textContent,catalog.PublicOrder.orderFailed ?? 'PublicOrder.orderFailed');
        } finally {LocalizationService.translations=original;dom.window.close();}
    });
}
