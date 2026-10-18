import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { SvgUtils } from '../../src/components/blueprint/svg_utils.js';
import { BlueprintRenderer } from '../../src/components/blueprint/blueprint_renderer.js';

export const staticSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><defs><linearGradient id="gradient"><stop offset="0" stop-color="red"/></linearGradient><clipPath id="clip"><rect width="100" height="100"/></clipPath><path id="shape" d="M0 0L10 10"/></defs><style>.paint { fill:url(#gradient); stroke:blue } @import 'https://evil.invalid/x.css';</style><g transform="translate(1,2)" clip-path="url(#clip)"><path class="paint" d="M0 0L100 100"/><text x="10" y="20">Stage</text><use href="#shape"/></g></svg>`;
function fixture(t) {
  let cleanup = () => {};
  const dom = new JSDOM('<div id="map"></div>');
  const keys = ['window', 'document', 'ResizeObserver'];
  const previous = keys.map(k => Object.getOwnPropertyDescriptor(globalThis, k));
  globalThis.window = dom.window; globalThis.document = dom.window.document;
  globalThis.ResizeObserver = class { observe() {} disconnect() {} };
  Object.defineProperty(dom.window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
  Object.defineProperty(dom.window.HTMLElement.prototype, 'clientHeight', { get: () => 400 });
  t.after(() => { cleanup(); dom.window.close(); keys.forEach((k,i) => previous[i] ? Object.defineProperty(globalThis,k,previous[i]) : delete globalThis[k]); });
  return callback => { cleanup = callback; };
}
test('static SVG keeps gradients, clipping, local use, text and CSS while removing imports', t => {
  fixture(t);
  const result = SvgUtils.prepareBackgroundSvg(staticSvg);
  const host = document.createElement('div'); host.innerHTML = result.svg;
  for (const tag of ['svg', 'defs', 'linearGradient', 'clipPath', 'text', 'use']) assert.ok(host.querySelector(tag), tag);
  assert.equal(host.querySelector('use').getAttribute('href'), '#shape');
  assert.match(host.querySelector('style').textContent, /url\(#gradient\)/);
  assert.doesNotMatch(result.svg, /evil.invalid|@import/);
  assert.equal(host.querySelector('svg').getAttribute('viewBox'), '0 0 200 100');
});
test('active and malformed SVG fail closed without poisoning rich HTML or URL backgrounds', t => {
  fixture(t);
  const payload = `<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><script>alert(1)</script><foreignObject><iframe/></foreignObject><animate attributeName="href" to="javascript:alert(1)"/><set attributeName="onload" to="alert(1)"/><use href="https://evil.invalid/x.svg#x"/><image href="data:image/svg+xml,bad"/><path style="fill:url(https://evil.invalid/x);stroke:red"/><style>.x{fill:u\\72l(https://evil.invalid/x);stroke:blue}</style></svg>`;
  const result = SvgUtils.prepareBackgroundSvg(payload);
  assert.doesNotMatch(result.svg, /onload|script|foreignObject|iframe|animate|<set|evil.invalid|data:image/);
  assert.match(result.svg, /stroke:red/);
  for (const value of ['<svg><g></svg>', '<svg><script>', '<html><svg/></html>', '<svg xmlns="http://evil.invalid"/>']) assert.equal(SvgUtils.prepareBackgroundSvg(value).svg, '');
  for (const value of ['javascript:alert(1)', 'data:image/svg+xml,bad', 'httpx://evil']) assert.equal(SvgUtils.prepareBackgroundSvg(value).svg, '');
  assert.equal(SvgUtils.prepareBackgroundSvg('https://images.example/map.png').isSvg, false);
});
test('renderer keeps seat callbacks and scaling with sanitized or rejected backgrounds', t => {
  const cleanup = fixture(t);
  const renderer = new BlueprintRenderer(document.getElementById('map'));
  cleanup(() => renderer.destroy());
  for (const background_svg of [staticSvg, '<svg><script>']) {
    let selected;
    renderer.render({ background_svg, configuration: { dimensions: { width: 20, height: 20 } }, objects: [{ id: 1, type: 'spot', x: 1, y: 1, title: 'A1' }] }, obj => { selected = obj.id; });
    renderer.setScalingMode('min');
    renderer.zoomBy(1.2);
    assert.equal(document.querySelector('script'), null);
    const seat = renderer.data.objects[0].element;
    assert.ok(seat);
    seat.click();
    assert.equal(selected, 1);
  }
});
