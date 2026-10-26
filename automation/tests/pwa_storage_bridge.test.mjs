import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(
  path.resolve(import.meta.dirname, '../../web/festapp_pwa_bridge.js'), 'utf8',
);

test('storage bridge is aggregate-only transport', () => {
  assert.match(source, /navigator\.storage\?\.estimate/);
  assert.match(source, /FESTAPP_INSPECT_SHELLS/);
  assert.match(source, /FESTAPP_PRUNE_UNUSED_SHELLS/);
  assert.doesNotMatch(source, /caches\.(?:open|keys|delete)|indexedDB|localStorage|sessionStorage|cookie|\.text\(|arrayBuffer/);
});

function loadBridge({ controller, estimate } = {}) {
  class TestMessageChannel {
    constructor() {
      this.port1 = { onmessage: null };
      this.port2 = {
        postMessage: (data) => this.port1.onmessage?.({ data }),
      };
    }
  }
  const window = { setTimeout, clearTimeout };
  const navigator = {
    serviceWorker: { controller: controller ?? null },
    storage: estimate ? { estimate } : undefined,
  };
  vm.runInNewContext(
    source.replace('const timeoutMs = 3000;', 'const timeoutMs = 10;'),
    { window, navigator, MessageChannel: TestMessageChannel, Number, Object, Promise, String },
  );
  const invoke = (name) => new Promise((resolve, reject) => {
    window[name](resolve, reject);
  });
  return { invoke };
}

test('storage bridge returns aggregate metadata through callback transport', async () => {
  const messages = [];
  const controller = {
    postMessage(message, ports) {
      messages.push(message);
      ports[0].postMessage({
        current: '2.0.0+2',
        retained: ['festapp-app-shell-2.0.0+2'],
        deletable: [],
      });
    },
  };
  const { invoke } = loadBridge({
    controller,
    estimate: async () => ({
      usage: 2048,
      quota: 4096,
      usageDetails: { caches: 1024, invalid: Number.NaN },
    }),
  });

  const inspection = await invoke('festappInspectPwaStorage');
  assert.equal(messages.length, 1);
  assert.equal(messages[0].type, 'FESTAPP_INSPECT_SHELLS');
  assert.equal(inspection.estimate.usage, 2048);
  assert.equal(inspection.estimate.usageDetails.caches, 1024);
  assert.equal(Object.keys(inspection.estimate.usageDetails).length, 1);
  assert.equal(inspection.shells.current, '2.0.0+2');

  await invoke('festappPruneUnusedShells');
  assert.equal(messages.at(-1).type, 'FESTAPP_PRUNE_UNUSED_SHELLS');
});

test('storage bridge fails closed for missing, throwing and timed-out workers', async () => {
  const unsupported = await loadBridge().invoke('festappPruneUnusedShells');
  assert.equal(unsupported.blocker, 'unsupported-browser');

  const throwing = await loadBridge({
    controller: { postMessage() { throw new Error('closed port'); } },
  }).invoke('festappPruneUnusedShells');
  assert.equal(throwing.blocker, 'worker-message-error');

  const timedOut = await loadBridge({
    controller: { postMessage() {} },
  }).invoke('festappPruneUnusedShells');
  assert.equal(timedOut.blocker, 'worker-timeout');
});
