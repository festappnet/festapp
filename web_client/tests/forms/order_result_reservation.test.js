import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { OrderResult } from '../../src/components/forms/order_result.js';
import { LocalizationService } from '../../src/services/localization_service.js';

for (const locale of ['cs', 'en']) {
    test(`reservation errors render actionable ${locale} text and return to the form`, () => {
        const dom = new JSDOM('<div id="host"></div>', {url:'http://localhost/'});
        globalThis.document = dom.window.document;
        const original = LocalizationService.translations;
        try {
            const catalog = JSON.parse(readFileSync(new URL(`../../../assets/translations/${locale}.json`, import.meta.url)));
            LocalizationService.translations = catalog;
            const host = document.querySelector('#host');
            let returned = 0;
            for (const errorCode of ['reservation_state_unknown', 'reservation_changed', 'reservation_expired', 'CHECKOUT_CONTEXT_EXPIRED']) {
                OrderResult.render(host, false, {code:999, errorCode}, {visibleFields:[]}, () => returned++);
                const message = host.querySelector('.result-subtitle').textContent;
                assert.equal(message, catalog.PublicOrder[errorCode]);
                assert.ok(message.length > 50);
                assert.ok(!message.includes('Waitlist.'));
                host.querySelector('.btn-back-to-form').click();
            }
            assert.equal(returned, 4);
        } finally {
            LocalizationService.translations = original;
            dom.window.close();
        }
    });
}
