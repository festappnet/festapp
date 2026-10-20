import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';

register('../css_loader.mjs', import.meta.url);

test('a successful fast submission keeps its confirmation visible after closing the preview', async () => {
  const dom = new JSDOM(`<!doctype html><html><body>
    <div id="form-page-container"></div>
    <div id="order-preview-overlay"></div>
  </body></html>`, { url: 'https://example.test/form/test' });

  global.window = dom.window;
  global.document = dom.window.document;
  global.HTMLElement = dom.window.HTMLElement;
  global.CustomEvent = dom.window.CustomEvent;
  window.scrollTo = () => {};

  const [{ FormPage }, { FormNetwork }, { RouterService }] = await Promise.all([
    import('../../src/components/forms/form_page.js'),
    import('../../src/components/forms/form_network.js'),
    import('../../src/services/router_service.js'),
  ]);

  const originalSubmitOrder = FormNetwork.submitOrder;
  const originalGoBack = RouterService.goBackProgrammatically;
  const originalPushOverlayState = RouterService.pushOverlayState;

  try {
    FormNetwork.submitOrder = async () => ({ success: true, data: { code: 200 } });
    RouterService.goBackProgrammatically = () => {
      setTimeout(() => window.dispatchEvent(new window.PopStateEvent('popstate')), 0);
    };
    RouterService.pushOverlayState = () => {};

    const page = new FormPage('form-page-container');
    page.currentSession = { awaitPendingReservations: async () => {}, captureReservationCapability: () => null, completeReservation: () => {}, payload: { form: 'test' } };
    page.cleanup = () => {};
    page.renderForm = () => {};

    page.submitOrder(document.createElement('form'), {
      communicationTone: 'formal',
      visibleFields: [],
    });

    await new Promise(resolve => setTimeout(resolve, 25));

    assert.ok(
      document.querySelector('.fullscreen-result-overlay .result-title'),
      'the confirmation disappeared when the delayed preview popstate arrived',
    );
  } finally {
    FormNetwork.submitOrder = originalSubmitOrder;
    RouterService.goBackProgrammatically = originalGoBack;
    RouterService.pushOverlayState = originalPushOverlayState;
    dom.window.close();
  }
});

test('demo checkout and waitlist use the normal result without sending or storing registration', async () => {
  const dom = new JSDOM('<div id="form-page-container"></div>', { url: 'https://example.test/form/demo' });
  global.window = dom.window;
  global.document = dom.window.document;
  global.HTMLElement = dom.window.HTMLElement;
  global.CustomEvent = dom.window.CustomEvent;
  window.scrollTo = () => {};
  const [{ FormPage }, { FormNetwork }, { RouterService }, { LocalizationService }, cs] = await Promise.all([
    import('../../src/components/forms/form_page.js'),
    import('../../src/components/forms/form_network.js'),
    import('../../src/services/router_service.js'),
    import('../../src/services/localization_service.js'),
    import('../../../assets/translations/cs.json', { with: { type: 'json' } }),
  ]);
  const originalSubmit = FormNetwork.submitOrder;
  const originalPush = RouterService.pushOverlayState;
  const originalTranslations = LocalizationService.translations;
  try {
    LocalizationService.translations = cs.default;
    let writes = 0;
    FormNetwork.submitOrder = async () => { writes++; throw new Error('real checkout called'); };
    RouterService.pushOverlayState = () => {};
    for (const registrationMode of ['regular', 'waitlist']) {
      const page = new FormPage('form-page-container');
      page.currentSession = { awaitPendingReservations: async () => {}, captureReservationCapability: () => null, completeReservation: () => {}, payload: { form: 'demo', email: 'private@example.invalid' } };
      page.waitlistCommands = { command: async () => { writes++; throw new Error('real waitlist called'); } };
      page.cleanup = () => {};
      page.submitOrder(document.createElement('form'), {
        demoSimulation: true, registrationMode, visibleFields: [], communicationTone: 'formal',
      });
      await new Promise(resolve => setTimeout(resolve, 25));
      const result = document.querySelector('.fullscreen-result-overlay');
      assert.equal(result.querySelector('.result-title').textContent, cs.default.DemoOccasions.formComplete);
      assert.equal(result.querySelector('.result-subtitle').textContent, cs.default.DemoOccasions.formResult);
      assert.equal(result.querySelector('.result-payment-details').textContent.trim(), '');
      assert.equal(result.querySelector('.result-order-symbol').textContent.trim(), '');
      assert.equal(result.textContent.includes('private@example.invalid'), false);
      result.remove();
    }
    assert.equal(writes, 0);
  } finally {
    FormNetwork.submitOrder = originalSubmit;
    RouterService.pushOverlayState = originalPush;
    LocalizationService.translations = originalTranslations;
    dom.window.close();
  }
});

for (const viewFails of [false, true]) {
  test(`waitlist registration opens the shared overview and preserves confirmation on view failure=${viewFails}`, async t => {
    const dom = new JSDOM('<div id="form-page-container"></div>', {url: 'https://example.test/form/test'});
    Object.assign(globalThis, {window: dom.window, document: dom.window.document,
      HTMLElement: dom.window.HTMLElement, CustomEvent: dom.window.CustomEvent});
    window.scrollTo = () => {};
    t.after(() => dom.window.close());
    const [{FormPage}, {RouterService}] = await Promise.all([
      import('../../src/components/forms/form_page.js'), import('../../src/services/router_service.js'),
    ]);
    t.mock.method(RouterService, 'pushOverlayState', () => {});
    t.mock.method(RouterService, 'goBackProgrammatically', () => window.dispatchEvent(new window.PopStateEvent('popstate')));
    const page = new FormPage('form-page-container');
    page.currentLink = 'test';
    const model = {key: 'test-key', registrationMode: 'waitlist', visibleFields: [], communicationTone: 'formal'};
    page.currentSession = { awaitPendingReservations: async () => {}, captureReservationCapability: () => null, completeReservation: () => {},formModel: model, payload: {fields: []}, state: {tickets: [{fields: []}]}};
    let registrations = 0, reads = 0;
    const token = 'a'.repeat(64);
    page.waitlistCommands = {
      command: async () => { registrations++; return {code: 200, order: {id: 12},
        orderOverviewUrl: `https://example.test/order?order_id=12&token=${token}`}; },
      overview: async scope => {
        reads++;
        assert.deepEqual(scope, {orderId: 12, token});
        if (viewFails) throw new Error('offline');
        return {root: {title: 'Synthetic', symbol: 'REGISTERED'}, people: [], offers: [], orders: [], serverTime: '2026-10-15T12:00:00Z'};
      },
    };
    page.submitOrder(document.createElement('form'), model);
    await new Promise(resolve => setTimeout(resolve, 30));
    assert.equal(registrations, 1);
    assert.equal(reads, 1);
    assert.ok(document.querySelector('.fullscreen-result-overlay .success-color'), 'committed registration stays successful');
    assert.equal(window.location.search, `?order_id=12&token=${token}`);
    assert.equal(window.location.hash, '');
    assert.equal(JSON.stringify(window.history.state).includes(token), false);
    assert.ok(viewFails ? page.host.querySelector('[role=alert]') : page.host.textContent.includes('REGISTERED'));
    document.querySelector('.btn-back-to-form').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(document.querySelector('.fullscreen-result-overlay'), null);
    assert.equal(registrations, 1, 'return must never repeat registration');
    page.cleanup();
  });
}
