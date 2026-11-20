import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { createBrowserStorage } from '../../src/services/browser_storage.js';
import { initPublicLanguage } from '../../src/marketing/public_language.js';

test('an explicit language survives a direct return to public help without overriding shared links', t => {
    const dom = new JSDOM('<html lang="cs"><a data-public-language="cs">Čeština</a><a data-public-language="sk">Slovenčina</a>', {
        url:'https://vstupenky.online/napoveda/platby/#potize',
    });
    t.after(() => dom.window.close());
    const storage = createBrowserStorage(() => dom.window.localStorage);
    storage.setItem('flutter.locale', '"sk"');
    let navigation;
    const win = {document:dom.window.document, location:{href:dom.window.location.href, replace:href => {navigation=href;}}};
    assert.equal(initPublicLanguage(win, storage), false, 'automatic preferences do not redirect public pages');
    storage.setItem('flutter.locale.manuallySelected', 'true');
    assert.equal(initPublicLanguage(win, storage), true);
    assert.equal(navigation, 'https://vstupenky.online/napoveda/platby/?lang=sk#potize');
    navigation = undefined;
    win.location.href = 'https://vstupenky.online/napoveda/platby/?lang=cs#potize';
    assert.equal(initPublicLanguage(win, storage), false);
    assert.equal(navigation, undefined);
});
