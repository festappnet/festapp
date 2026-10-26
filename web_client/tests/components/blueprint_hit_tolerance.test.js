import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { emptyLayout } from '../helpers/venue_layout_kernel.js';
import { mount } from '@festapp/venue-layout';

const a = '00000000-0000-4000-8000-000000000001';
const b = '00000000-0000-4000-8000-000000000002';
const seat = (id, x, rotation = 0) => ({id, kind: 'seat', transform: {x, y: 100, rotation}, width: 40, height: 40});

function fixture(t, nodes, scale = 1, options = {}) {
    const dom = new JSDOM('<div id="host"></div>');
    const keys = ['window', 'document', 'DOMPoint'];
    const originals = keys.map(key => Object.getOwnPropertyDescriptor(globalThis, key));
    globalThis.window = dom.window;
    globalThis.document = dom.window.document;
    // JSDOM has no SVG layout: model only the camera's screen transform.
    globalThis.DOMPoint = class {
        constructor(x, y) { this.x = x; this.y = y; }
        matrixTransform(m) { return {x: this.x * m.a + m.e, y: this.y * m.d + m.f}; }
    };
    const matrix = {a: scale, b: 0, c: 0, d: scale, e: 20, f: 30,
        inverse: () => ({a: 1 / scale, d: 1 / scale, e: -20 / scale, f: -30 / scale})};
    dom.window.SVGElement.prototype.getScreenCTM = () => matrix;
    dom.window.SVGElement.prototype.getBoundingClientRect = () => ({left: 0, top: 0, right: 800, bottom: 600, width: 800, height: 600});
    const calls = [];
    const viewer = mount(document.getElementById('host'), {
        document: {...emptyLayout, nodes},
        onSelectionRequested: async (ids, selecting) => { calls.push({ids: [...ids], selecting}); return {accepted: true}; },
        ...options,
    });
    t.after(() => {
        viewer.dispose(); dom.window.close();
        keys.forEach((key, index) => {
            if (originals[index]) Object.defineProperty(globalThis, key, originals[index]);
            else delete globalThis[key];
        });
    });
    const click = (x, y) => viewer.click({target: viewer.svg, clientX: x, clientY: y});
    return {viewer, calls, click, screen: (x, y) => [20 + x * scale, 30 + y * scale]};
}

for (const scale of [0.15, 0.5, 1, 2]) {
    test(`near misses select once with screen-space tolerance at scale ${scale}`, async t => {
        const {click, calls, screen} = fixture(t, [seat(a, 100)], scale);
        const [right, middle] = screen(120, 100);
        await click(right + 7, middle);
        assert.deepEqual(calls, [{ids: [a], selecting: true}]);
        await click(right + 9, middle);
        assert.equal(calls.length, 1, 'outside the eight-pixel radius');
        await click(...screen(100, 100));
        assert.deepEqual(calls.at(-1), {ids: [a], selecting: false});
    });
}

test('nearest seat wins; exact occupied hits and near misses never jump to a free neighbor', async t => {
    const {click, calls, screen, viewer} = fixture(t, [seat(a, 100), seat(b, 152)]);
    await click(...screen(125, 100));
    await click(...screen(127, 100));
    assert.deepEqual(calls.map(call => call.ids), [[a], [b]]);
    calls.length = 0;
    viewer.update({seatPresentation: {[b]: {status: 'occupied', selectable: false}}});
    await click(...screen(127, 100));
    await click(...screen(133, 100));
    assert.deepEqual(calls, []);
});

test('rotated seats use the real kernel outline and retain atomic selection units', async t => {
    const {click, calls, screen} = fixture(t, [seat(a, 100, 45), seat(b, 200)], 1, {
        document: {...emptyLayout, nodes: [seat(a, 100, 45), seat(b, 200)],
            selectionUnits: [{id: '00000000-0000-4000-8000-000000000009', kind: 'atomic', nodeIds: [a, b]}]},
    });
    await click(...screen(128, 100));
    assert.deepEqual(calls, [{ids: [a, b], selecting: true}]);
});

test('drag suppression, viewport boundaries and standing areas keep their existing behavior', async t => {
    const standing = {...seat(b, 200), kind: 'capacityArea', capacity: 20};
    const {click, calls, screen, viewer} = fixture(t, [seat(a, 100), standing]);
    viewer.suppressClick = true;
    await click(...screen(125, 100));
    assert.deepEqual(calls, []);
    assert.equal(viewer.suppressClick, false);
    await click(...screen(225, 100));
    await click(-1, 100);
    assert.deepEqual(calls, [], 'near misses only extend seats');
    await click(...screen(100, 100));
    assert.equal(calls.length, 1, 'next intentional click works');
});
