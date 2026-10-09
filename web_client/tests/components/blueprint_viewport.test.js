import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { BlueprintRenderer } from '../../src/components/blueprint/blueprint_renderer.js';

function fixture(t, width = 390, mapHeight = 434) {
    const dom = new JSDOM('<div id="map"></div>');
    const originals = Object.fromEntries(['window', 'document', 'ResizeObserver'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
    globalThis.window = dom.window;
    globalThis.document = dom.window.document;
    globalThis.ResizeObserver = class { observe() {} disconnect() {} };
    const restoreGlobals = () => {
        for (const [key, descriptor] of Object.entries(originals)) {
            if (descriptor) Object.defineProperty(globalThis, key, descriptor);
            else delete globalThis[key];
        }
    };
    // JSDOM has no layout engine: emulate the mobile toolbar consuming 66px.
    Object.defineProperty(dom.window.HTMLElement.prototype, 'clientWidth', { configurable: true, get: () => width });
    Object.defineProperty(dom.window.HTMLElement.prototype, 'clientHeight', { configurable: true,
        get() { return this.classList.contains('blueprint-map-viewport') ? mapHeight : mapHeight + 66; },
    });
    const renderer = new BlueprintRenderer(document.getElementById('map'));
    renderer.render({ configuration: { dimensions: { width: 20, height: 20 } }, objects: [] }, () => {});
    t.after(() => { renderer.destroy(); dom.window.close(); restoreGlobals(); });
    return renderer;
}

test('zoom controls stay outside the pannable seat viewport, including after rerender', t => {
    const renderer = fixture(t);
    for (let pass = 0; pass < 2; pass++) {
        assert.equal(renderer.transformContainer.parentElement, renderer.viewport);
        assert.equal(renderer.viewport.contains(renderer.zoomInButton), false);
        assert.equal(renderer.gestureController.container, renderer.viewport);
        assert.equal(renderer.container.querySelectorAll('.blueprint-zoom-controls').length, 1);
        if (pass === 0) renderer.setScalingMode('min');
    }
});

test('bottom-right seats can pan above the mobile toolbar and stay there after snapback', t => {
    const renderer = fixture(t);
    const { controller } = renderer;
    assert.equal(controller.dims.viewportH, 434, 'pan bounds must exclude the mobile toolbar');
    renderer.zoomBy(2.5);
    renderer.handlePan(-10000, -10000, 0, 0);
    const bounded = controller.getConstrainedState();
    controller.setState(bounded.x, bounded.y, bounded.scale);
    // Center of the last seat in a 20x20 plan, whose seat size is 60.
    const lastSeatCenter = 19.5 * renderer.seatSize;
    const x = bounded.x + lastSeatCenter * bounded.scale;
    const y = bounded.y + lastSeatCenter * bounded.scale;
    assert.ok(x > 0 && x < controller.dims.viewportW);
    assert.ok(y > 0 && y < 434, 'the last seat must remain in the map, above the controls');
    assert.equal(controller.shouldSnapBack(), false);
});

test('desktop sizing uses the full unobstructed map viewport', t => {
    const renderer = fixture(t, 1200, 700);
    assert.equal(renderer.controller.dims.viewportW, 1200);
    assert.equal(renderer.controller.dims.viewportH, 700);
});
