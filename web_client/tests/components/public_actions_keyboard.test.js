import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';

test('settings and feedback expose named buttons and restore keyboard focus', async t => {
    const dom = new JSDOM('<body><div id="feedback-fab"></div></body>', { url: 'https://tickets.invalid/' });
    for (const key of ['window', 'document', 'HTMLElement', 'customElements', 'Event', 'CustomEvent']) {
        globalThis[key] = key === 'window' ? dom.window : dom.window[key];
    }
    globalThis.localStorage = dom.window.localStorage;
    t.after(() => dom.window.close());
    const [{ UserHeader }, { RightsService }, { LocalizationService }, { FeedbackFab }, { FeedbackDialog }] = await Promise.all([
        import('../../src/components/users/user_header.js'), import('../../src/services/rights_service.js'),
        import('../../src/services/localization_service.js'), import('../../src/components/feedback/feedback_fab.js'),
        import('../../src/components/feedback/feedback_dialog.js'),
    ]);
    const translations = JSON.parse(readFileSync(new URL('../../public/assets/translations/cs.json', import.meta.url)));
    t.mock.method(LocalizationService, 'tr', key => key.split('.').reduce((value, part) => value?.[part], translations) ?? key);
    const context = RightsService._context;
    t.after(() => { RightsService._context = context; });
    RightsService._context = { organization: {} };
    const header = new UserHeader();
    document.body.appendChild(header);
    const settings = header.querySelector('.settings-icon-btn');
    assert.equal(settings.tagName, 'BUTTON');
    assert.equal(settings.type, 'button');
    assert.equal(settings.tabIndex, 0);
    assert.equal(settings.getAttribute('aria-label'), 'Nastavení');
    settings.click();
    const close = header.querySelector('.popover-close-btn');
    assert.equal(close.tagName, 'BUTTON');
    assert.equal(close.getAttribute('aria-label'), 'Zavřít');
    assert.equal(document.activeElement, close);
    assert.equal(settings.getAttribute('aria-expanded'), 'true');
    document.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Escape' }));
    assert.equal(document.activeElement, settings);
    assert.equal(settings.getAttribute('aria-expanded'), 'false');
    settings.click();
    header.querySelector('.popover-close-btn').click();
    assert.equal(document.activeElement, settings);
    FeedbackFab.init('feedback-fab');
    const trigger = document.getElementById('fab-button');
    assert.equal(trigger.tagName, 'BUTTON');
    assert.equal(trigger.type, 'button');
    assert.equal(trigger.getAttribute('aria-label'), 'Jak můžeme pomoci?');
    trigger.click();
    const first = document.querySelector('.fab-item');
    assert.equal(first.tagName, 'BUTTON');
    assert.equal(trigger.getAttribute('aria-expanded'), 'true');
    assert.equal(document.activeElement, first);
    document.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Escape' }));
    assert.equal(trigger.getAttribute('aria-expanded'), 'false');
    assert.equal(document.activeElement, trigger);
    trigger.click();
    first.click();
    const dialogClose = document.getElementById('fd-close-btn');
    assert.equal(document.activeElement, dialogClose);
    assert.equal(dialogClose.getAttribute('aria-label'), 'Zavřít');
    FeedbackDialog.close();
    assert.equal(document.activeElement, trigger);
    trigger.click();
    document.body.click();
    assert.equal(trigger.getAttribute('aria-expanded'), 'false');
    assert.equal(FeedbackFab.clickOutsideListener, null);
    assert.equal(FeedbackFab.escListener, null);
    header.remove();
});
