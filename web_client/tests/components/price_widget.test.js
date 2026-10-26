
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { PriceWidget } from '../../src/components/forms/widgets/price_widget.js';
import { formatPrice } from '../../src/utils/formatters.js';

// --- MOCK DOM ENVIROMENT ---
if (typeof document === 'undefined') {
    global.document = {
        createElement: (tag) => {
            return {
                tagName: tag.toUpperCase(),
                style: {},
                classList: {
                    _classes: new Set(),
                    add(c) { this._classes.add(c); },
                    remove(c) { this._classes.delete(c); },
                    contains(c) { return this._classes.has(c); }
                },
                setAttribute() {},
                remove() { this._removed = true; },
                _removed: false,
                set innerHTML(v) { this._innerHTML = v; },
                get innerHTML() { return this._innerHTML; }
            };
        },
        querySelector: () => null,
        getElementById: () => null,
        body: {
            appendChild: () => {}
        },
        documentElement: {
             style: {} 
        }
    };
    global.window = {
        getComputedStyle: () => ({ getPropertyValue: () => '' })
    };
    global.getComputedStyle = global.window.getComputedStyle;
}

// --- MOCK FORM SESSION ---
class MockFormSession {
    constructor(formModel) {
        this.formModel = formModel;
        this.listeners = {};
        this.currentState = { totalPrice: 0, totalItems: 0, currency: 'CZK' };
    }

    addEventListener(event, callback) {
        if (!this.listeners[event]) this.listeners[event] = [];
        this.listeners[event].push(callback);
    }

    removeEventListener(event, callback) {
        if (!this.listeners[event]) return;
        this.listeners[event] = this.listeners[event].filter(cb => cb !== callback);
    }

    // Output
    emitStateChange(newState) {
        this.currentState = { ...this.currentState, ...newState };
        const event = { detail: this.currentState };
        if (this.listeners['state-changed']) {
            this.listeners['state-changed'].forEach(cb => cb(event));
        }
    }
}

describe('PriceWidget Logic', () => {
    let mockContainer;
    let mockSubmitBtn;
    let mockSession;
    let widget;

    beforeEach(() => {
        // Setup Container and Submit Button Mock
        mockSubmitBtn = {
            tagName: 'BUTTON',
            type: 'submit',
            disabled: false,
            style: {},
            classList: {
                _classes: new Set(),
                add(c) { this._classes.add(c); },
                remove(c) { this._classes.delete(c); },
                contains(c) { return this._classes.has(c); }
            }
        };

        mockContainer = {
            querySelector: (sel) => {
                if (sel.includes('button[type="submit"]')) return mockSubmitBtn;
                if (sel === '#dynamic-form') return mockContainer; // self/wrapper
                return null;
            }
        };

        // Allow global search fallback in PriceWidget
        // PriceWidget searches document if container fails, or container.
        // It looks for '#dynamic-form'.
    });

    it('should be HIDDEN and DISABLE submit button when 0 items and 0 price', () => {
        const formModel = { 
            blueprint: null, // Non-blueprint
            visibleFields: [{ type: 'ticket' }] 
        };
        mockSession = new MockFormSession(formModel);
        widget = new PriceWidget(mockSession, mockContainer);

        // ACT: Trigger state 0/0
        widget.render({ totalPrice: 0, totalItems: 0, currency: 'CZK' });

        // ASSERT: Widget should remove element
        assert.ok(!widget.element || widget.element._removed, 'Widget element should be removed/null');
        
        // ASSERT: Submit button should be disabled
        assert.strictEqual(mockSubmitBtn.disabled, true, 'Submit button should be disabled');
        assert.ok(mockSubmitBtn.classList.contains('disabled'), 'Submit button should have disabled class');
    });

    it('should be VISIBLE and ENABLE submit button when items > 0 even if price is 0 (User Request)', () => {
        const formModel = { 
            blueprint: null, 
            visibleFields: [{ type: 'ticket' }] 
        };
        mockSession = new MockFormSession(formModel);
        widget = new PriceWidget(mockSession, mockContainer);

        // ACT: Trigger state 0 price but 1 item
        widget.render({ totalPrice: 0, totalItems: 1, currency: 'CZK' });

        // ASSERT: Widget element should exist
        assert.ok(widget.element, 'Widget element should exist');
        assert.strictEqual(widget.element._removed, false, 'Widget element should not be removed');

        // ASSERT: Submit button should be enabled
        assert.strictEqual(mockSubmitBtn.disabled, false, 'Submit button should be enabled');
        assert.ok(!mockSubmitBtn.classList.contains('disabled'), 'Submit button should NOT have disabled class');

        // Verify Content
        assert.ok(widget.element.innerHTML.includes('1x'), 'Should display item count');
        const expectedPrice = formatPrice(0, 'CZK', 0, 'cs-CZ').replace(/\u00A0/g, ' '); // Normalize NBSP
        
        // Easier: Check that the string is present, normalizing spaces
        const widgetHtml = widget.element.innerHTML.replace(/&nbsp;/g, ' ').replace(/\u00A0/g, ' ');
        assert.ok(widgetHtml.includes(expectedPrice), `Should display zero price (Expected: ${expectedPrice}, Got: ${widgetHtml})`);
    });

    it('should be VISIBLE and ENABLE submit button when price > 0 (Standard)', () => {
        const formModel = { 
            blueprint: null, 
            visibleFields: [{ type: 'ticket' }] 
        };
        mockSession = new MockFormSession(formModel);
        widget = new PriceWidget(mockSession, mockContainer);

        // ACT: Trigger state
        widget.render({ totalPrice: 100, totalItems: 1, currency: 'CZK' });

        // ASSERT
        assert.strictEqual(mockSubmitBtn.disabled, false);
        assert.ok(widget.element);
    });
});
