import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';

register('../css_loader.mjs', import.meta.url);

const catalog = locale => JSON.parse(readFileSync(new URL(`../../../assets/translations/${locale}.json`, import.meta.url)));

test('ticketing account navigation does not require administration privileges', async t => {
    const dom = new JSDOM('<body></body>', { url: 'https://vstupenky.online/' });
    Object.assign(globalThis, {
        window: dom.window, document: dom.window.document,
        HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements,
    });
    const [{ UserHeader }, { RightsService }, { RouterService }, { AppConfig }, { LocalizationService }] = await Promise.all([
        import('../../src/components/users/user_header.js'),
        import('../../src/services/rights_service.js'),
        import('../../src/services/router_service.js'),
        import('../../src/app_config.js'),
        import('../../src/services/localization_service.js'),
    ]);
    const originalContext = RightsService._context;
    const originalLink = AppConfig.webLink;
    const originalTranslations = LocalizationService.translations;
    LocalizationService.translations = catalog('cs');
    t.after(() => {
        RightsService._context = originalContext;
        AppConfig.webLink = originalLink;
        LocalizationService.translations = originalTranslations;
        dom.window.close();
    });
    let navigations = 0;
    t.mock.method(RouterService, 'navigateToAdmin', () => { navigations++; });
    for (const [marketing, path] of [[false, '/events'], [true, '/'], [true, '/rezervace-mist/'], [false, '/napoveda/odbaveni/']]) {
        window.history.replaceState(null, '', path);
        AppConfig.webLink = 'https://vstupenky.online';
        RightsService._context = {
            user_info: { id: 'signed-in-account', name: 'Test', units: [] },
            capabilities: {},
        };
        const header = new UserHeader();
        if (marketing) header.setAttribute('data-marketing', '');
        document.body.appendChild(header);
        const navigation = header.querySelector('.header-public-navigation');
        assert.ok(navigation, 'public navigation belongs to the shared header on catalogue and marketing pages');
        assert.deepEqual([...navigation.querySelectorAll('a')].map(a => a.getAttribute('href')), [path === '/' ? '/events' : '/', '/napoveda/']);
        assert.equal(navigation.querySelector('a').textContent, path === '/' ? 'Najít akci' : 'Pro pořadatele');
        assert.equal(header.querySelectorAll('a[href="/napoveda/"]').length, 1, 'help is not duplicated');
        assert.equal(navigation.closest('.header-actions'), null, 'site navigation stays outside account actions');
        assert.equal(RightsService.canSeeAdmin(), false);
        assert.equal(RightsService.canSeeReservations(), false);
        const button = header.querySelector('.btn-admin');
        assert.ok(button, 'signed-in accounts can enter My events even without privileged capabilities');
        const before = navigations;
        button.click();
        assert.equal(navigations, before + 1, 'use the existing signed-in routing and access checks');
        assert.equal(RightsService.canSeeAdmin(), false, 'navigation grants no administration rights');
        RightsService._context = { organization: {} };
        RightsService._notifyListeners();
        assert.equal(header.querySelector('.btn-admin'), null, 'sign-out removes personal navigation');
        assert.ok(header.querySelector('.header-public-navigation'), 'help stays available after sign-out');
        header.remove();
    }
    document.documentElement.lang = 'en';
    LocalizationService.translations = catalog('en');
    dom.window.history.replaceState({}, '', '/en/whats-new');
    const englishHeader = new UserHeader();
    document.body.appendChild(englishHeader);
    const englishNavigation = englishHeader.querySelector('.header-public-navigation');
    assert.equal(englishNavigation.getAttribute('aria-label'), 'Main navigation');
    assert.deepEqual([...englishNavigation.querySelectorAll('a')].map(a => a.textContent), ['For organizers', 'Help']);
    englishHeader.remove();

    document.documentElement.lang = 'sk';
    LocalizationService.translations = catalog('sk');
    dom.window.history.replaceState({}, '', '/events');
    RightsService._context = { organization: { IS_REGISTRATION_ENABLED: true } };
    const slovakHeader = new UserHeader();
    document.body.appendChild(slovakHeader);
    const slovakNavigation = slovakHeader.querySelector('.header-public-navigation');
    assert.equal(slovakNavigation.getAttribute('aria-label'), 'Hlavná navigácia');
    assert.deepEqual([...slovakNavigation.querySelectorAll('a')].map(a => [a.textContent, a.getAttribute('href')]),
        [['Pre organizátorov', '/'], ['Pomoc', '/napoveda/']]);
    assert.equal(slovakHeader.querySelector('.btn-add-event').getAttribute('aria-label'), 'Vytvoriť podujatie zdarma');
    assert.equal(slovakHeader.querySelector('.add-event-short').textContent, 'Vytvoriť zdarma');
    slovakHeader.remove();

    document.documentElement.lang = 'cs';
    LocalizationService.translations = catalog('cs');
    AppConfig.webLink = 'https://hvezdamorska.festapp.net';
    RightsService._context = { user_info: { id: 'ordinary-attendee' }, capabilities: {} };
    const header = new UserHeader();
    document.body.appendChild(header);
    assert.equal(header.querySelector('.btn-admin'), null, 'app tenants retain capability-based administration entry');
    header.remove();
});
