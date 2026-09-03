import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';

register('../css_loader.mjs', import.meta.url);

test('the order-result route never exposes a blank overlay while loading code', async () => {
  const dom = new JSDOM(
    '<!doctype html><html><body><div id="form-page-container"></div></body></html>',
    { url: 'https://example.test/form/test' },
  );

  global.window = dom.window;
  global.document = dom.window.document;
  global.HTMLElement = dom.window.HTMLElement;
  global.CustomEvent = dom.window.CustomEvent;
  window.scrollTo = () => {};

  try {
    const { FormPage } = await import('../../src/components/forms/form_page.js');
    const page = new FormPage('form-page-container');

    page.showFullScreenResult(true, { code: 200 }, {
      communicationTone: 'formal',
      visibleFields: [],
    });

    assert.ok(
      document.querySelector('.fullscreen-result-overlay .result-title'),
      'the result overlay was mounted before its content was available',
    );
  } finally {
    await new Promise(resolve => setTimeout(resolve, 25));
    dom.window.close();
  }
});
