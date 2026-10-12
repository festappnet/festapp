import assert from 'node:assert/strict';
import test from 'node:test';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);

test('create-event invitation respects the tenant and explicit registration permission', async t => {
    const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://vstupenky.online/' });
    global.window = dom.window;
    global.document = dom.window.document;
    global.HTMLElement = dom.window.HTMLElement;
    global.customElements = dom.window.customElements;
    const [{ UserHeader }, { RightsService }, { AppConfig }, { LocalizationService }] = await Promise.all([
        import('../../src/components/users/user_header.js'),
        import('../../src/services/rights_service.js'),
        import('../../src/app_config.js'),
        import('../../src/services/localization_service.js'),
    ]);
    t.after(() => dom.window.close());
    t.mock.method(LocalizationService, 'tr', key => ({
        'FeatureUser.addEvent': 'Vytvořit vlastní akci',
        'FeatureUser.addEventShort': '+ Akce',
    }[key] || key));
    const previousLink = AppConfig.webLink;
    const previousContext = RightsService._context;
    t.after(() => { AppConfig.webLink = previousLink; RightsService._context = previousContext; });
    const header = new UserHeader();
    for (const [link, organization, visible] of [
        ['https://vstupenky.online', { IS_REGISTRATION_ENABLED: true }, true],
        ['https://vstupenky.online', { IS_REGISTRATION_ENABLED: false }, false],
        ['https://vstupenky.online', { IS_REGISTRATION_ENABLED: null }, false],
        ['https://vstupenky.online', {}, false],
        ['https://vstupenky.online', undefined, false],
        ['https://hvezdamorska.festapp.net', { IS_REGISTRATION_ENABLED: true }, false],
    ]) {
        AppConfig.webLink = link;
        header.context = RightsService._context = { organization };
        header.render();
        const button = header.querySelector('.btn-add-event');
        assert.equal(!!button, visible, `${link}, ${JSON.stringify(organization)}`);
        assert.ok(header.querySelector('.btn-sign-in'), 'existing users can still sign in');
        if (visible) {
            assert.equal(button.getAttribute('aria-label'), 'Vytvořit vlastní akci');
            assert.equal(button.querySelector('.add-event-full').textContent, 'Vytvořit vlastní akci');
            assert.equal(button.querySelector('.add-event-short').textContent, '+ Akce');
        }
    }
});
