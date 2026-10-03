#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';

const projectRoot = path.resolve(import.meta.dirname, '../..');
const source = await readFile(
  path.join(projectRoot, 'web/festapp_flutter_bootstrap_guard.js'),
  'utf8',
);

function createContext({ configurable = true } = {}) {
  function MutationObserver() {}
  Object.defineProperty(
    MutationObserver.prototype,
    '___dart_dispatch_record_old_generation_',
    { value: { stale: true }, configurable, writable: true },
  );
  const window = { MutationObserver };
  const context = { console, Object, Set, window };
  context.globalThis = context;
  vm.runInNewContext(source, context);
  return { window, MutationObserver };
}

{
  const { window, MutationObserver } = createContext();
  const result = window.prepareFestappFlutterBootstrap();
  assert.equal(result.removedDispatchRecords, 1);
  assert.equal(
    Object.getOwnPropertyNames(MutationObserver.prototype)
      .some((name) => name.startsWith('___dart_dispatch_record')),
    false,
  );
  assert.throws(
    () => window.prepareFestappFlutterBootstrap(),
    /already started/,
    'a document must never inject the Flutter entrypoint twice',
  );
}

{
  const { window } = createContext({ configurable: false });
  assert.throws(
    () => window.prepareFestappFlutterBootstrap(),
    /cannot clear 1 stale Dart runtime marker/,
  );
}

const index = await readFile(path.join(projectRoot, 'web/index.html'), 'utf8');
assert.match(index, /festapp_flutter_bootstrap_guard\.js/);
assert.ok(
  index.indexOf('prepareFestappFlutterBootstrap()') <
    index.indexOf('{{flutter_js}}'),
  'the runtime guard must run before Flutter injects its loader and entrypoint',
);

const engineConfigSource = index.match(/initializeEngine\((\{[\s\S]*?\})\)/)[1];
for (const baseURI of ['https://live.festapp.net/', 'https://example.com/app/']) {
  const engineConfig = vm.runInNewContext(`(${engineConfigSource})`, {
    URL, document: { baseURI },
  });
  // Flutter appends assets/ itself, independently of the deep-link pathname.
  assert.equal(new URL('assets/FontManifest.json', engineConfig.assetBase).href,
    `${baseURI}assets/FontManifest.json`);
}
console.log('flutter_bootstrap_guard.test: ok');
