import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
const initialDom = new JSDOM('', {url: 'https://fixture.invalid'});
globalThis.window = initialDom.window;
globalThis.document = initialDom.window.document;
globalThis.HTMLElement = initialDom.window.HTMLElement;
globalThis.customElements = initialDom.window.customElements;
const { OccasionDetailDialog } = await import('../../src/components/occasion/occasion_detail_dialog.js');
import { FeatureService } from '../../src/components/features/feature_service.js';
import { LocalizationService } from '../../src/services/localization_service.js';

function fixture(t, primaryColor = '123abc') {
  const dom = new JSDOM('', { url: 'https://fixture.invalid' });
  const previous = globalThis.document;
  globalThis.document = dom.window.document;
  t.mock.method(LocalizationService, 'tr', key => key);
  t.mock.method(FeatureService, 'getFeatureDetails', () => ({ primaryColor, reserveButtonTitle: '<img src=x onerror=alert(1)>' }));
  t.after(() => { globalThis.document = previous; dom.window.close(); });
  OccasionDetailDialog.show({ title: '<img src=x onerror=alert(1)>', description: '<h2>Heading</h2><p><b>Bold</b><a href="https://example.com">Link</a><img src="/safe.png" onerror="alert(1)"><a href="javascript:alert(1)">Bad</a><script>alert(1)</script></p>', start_time: '2026-10-18', end_time: '2026-10-19', features: [] });
  return document.querySelector('.overlay');
}
test('actual dialog escapes plain text, sanitizes rich content and preserves reserve action', async t => {
  const overlay = fixture(t);
  assert.equal(overlay.querySelector('h2').textContent, '<img src=x onerror=alert(1)>');
  assert.equal(overlay.querySelector('h2 img'), null);
  assert.equal(overlay.querySelector('.btn-reserve img'), null);
  assert.equal(overlay.querySelector('.dialog-description b').textContent, 'Bold');
  assert.equal(overlay.querySelector('.dialog-description img').getAttribute('src'), '/safe.png');
  assert.equal(overlay.querySelector('script, [onerror], a[href^="javascript:"]'), null);
  assert.equal(overlay.querySelector('.btn-reserve').style.backgroundColor, 'rgb(18, 58, 188)');
  let calls = 0;
  t.mock.method(OccasionDetailDialog, 'handleReserveAction', async () => { calls++; });
  await overlay.querySelector('.btn-reserve').onclick();
  assert.equal(calls, 1);
  assert.equal(overlay.classList.contains('visible'), false);
  assert.equal(document.body.style.overflow, '');
});
test('rejects attribute/color injection and closes with Escape or close button', t => {
  const overlay = fixture(t, 'red;" onclick="alert(1)');
  assert.equal(overlay.querySelector('.btn-reserve').style.backgroundColor, '');
  assert.equal(overlay.querySelector('[onclick]'), null);
  document.dispatchEvent(new document.defaultView.KeyboardEvent('keydown', { key: 'Escape' }));
  assert.equal(overlay.classList.contains('visible'), false);
  overlay.classList.add('visible');
  overlay.querySelector('.close-btn').click();
  assert.equal(overlay.classList.contains('visible'), false);
});
