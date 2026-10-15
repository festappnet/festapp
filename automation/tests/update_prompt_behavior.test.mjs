#!/usr/bin/env node

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';

const projectRoot = path.resolve(import.meta.dirname, '../..');
const source = await readFile(
  path.join(projectRoot, 'web/festapp_update_prompt.js'),
  'utf8',
);

const clickHandler = source.match(
  /reloadButton\.addEventListener\('click',[\s\S]*?\n    \}\);/,
)?.[0] ?? '';
assert.match(clickHandler, /networkBuildVersion\(\)/);
assert.match(clickHandler, /cutOverToVersion\(targetVersion/);
assert.doesNotMatch(
  clickHandler,
  /recoverFailedCutover\(latestVersion\)/,
  'accepting an update must preserve the currently working offline shell',
);
const cutoverFunction = source.match(
  /async function cutOverToVersion\(latestVersion, repair = false, onlyIfStalled = false\) \{[\s\S]*?\n  \}/,
)?.[0] ?? '';
assert.ok(
  cutoverFunction.indexOf('activateWaitingFestappWorker') <
    cutoverFunction.indexOf('sessionStorage.setItem'),
  'a failed activation must not mark the version as an attempted cutover',
);

function storage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
  };
}

const windowListeners = new Map();
const timers = [];
const appendedElements = [];
const deletedCaches = [];
let unregistered = 0;
let replacedLocation = null;
let reloads = 0;

const activeWorker = {
  scriptURL: 'https://app.test/festapp_service_worker.js',
  state: 'activated',
  postMessage: () => {},
};
const registration = {
  active: activeWorker,
  waiting: null,
  installing: null,
  update: async () => {},
  unregister: async () => { unregistered++; return true; },
};
const sessionStorage = storage({ festappCutoverVersion: '2.0.0+2' });

const document = {
  visibilityState: 'visible',
  body: { appendChild: (element) => appendedElements.push(element) },
  createElement: (tag) => ({
    tag,
    style: {},
    attributes: {},
    listeners: {},
    children: [],
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(type, listener) { this.listeners[type] = listener; },
    append(...children) { this.children.push(...children); },
    remove() {},
  }),
  getElementById: () => null,
  addEventListener() {},
  removeEventListener() {},
};

const navigator = {
  language: 'en',
  onLine: true,
  serviceWorker: {
    controller: activeWorker,
    getRegistration: async () => registration,
    getRegistrations: async () => [registration],
    addEventListener() {},
  },
};

const cacheStorage = {
  keys: async () => ['festapp-app-shell-1.0.0+1', 'festapp-used-fonts-v1'],
  delete: async (name) => { deletedCaches.push(name); return true; },
};

const window = {
  __FESTAPP_BUILD_VERSION__: '1.0.0+1',
  __FESTAPP_APP_READY__: true,
  __FESTAPP_LOCAL_DEVELOPMENT__: false,
  location: {
    href: 'https://app.test/news',
    reload: () => { reloads++; },
    replace: (url) => { replacedLocation = String(url); },
  },
  addEventListener: (type, listener) => windowListeners.set(type, listener),
  setTimeout: (listener, delay) => { timers.push({ listener, delay }); return timers.length; },
  clearTimeout() {},
  setInterval() {},
  caches: cacheStorage,
};

const context = {
  console,
  document,
  fetch: async () => new Response(JSON.stringify({
    version: '2.0.0+2',
    main: 'main.dart.2.0.0-2.js',
  })),
  localStorage: storage({ 'flutter.locale': '"cs"', 'flutter.Locale': '"en"' }),
  navigator,
  sessionStorage,
  caches: cacheStorage,
  Response,
  URL,
  window,
};
context.globalThis = context;

vm.runInNewContext(source, context);
windowListeners.get('load')();
await new Promise((resolve) => setImmediate(resolve));

const versionTimer = timers.find(({ delay }) => delay === 3000);
assert.ok(versionTimer, 'load must schedule the version check');
await versionTimer.listener();
await Promise.resolve();

assert.equal(
  appendedElements.length,
  0,
  'an already-attempted version must never show the same update banner again',
);
assert.equal(unregistered, 0, 'window recovery must preserve the canonical Festapp worker');
assert.deepEqual(deletedCaches, [], 'window recovery must never delete versioned shells');
assert.match(replacedLocation, /festapp-recovery=2\.0\.0%2B2/);
assert.equal(reloads, 0, 'failed cutover recovery must use a cache-busted restart');

const runtimeErrorListener = windowListeners.get('error');
assert.ok(runtimeErrorListener, 'runtime corruption must be observed globally');
runtimeErrorListener({
  message: 'Cannot define property ___dart_dispatch_record_ZxYxX_0_, object is not extensible',
  error: new TypeError(
    'Cannot define property ___dart_dispatch_record_ZxYxX_0_, object is not extensible',
  ),
});
await new Promise((resolve) => setImmediate(resolve));

assert.equal(
  reloads,
  1,
  'a corrupt Dart runtime must automatically retry with a coherent app shell',
);
runtimeErrorListener({ message: 'Unrelated application error' });
windowListeners.get('unhandledrejection')({
  reason: new TypeError(
    'Cannot define property ___dart_dispatch_record_ZxYxX_0_, object is not extensible',
  ),
});
await new Promise((resolve) => setImmediate(resolve));
assert.equal(reloads, 1, 'runtime recovery must neither match other errors nor reload-loop');

// A stale startup banner captures the old document's version. Accepting it
// must still activate the newest installed generation, rather than do nothing
// because the old generation is no longer the registration's active worker.
context.MessageChannel = class {
  constructor() {
    this.port1 = { onmessage: null, close() {} };
    this.port2 = { reply: (data) => this.port1.onmessage?.({ data }) };
  }
};
let workerVersion = '2.0.0+2';
let repairs = 0;
activeWorker.postMessage = (message, ports = []) => {
  if (message?.type === 'FESTAPP_QUERY_BUILD_VERSION') {
    ports[0]?.reply({ version: workerVersion });
  }
  if (message?.type === 'FESTAPP_REPAIR_APP_SHELL') {
    repairs++;
    ports[0]?.reply({ ok: true, version: workerVersion });
  }
};
window.__FESTAPP_APP_READY__ = false;
sessionStorage.setItem('festappStartupRecoveryVersion', '1.0.0+1');
window.getFestappStartupPhase = () => 'S06';
await window.recoverFestappStartup('still-stalled');
const banner = appendedElements.at(-1);
const diagnostic = banner.children[0].children.find((element) =>
  element.attributes['data-festapp-startup-diagnostic'] === 'true');
assert.ok(diagnostic, 'stalled phone recovery must expose a code without a console');
assert.equal(diagnostic.textContent, 'Kód pro podporu: 1.0.0+1 / S06');
window.getFestappStartupPhase = () => 'https://private.test/?token=secret';
await window.recoverFestappStartup('invalid-phase');
assert.equal(appendedElements.at(-1).children[0].children[0].textContent,
  'Kód pro podporu: 1.0.0+1 / S00');
assert.ok(!appendedElements.at(-1).children[0].children[0].textContent.includes('secret'));
const refresh = banner.children[1].children.find(
  (element) => element.attributes['data-festapp-update-action'] === 'reload');
assert.ok(refresh);
await refresh.listeners.click();
assert.equal(reloads, 2, 'Refresh must leave the stranded document for the latest ready generation');
assert.equal(sessionStorage.getItem('festappCutoverVersion'), '2.0.0+2');
assert.equal(repairs, 0, 'a newly installed generation already has a coherent shell');

// Retrying the same failed generation must refetch its core before reload.
workerVersion = '1.0.0+1';
context.fetch = async () => new Response(JSON.stringify({ version: workerVersion }));
sessionStorage.removeItem('festappStartupRecoveryVersion');
await window.recoverFestappStartup('same-version-stall');
assert.equal(repairs, 1, 'same-generation startup recovery must repair cached core files');
assert.equal(reloads, 3);
assert.equal(unregistered, 0);
assert.deepEqual(deletedCaches, []);

// Another tab can activate the verified registration while this page still has
// the previous controller. A navigation uses the active worker, so do not no-op.
navigator.serviceWorker.controller = { state: 'activated' };
const beforeReloads = reloads;
assert.equal(await window.cutOverToVersion(workerVersion), true);
assert.equal(reloads, beforeReloads + 1);
assert.equal(unregistered, 0);

// If an explicit update cannot activate a worker, navigate through the network
// without deleting caches or silently leaving the click ineffective.
registration.active = null;
registration.waiting = null;
registration.installing = null;
await refresh.listeners.click();
assert.equal(unregistered, 1);
assert.match(replacedLocation, /festapp-recovery=/);
assert.deepEqual(deletedCaches, []);
assert.equal(refresh.disabled, false);

context.localStorage.setItem('flutter.locale', '"en"');
navigator.language = 'cs';
windowListeners.get('festapp-update-available')({ detail: { version: '3.0.0+3', reason: 'legacy-cache' } });
assert.equal(appendedElements.at(-1).children[0].textContent,
  'The app is ready to refresh.', 'saved English must win over the Czech device');
console.log('update_prompt_behavior.test: ok');
