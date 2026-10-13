import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';

register('../css_loader.mjs', import.meta.url);

for (const role of ['occasion editor', 'unit editor', 'visitor']) {
  test(`${role}: edit button follows permissions through order completion`, async (t) => {
    const dom = new JSDOM('<div id="form-page-container"></div>', {
      url: 'https://example.test/form/test',
    });
    global.window = dom.window;
    global.document = dom.window.document;
    global.HTMLElement = dom.window.HTMLElement;
    global.CustomEvent = dom.window.CustomEvent;
    window.scrollTo = () => {};
    t.after(() => dom.window.close());

    const [{ FormPage }, { DbForms }, { FormNetwork }, { RouterService },
      { RightsService }, { FormAvailabilityService }] = await Promise.all([
      import('../../src/components/forms/form_page.js'),
      import('../../src/components/forms/db_forms.js'),
      import('../../src/components/forms/form_network.js'),
      import('../../src/services/router_service.js'),
      import('../../src/services/rights_service.js'),
      import('../../src/components/forms/form_availability_service.js'),
    ]);
    const model = { communicationTone: 'formal', visibleFields: [] };
    const oldContext = RightsService._context;
    t.after(() => { RightsService._context = oldContext; });
    RightsService._context = {
      occasion: { link: 'event' },
      occasion_user: { is_editor_order_view: role === 'occasion editor' },
      unit_user: { is_editor_view: role === 'unit editor' },
    };
    t.mock.method(DbForms, 'getFormByLink', async () => model);
    t.mock.method(RightsService, 'updateAppData', async () => true);
    t.mock.method(FormAvailabilityService, 'getStatus', () => ({}));
    t.mock.method(FormAvailabilityService, 'renderStatus', () => false);
    t.mock.method(FormNetwork, 'submitOrder', async () => ({ success: true, data: { code: 200 } }));
    t.mock.method(RouterService, 'pushOverlayState', () => {});
    const navigate = t.mock.method(RouterService, 'navigateToFlutterRoute', async () => {});

    const page = new FormPage('form-page-container');
    t.mock.method(page, 'applyTheme', () => {});
    t.mock.method(page, 'renderForm', () => {
      page.host.innerHTML = '<form></form>';
      page.currentSession = { payload: { form: 'test' } };
    });
    await page.init('test');
    const editor = role !== 'visitor';
    assert.equal(!!document.querySelector('.fab-edit'), editor);

    page.submitOrder(page.host.querySelector('form'), model);
    await new Promise(resolve => setImmediate(resolve));
    const overlay = document.querySelector('.fullscreen-result-overlay');
    assert.ok(overlay, 'order confirmation must be visible');
    const button = document.querySelector('.fab-edit');
    assert.equal(!!button, editor, 'edit access must survive a successful order');
    if (editor) {
      assert.ok(Number(button.style.zIndex) > Number(overlay.style.zIndex),
        'edit button must remain above the confirmation');
      button.click();
      assert.equal(navigate.mock.calls[0].arguments[0], '/event/reservations');
    }

    window.dispatchEvent(new window.PopStateEvent('popstate'));
    assert.equal(!!document.querySelector('.fab-edit'), editor,
      'edit access must survive closing the confirmation');
    assert.equal(document.querySelectorAll('.fab-edit').length, editor ? 1 : 0);
    page.cleanup();
    assert.equal(document.querySelector('.fab-edit'), null,
      'leaving the form must still remove the edit button');
  });
}
