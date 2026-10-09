import test from 'node:test';
import assert from 'node:assert/strict';

import { DbOrders } from '../../src/components/eshop/db_orders.js';
import { SupabaseService } from '../../src/services/supabase_service.js';

test('ticket order sends stable command identity and clears it after success', async () => {
    const values = new Map();
    globalThis.localStorage = {
        getItem: (key) => values.get(key) ?? null,
        setItem: (key, value) => values.set(key, value),
        removeItem: (key) => values.delete(key),
    };

    const bodies = [];
    let shouldFail = true;
    SupabaseService._client = {
        functions: {
            invoke: async (_name, options) => {
                bodies.push(options.body);
                return shouldFail
                    ? { data: null, error: new Error('temporary failure') }
                    : { data: { code: 200 }, error: null };
            },
        },
    };

    const order = { occasion: 1121, tickets: [] };
    const originalConsoleError = console.error;
    console.error = () => {};
    try {
        await DbOrders.sendOrder(order);
        shouldFail = false;
        await DbOrders.sendOrder(order);
    } finally {
        console.error = originalConsoleError;
    }

    assert.equal(bodies.length, 2);
    assert.deepEqual(bodies[0].orderDetails, order);
    assert.match(bodies[0].commandId, /^[0-9a-f-]{36}$/);
    assert.match(bodies[0].clientId, /^[0-9a-f-]{36}$/);
    assert.equal(bodies[1].commandId, bodies[0].commandId);
    assert.equal(bodies[1].clientId, bodies[0].clientId);
    assert.equal(localStorage.getItem('client_command_pending:ticket_order'), null);
});

test('blocked persistent storage preserves order identity across in-page retries', async (t) => {
    const original = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
    Object.defineProperty(globalThis, 'localStorage', {
        configurable: true,
        get() { throw new Error('SecurityError'); },
    });
    t.after(() => {
        if (original) Object.defineProperty(globalThis, 'localStorage', original);
        else delete globalThis.localStorage;
    });
    const bodies = [];
    t.mock.method(SupabaseService, 'getClient', () => ({
        functions: { invoke: async (_, { body }) => {
            bodies.push(body);
            return bodies.length === 1
                ? { data: null, error: new Error('retry') }
                : { data: { code: 200 }, error: null };
        } },
    }));
    t.mock.method(console, 'error', () => {});
    const order = { occasion: 1121, tickets: [] };
    await DbOrders.sendOrder(order);
    await DbOrders.sendOrder(order);
    assert.equal(bodies[0].commandId, bodies[1].commandId);
    assert.equal(bodies[0].clientId, bodies[1].clientId);
    await DbOrders.sendOrder(order);
    assert.notEqual(bodies[1].commandId, bodies[2].commandId, 'a completed order must clear its pending command');
});
