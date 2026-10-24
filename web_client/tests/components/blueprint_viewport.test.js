import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { BlueprintRenderer } from '../../src/components/blueprint/blueprint_renderer.js';

function fixture(t, width = 390, mapHeight = 500) {
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
    // JSDOM has no layout engine: model the full map and its bottom-right overlay.
    Object.defineProperty(dom.window.HTMLElement.prototype, 'clientWidth', { configurable: true, get: () => width });
    Object.defineProperty(dom.window.HTMLElement.prototype, 'clientHeight', { configurable: true,
        get: () => mapHeight,
    });
    dom.window.HTMLElement.prototype.getBoundingClientRect = function () {
        if (this.classList.contains('blueprint-zoom-controls')) return { left: width - 66, top: mapHeight - 156, right: width - 16, bottom: mapHeight - 16, width: 50, height: 140 };
        return { left: 0, top: 0, right: width, bottom: mapHeight, width, height: mapHeight };
    };
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

test('edge seats can be dragged clear of the floating controls at every zoom and stay clear after release', t => {
    const renderer = fixture(t);
    const { controller } = renderer;
    assert.equal(controller.dims.viewportH, 500, 'the map keeps its full height');
    for (const zoom of [1, 1.25, 2.5, 5]) {
        renderer.fitToScreen();
        renderer.zoomBy(zoom);
        renderer.handlePan(-10000, -10000, 0, 0);
        const bounded = controller.getConstrainedState();
        controller.setState(bounded.x, bounded.y, bounded.scale);
        const seatCenter = 19.5 * renderer.seatSize;
        const x = bounded.x + seatCenter * bounded.scale;
        const y = bounded.y + seatCenter * bounded.scale;
        assert.ok(x > 0 && x < 324, `last seat clears the controls horizontally at zoom ${zoom}`);
        assert.ok(y > 0 && y < 344, `last seat clears the controls vertically at zoom ${zoom}`);
        assert.equal(controller.shouldSnapBack(), false, 'release must not return the seat under the controls');
    }
});

test('desktop sizing uses the full unobstructed map viewport', t => {
    const renderer = fixture(t, 1200, 700);
    assert.equal(renderer.controller.dims.viewportW, 1200);
    assert.equal(renderer.controller.dims.viewportH, 700);
});

test('seat hit tolerance stays eight screen pixels across zoom and pan', t => {
    const renderer = fixture(t);
    const seat = { id: 1, x: 2, y: 2, state: 'available' };
    renderer.data.objects = [seat];
    const selected = [];
    renderer.onSeatClick = obj => selected.push(obj.id);
    for (const scale of [0.15, 0.5, 1, 2]) {
        renderer.controller.setState(20, 30, scale);
        const right = 20 + 3 * renderer.seatSize * scale;
        const middle = 30 + 2.5 * renderer.seatSize * scale;
        renderer.handleTap(right + 7, middle);
        assert.equal(selected.pop(), 1, `near miss at scale ${scale}`);
        renderer.handleTap(right + 9, middle);
        assert.equal(selected.length, 0, `distant miss at scale ${scale}`);
        renderer.handleTap(right + 7, 30 + 3 * renderer.seatSize * scale + 7);
        assert.equal(selected.length, 0, 'diagonal misses use radial distance');
    }
});

test('nearest seat wins and occupied seats prevent snapping to an available neighbor', t => {
    const renderer = fixture(t);
    renderer.controller.setState(0, 0, 1);
    renderer.data.objects = [
        { id: 1, x: 1, y: 1, state: 'available' },
        { id: 2, x: 2.2, y: 1, state: 'selected_by_me' },
    ];
    const selected = [];
    renderer.onSeatClick = obj => selected.push(obj.id);
    renderer.handleTap(125, 90);
    renderer.handleTap(127, 90);
    assert.deepEqual(selected.splice(0), [1, 2]);
    renderer.data.objects[1].state = 'ordered';
    renderer.handleTap(127, 90);
    assert.deepEqual(selected, [], 'near miss on occupied seat does not select another seat');
    renderer.handleTap(133, 90);
    assert.deepEqual(selected, [2], 'direct hits retain existing callback behavior');
});

test('mouse and touch use tolerant selection once and mouse dragging never selects', t => {
    const renderer = fixture(t);
    renderer.controller.setState(0, 0, 1);
    renderer.data.objects = [{ id: 1, x: 1, y: 1, state: 'available' }];
    const selected = [];
    renderer.onSeatClick = obj => selected.push(obj.id);
    const gesture = renderer.gestureController;
    gesture.callbacks.onInteractionStart = () => {};
    gesture.callbacks.onInteractionEnd = () => {};
    const event = (x, y) => ({ clientX: x, clientY: y, button: 0, preventDefault() {} });
    renderer.viewport.onmousedown(event(125, 90));
    window.dispatchEvent(new window.MouseEvent('mouseup', { clientX: 125, clientY: 90 }));
    renderer.transformContainer.dispatchEvent(new window.MouseEvent('click', { bubbles: true, clientX: 125, clientY: 90 }));
    assert.deepEqual(selected.splice(0), [1], 'one selection per mouse click');
    gesture.onTouchStart({ touches: [event(125, 90)] });
    gesture.onTouchEnd({ touches: [] });
    assert.deepEqual(selected.splice(0), [1], 'touch uses the same tolerance');
    gesture.onMouseDown(event(90, 90));
    gesture.onMouseMove(event(110, 90));
    gesture.onMouseUp(event(110, 90));
    assert.deepEqual(selected, [], 'pan does not toggle a seat');
    renderer.handleTap(-1, 90);
    assert.deepEqual(selected, [], 'input outside the viewport is ignored');
});
