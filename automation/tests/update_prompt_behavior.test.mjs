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
assert.match(clickHandler, /cutOverToVersion\(latestVersion\)/);
assert.doesNotMatch(
  clickHandler,
  /recoverFailedCutover\(latestVersion\)/,
  'accepting an update must preserve the currently working offline shell',
);
const cutoverFunction = source.match(
  /async function cutOverToVersion\(latestVersion\) \{[\s\S]*?\n  \}/,
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
    setAttribute() {},
    addEventListener() {},
    append() {},
    remove() {},
  }),
  getElementById: () => null,
  addEventListener() {},
  removeEventListener() {},
};

const navigator = {
  language: 'cs',
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
  localStorage: storage(),
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

console.log('update_prompt_behavior.test: ok');
