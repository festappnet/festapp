import { test } from 'node:test';
import assert from 'node:assert/strict';
import { prepareFlutterRuntime } from '../../src/services/flutter_runtime_handoff.js';

class FakeMessageChannel {
    constructor() {
        this.port1 = { onmessage: null };
        this.port2 = { reply: (version) => this.port1.onmessage?.({ data: { version } }) };
    }
}

function worker(version, state = 'activated') {
    const listeners = new Map();
    return {
        state,
        messages: [],
        postMessage(message, ports = []) {
            this.messages.push(message);
            if (message?.type === 'FESTAPP_QUERY_BUILD_VERSION') ports[0].reply(version);
        },
        addEventListener(type, listener) { listeners.set(type, listener); },
        removeEventListener(type) { listeners.delete(type); },
        setState(next) {
            this.state = next;
            listeners.get('statechange')?.();
        },
    };
}

function fixture({ activeVersion = '0.19.93+458', waitingVersion = null } = {}) {
    const active = worker(activeVersion);
    const waiting = waitingVersion ? worker(waitingVersion, 'installed') : null;
    const listeners = new Map();
    const serviceWorker = {
        controller: active,
        addEventListener(type, listener) { listeners.set(type, listener); },
        removeEventListener(type) { listeners.delete(type); },
        async getRegistration() { return registration; },
    };
    if (waiting) {
        const originalPostMessage = waiting.postMessage.bind(waiting);
        waiting.postMessage = (message, ports) => {
            originalPostMessage(message, ports);
            if (message === 'SKIP_WAITING') {
                waiting.state = 'activated';
                serviceWorker.controller = waiting;
                listeners.get('controllerchange')?.();
            }
        };
    }
    const registration = {
        active,
        waiting,
        installing: null,
        updated: 0,
        unregistered: 0,
        async update() { this.updated += 1; },
        async unregister() { this.unregistered += 1; return true; },
    };
    return {
        active,
        waiting,
        registration,
        navigator: {
            onLine: true,
            serviceWorker,
        },
    };
}

const manifestFetch = async () => ({
    ok: true,
    async json() { return { version: '0.19.93+458' }; },
});

test('keeps a matching active worker', async () => {
    const f = fixture();
    const result = await prepareFlutterRuntime({
        navigator: f.navigator,
        fetch: manifestFetch,
        MessageChannel: FakeMessageChannel,
        timeoutMs: 50,
    });
    assert.equal(result.strategy, 'current');
    assert.equal(f.registration.unregistered, 0);
});

test('activates the exact waiting generation before navigation', async () => {
    const f = fixture({ activeVersion: '0.19.93+455', waitingVersion: '0.19.93+458' });
    const result = await prepareFlutterRuntime({
        navigator: f.navigator,
        fetch: manifestFetch,
        MessageChannel: FakeMessageChannel,
        timeoutMs: 50,
    });
    assert.equal(result.strategy, 'activated');
    assert.deepEqual(f.waiting.messages, [
        { type: 'FESTAPP_QUERY_BUILD_VERSION' },
        'SKIP_WAITING',
    ]);
    assert.equal(f.registration.unregistered, 0);
});

test('unregisters a stale worker when no matching generation is ready', async () => {
    const f = fixture({ activeVersion: '0.19.93+455' });
    const result = await prepareFlutterRuntime({
        navigator: f.navigator,
        fetch: manifestFetch,
        MessageChannel: FakeMessageChannel,
        timeoutMs: 50,
    });
    assert.equal(result.strategy, 'stale-unregistered');
    assert.equal(f.registration.unregistered, 1);
});

test('preserves the offline worker and caches', async () => {
    const f = fixture({ activeVersion: '0.19.93+455' });
    f.navigator.onLine = false;
    const result = await prepareFlutterRuntime({
        navigator: f.navigator,
        fetch: () => assert.fail('offline handoff must not fetch'),
        MessageChannel: FakeMessageChannel,
    });
    assert.equal(result.strategy, 'preserved');
    assert.equal(f.registration.unregistered, 0);
});

test('binds browser host functions to Window instead of the coordinator object', async () => {
    const f = fixture();
    const root = {
        navigator: f.navigator,
        MessageChannel: FakeMessageChannel,
        fetch() {
            assert.equal(this, root);
            return manifestFetch();
        },
        setTimeout(callback, delay) {
            assert.equal(this, root);
            return globalThis.setTimeout(callback, delay);
        },
        clearTimeout(timeout) {
            assert.equal(this, root);
            return globalThis.clearTimeout(timeout);
        },
    };
    const result = await prepareFlutterRuntime({ globalObject: root, timeoutMs: 50 });
    assert.equal(result.strategy, 'current');
});
