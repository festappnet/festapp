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
    page.currentSession = { payload: { form: 'test' } };
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
