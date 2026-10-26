import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { initMotion } from '../../src/marketing/motion.js';

function fixture() {
  const dom = new JSDOM(`<svg data-hero-sketch><circle class="sketch-pen"/>${['left', 'right'].map(side => `<g data-sketch-side="${side}"><path/></g>`).join('')}</svg><svg data-closing-art><circle data-closing-pen/><g data-closing-motif="ticket"><path/></g></svg>`, {pretendToBeVisual: true});
  const win = dom.window, doc = win.document;
  let geometryReads = 0, next = 0;
  const frames = new Map(), observers = [];
  win.matchMedia = () => Object.assign(new win.EventTarget(), {matches: false});
  win.requestAnimationFrame = callback => { frames.set(++next, callback); return next; };
  win.cancelAnimationFrame = id => frames.delete(id);
  win.IntersectionObserver = class {
    constructor(callback) { this.callback = callback; observers.push(this); }
    observe(target) { this.target = target; }
    unobserve() {}
    disconnect() {}
  };
  for (const element of doc.querySelectorAll('g')) {
    element.transform = {baseVal: {consolidate: () => ({matrix: {a: 1, b: 0}})}};
    element.getScreenCTM = () => { geometryReads++; return {a: 1, b: 0}; };
  }
  for (const path of doc.querySelectorAll('path')) {
    path.getTotalLength = () => 100;
    path.getPointAtLength = () => ({x: 0, y: 0});
  }
  doc.querySelector('[data-hero-sketch]').createSVGPoint = () => ({matrixTransform: () => ({x: 0, y: 0})});
  const tick = time => { const pending = [...frames.values()]; frames.clear(); pending.forEach(callback => callback(time)); };
  const visible = (selector, isIntersecting) => observers.filter(o => o.target?.matches(selector)).forEach(o => o.callback([{target: o.target, isIntersecting}]));
  const cleanup = initMotion(doc);
  return {win, doc, frames, tick, visible, reads: () => geometryReads, cleanup: () => { cleanup(); win.close(); }};
}

test('SVG drawing frames do not force geometry reads after initialization', () => {
  const f = fixture();
  try {
    f.visible('[data-hero-sketch]', true); f.visible('[data-closing-art]', true);
    const initial = f.reads();
    f.tick(0); f.tick(200); f.tick(400); f.tick(3000);
    assert.equal(f.reads(), initial, 'animation must not read layout between SVG writes');
    f.win.dispatchEvent(new f.win.Event('resize'));
    assert.ok(f.reads() > initial, 'resizing refreshes SVG scale');
  } finally { f.cleanup(); }
});

test('decorative loops stop outside the viewport, in hidden tabs, and on cleanup', () => {
  const f = fixture();
  try {
    f.visible('[data-hero-sketch]', true); f.visible('[data-closing-art]', true);
    assert.equal(f.frames.size, 2);
    f.visible('[data-hero-sketch]', false); f.visible('[data-closing-art]', false);
    assert.equal(f.frames.size, 0, 'offscreen decoration must not keep drawing');
    f.visible('[data-hero-sketch]', true);
    assert.equal(f.frames.size, 1);
    Object.defineProperty(f.doc, 'hidden', {value: true, configurable: true});
    f.doc.dispatchEvent(new f.win.Event('visibilitychange'));
    assert.equal(f.frames.size, 0, 'background tab must not keep drawing');
    Object.defineProperty(f.doc, 'hidden', {value: false, configurable: true});
    f.doc.dispatchEvent(new f.win.Event('visibilitychange'));
    assert.equal(f.frames.size, 1);
  } finally { f.cleanup(); }
  assert.equal(f.frames.size, 0);
});
