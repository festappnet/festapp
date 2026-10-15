import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);

test('real header keeps rendered navigation when the overview moves it out of the hidden app', async t => {
    const dom = new JSDOM('<div id="app"><user-header id="universal-header"></user-header></div><main id="form-page-container"></main>', { url: 'https://example.test/form/event' });
    Object.assign(globalThis, { window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements });
    await import('../../src/components/users/user_header.js');
    const { RightsService } = await import('../../src/services/rights_service.js');
    const { FormPage } = await import('../../src/components/forms/form_page.js');
    const previous = RightsService._context;
    t.after(() => { dom.window.close(); RightsService._context = previous; });
    RightsService._context = {};
    RightsService._notifyListeners();
    const page = new FormPage('form-page-container');
    const header = document.getElementById('universal-header');
    const home = header.querySelector('.header-home-link');
    assert.ok(home);
    for (const overview of [true, false, true]) {
        page.setOverviewLayout(overview);
        assert.equal(header.querySelector('.header-home-link'), home, 'DOM reconnection must retain visible navigation');
        assert.equal(RightsService._listeners.filter(listener => listener === header._handleContextChange).length, 1);
    }
});
