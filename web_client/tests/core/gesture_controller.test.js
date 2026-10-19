
import test from 'node:test';
import assert from 'node:assert';
import { GestureController } from '../../src/components/blueprint/gesture_controller.js';

// Mock DOM
class MockElement {
    constructor() {
        this.listeners = {};
        this.style = {};
    }
    addEventListener(event, handler) {
        if (!this.listeners[event]) this.listeners[event] = [];
        this.listeners[event].push(handler);
    }
    removeEventListener(event, handler) {
        if (this.listeners[event]) {
            this.listeners[event] = this.listeners[event].filter(h => h !== handler);
        }
    }
    dispatchEvent(event) {
        if (this.listeners[event.type]) {
            this.listeners[event.type].forEach(h => h(event));
        }
    }
    getBoundingClientRect() {
        return { left: 0, top: 0, width: 100, height: 100 };
    }
}

global.window = new MockElement();
global.document = new MockElement();
global.document.body = new MockElement();
global.document.documentElement = new MockElement();

test('GestureController - Pan', (t) => {
    // Reset Mocks for isolation
    global.window = new MockElement();
    global.document = new MockElement();
    
    const container = new MockElement();
    let panData = null;
    
    const controller = new GestureController(container, {
        onPan: (dx, dy) => {
            panData = { dx, dy };
        }
    });

    // Simulate mouse interaction
    // Mouse Down
    container.onmousedown({ clientX: 100, clientY: 100, preventDefault: () => {} });
    
    // Mouse Move
    global.window.dispatchEvent({ type: 'mousemove', clientX: 110, clientY: 120, preventDefault: () => {} });
    
    assert.deepStrictEqual(panData, { dx: 10, dy: 20 });
    
    // Mouse Up
    global.window.dispatchEvent({ type: 'mouseup' });
    
    // Move after up should not pan
    panData = null;
    global.window.dispatchEvent({ type: 'mousemove', clientX: 120, clientY: 130, preventDefault: () => {} });
    assert.strictEqual(panData, null);
});

test('GestureController - Zoom / Pinch', (t) => {
    // Reset Mocks for isolation
    global.window = new MockElement();
    global.document = new MockElement();

    const container = new MockElement();
    let pinchData = null;
    
    const controller = new GestureController(container, {
        onPinch: (dx, dy, factor) => {
            pinchData = { dx, dy, factor };
        }
    });

    // Helper for touch event
    const createTouchEvent = (touches) => ({
        type: 'touchmove',
        touches: touches.map(t => ({ clientX: t.x, clientY: t.y })),
        preventDefault: () => {}
    });

    // 2 Fingers Start
    // Dist = 100 (0,0 to 100,0)
    // Center = 50,0
    const startEvent = {
        type: 'touchstart',
        touches: [
            { clientX: 0, clientY: 0 },
            { clientX: 100, clientY: 0 }
        ],
        preventDefault: () => {}
    };
    
    // We need to trigger the listener attached to container
    // But in our mock, we attached via addEventListener
    const touchStartHandler = container.listeners['touchstart'][0];
    touchStartHandler(startEvent);
    
    // Move 1 (Set Anchor)
    const moveEvent1 = {
        type: 'touchmove',
        touches: [
            { clientX: -50, clientY: 0 },
            { clientX: 150, clientY: 0 }
        ],
        preventDefault: () => {}
    };
    const touchMoveHandler = global.window.listeners['touchmove'][0];
    touchMoveHandler(moveEvent1);
    
    // Move 2 (Trigger Pinch) - Expand more
    const moveEvent2 = {
        type: 'touchmove',
        touches: [
            { clientX: -100, clientY: 0 },
            { clientX: 200, clientY: 0 }
        ],
        preventDefault: () => {}
    };
    touchMoveHandler(moveEvent2);

    // Initial Dist = 100
    // Move 1 Dist = 200 (Anchor set here: lastDist=200)
    // Move 2 Dist = 300
    // Factor = 300 / 200 = 1.5
    
    assert.ok(pinchData !== null, "Pinch data should not be null");
    assert.ok(Math.abs(pinchData.factor - 1.5) < 0.001, `Factor was ${pinchData.factor}, expected 1.5`);
});

test('GestureController - Tap', (t) => {
     // Reset Mocks for isolation
     global.window = new MockElement();
     global.document = new MockElement();
     
     const container = new MockElement();
     let tapped = false;
     
     const controller = new GestureController(container, {
         onTap: (x, y) => {
             tapped = true;
         }
     });
     
     const touchStartHandler = container.listeners['touchstart'][0];
     // console.error("Test: Firing TouchStart");
     touchStartHandler({
        type: 'touchstart',
         touches: [{ clientX: 100, clientY: 100 }],
         preventDefault: () => {},
         cancelable: true
     });
     
     // Verify state if possible, but state is private/internal
     // Assuming controller.state is accessible (it is)
     
     const touchEndHandler = global.window.listeners['touchend'][0];
     touchEndHandler({
         type: 'touchend',
         touches: []
     });
          
     assert.strictEqual(tapped, true);
});
