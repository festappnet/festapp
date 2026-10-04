import test from 'node:test';
import assert from 'node:assert/strict';
import { observeOrderDelivery } from '../../src/components/forms/order_delivery_status.js';
test('status observation is bounded and never fabricates accepted on an unavailable backend', async () => {
    let calls = 0; const states = []; let time = 0;
    const observation = observeOrderDelivery('fixture', state => states.push(state), { invoke: async () => { calls++; return { state: 'queued' }; }, visible: () => true, now: () => time, delay: async ms => { time += ms; } });
    await observation.done;
    assert.equal(calls, 5); assert.deepEqual(states, []);
    const failing = observeOrderDelivery('fixture', state => states.push(state), { invoke: async () => { throw new Error('offline'); }, visible: () => true });
    await failing.done; assert.deepEqual(states, []);
});
test('accepted is observed without waiting on rendering and closing cancels updates', async () => {
    const states = [];
    const accepted = observeOrderDelivery('fixture', state => states.push(state), { invoke: async () => ({ state: 'accepted' }), visible: () => true });
    await accepted.done; assert.deepEqual(states, ['accepted']);
    let finish;
    const closed = observeOrderDelivery('fixture', state => states.push(state), { invoke: () => new Promise(resolve => { finish = resolve; }), visible: () => true });
    closed.stop(); finish({ state: 'accepted' }); await closed.done; assert.deepEqual(states, ['accepted']);
});
test('missing capability and hidden pages do not request status', async () => {
    let calls = 0;
    const deps = { invoke: async () => { calls++; return {}; }, visible: () => false };
    await observeOrderDelivery(null, () => {}, deps).done;
    await observeOrderDelivery('fixture', () => {}, deps).done;
    assert.equal(calls, 0);
});
