import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import vm from 'node:vm';

test('legacy web clients recover without relying on browser online status or reloading healthy tabs', async t => {
  const root = await mkdtemp(path.join(tmpdir(), 'festapp-legacy-web-'));
  try {
    for (const [name, body] of [['flutter', 'f'], ['webclient', 'current form shell'], ['main.dart.js', 'm']]) {
      await writeFile(path.join(root, name), body);
    }
    const generator = path.resolve(import.meta.dirname, '../generate_pwa_service_worker.mjs');
    const generated = spawnSync(process.execPath, [generator, root, '2.0.0+2'], { encoding: 'utf8' });
    assert.equal(generated.status, 0, generated.stderr);
    const source = (await readFile(path.join(root, 'festapp_service_worker.js'), 'utf8'))
      .replace('const CLIENT_VERSION_REPORT_TIMEOUT_MS = 1000;',
        'const CLIENT_VERSION_REPORT_TIMEOUT_MS = 10;');

    for (const { online, navigationFails = false } of [
      { online: true }, { online: false }, { online: undefined },
      { online: true, navigationFails: true },
    ]) {
      await t.test(`navigator.onLine=${online}, navigationFails=${navigationFails}`, async () => {
        const handlers = {};
        const stores = new Map([
          ['festapp-app-shell-0.20.17+501', new Map()],
          ['festapp-app-shell-1.5.0+5', new Map([
            ['/web-assets/form-cached.js', new Response('older cached form module')],
          ])],
          ['festapp-app-shell-2.0.0+2', new Map([
            ['/webclient?pwa-cache=1', new Response('current form shell')],
            ['/web-assets/form-current.js', new Response('current form module')],
          ])],
          ['festapp-used-fonts-v1', new Map()],
        ]);
        const navigated = [];
        const pendingNavigations = [];
        const pendingReports = [];
        let skipWaitingCalls = 0;
        let installFails = true;
        const clients = [
          { id: 'broken-akh', url: 'https://app.test/form/akh', postMessage() {},
            navigate: url => {
              navigated.push(['broken-akh', url]);
              if (navigationFails) return Promise.reject(new Error('navigation rejected'));
              // WebKit cannot finish this controlled navigation until the
              // activating worker has finished its activate event.
              return new Promise(resolve => pendingNavigations.push(resolve));
            } },
          { id: 'healthy-form', url: 'https://app.test/form/another-event',
            navigate: async url => { navigated.push(['healthy-form', url]); },
            postMessage() {
              handlers.message({
                data: { type: 'FESTAPP_CLIENT_VERSION', version: '1.5.0+5' },
                source: this,
                waitUntil: promise => pendingReports.push(promise),
              });
            } },
        ];
        const key = request => typeof request === 'string'
          ? request : new URL(request.url).pathname + new URL(request.url).search;
        vm.runInNewContext(source, {
          URL, Request, Response, Promise, setTimeout, clearTimeout,
          fetch: async () => { throw new Error('network unavailable'); },
          caches: {
            keys: async () => [...stores.keys()],
            delete: async name => stores.delete(name),
            open: async name => {
              if (!stores.has(name)) stores.set(name, new Map());
              const store = stores.get(name);
              return {
                addAll: async () => { if (installFails) throw new Error('network unavailable'); },
                match: async request => store.get(key(request))?.clone(),
                put: async (request, response) => store.set(key(request), response.clone()),
              };
            },
          },
          self: {
            location: { origin: 'https://app.test' }, navigator: { onLine: online },
            clients: { matchAll: async () => clients, claim: async () => {},
              get: async id => clients.find(client => client.id === id) },
            skipWaiting: async () => { skipWaitingCalls++; },
            addEventListener: (type, handler) => { handlers[type] = handler; },
          },
        });
        const dispatch = async type => {
          let pending;
          handlers[type]({ waitUntil: promise => { pending = promise; } });
          await pending;
        };
        await assert.rejects(dispatch('install'), /network unavailable/);
        assert.equal(skipWaitingCalls, 0, 'failed installation must preserve the offline shell');
        assert.ok(stores.has('festapp-app-shell-0.20.17+501'));

        installFails = false;
        await dispatch('install');
        assert.equal(skipWaitingCalls, 1,
          'a legacy page without an updater must not strand the installed recovery worker');
        let activationTimeout;
        try {
          await Promise.race([
            dispatch('activate'),
            new Promise((_, reject) => {
              activationTimeout = setTimeout(() => reject(new Error(
                'activation deadlocked waiting for its own controlled navigation')), 100);
            }),
          ]);
        } finally {
          clearTimeout(activationTimeout);
          for (const resolve of pendingNavigations) resolve();
        }
        await Promise.all(pendingReports);
        assert.deepEqual(navigated, [['broken-akh', 'https://app.test/form/akh']],
          'recover only the unreporting legacy page; preserve another form and its draft');
        assert.ok(stores.has('festapp-app-shell-1.5.0+5'), 'the healthy older tab retains its executable shell');
        assert.ok(stores.has('festapp-used-fonts-v1'));
        if (navigationFails) {
          assert.ok(stores.has('festapp-app-shell-0.20.17+501'),
            'a rejected navigation must preserve the only shell of the unreporting page');
          await new Promise(setImmediate); // Let Node detect any unhandled rejection.
          return;
        }

        const fetchResponse = async (request, clientId, resultingClientId = '') => {
          let response;
          handlers.fetch({ request, clientId, resultingClientId,
            respondWith: promise => { response = promise; }, waitUntil() {} });
          return response;
        };
        const navigation = new Request('https://app.test/form/akh');
        Object.defineProperty(navigation, 'mode', { value: 'navigate' });
        assert.equal(await (await fetchResponse(navigation, '', 'recovered-akh')).text(), 'current form shell');
        const module = await fetchResponse(new Request('https://app.test/web-assets/form-current.js'), 'recovered-akh');
        assert.equal(await module.text(), 'current form module', 'the recovered form must load its module without a version-handshake deadlock');

        const cachedModule = await fetchResponse(new Request('https://app.test/web-assets/form-cached.js'), 'healthy-form');
        assert.equal(await cachedModule.text(), 'older cached form module');
        assert.equal(navigated.length, 1, 'an intact older module must not reload an edited form');
        const missingModule = await fetchResponse(new Request('https://app.test/web-assets/form-removed.js'), 'healthy-form');
        assert.equal(missingModule.type, 'error', 'never substitute another build into a running module graph');
        assert.deepEqual(navigated.at(-1), ['healthy-form', 'https://app.test/form/another-event'],
          'a missing lazy web module must recover through the complete installed shell');
      });
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('one reconcile policy retains exactly current and live known shells', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'festapp-reconcile-'));
  try {
    for (const [name, body] of [['flutter', 'f'], ['webclient', 'w'], ['main.dart.js', 'm']]) {
      await writeFile(path.join(root, name), body);
    }
    const generator = path.resolve(import.meta.dirname, '../generate_pwa_service_worker.mjs');
    const generated = spawnSync(process.execPath, [generator, root, '2.0.0+2'], { encoding: 'utf8' });
    assert.equal(generated.status, 0, generated.stderr);
    const source = (await readFile(
      path.join(root, 'festapp_service_worker.js'),
      'utf8',
    )).replace('const STORAGE_API_TIMEOUT_MS = 1000;',
      'const STORAGE_API_TIMEOUT_MS = 10;');
    const handlers = {};
    const deleted = [];
    const deleteAttempts = [];
    let names = [
      'festapp-app-shell-0.9.0+9',
      'festapp-app-shell-1.0.0+1',
      'festapp-app-shell-1.1.0+1',
      'festapp-app-shell-1.5.0+5',
      'festapp-app-shell-2.0.0+2',
      'festapp-used-fonts-v1',
    ];
    let keysFail = false;
    let deleteBehavior = 'success';
    let skipWaitingCalls = 0;
    const clients = [{ id: 'flutter', postMessage() {} }, { id: 'webclient', postMessage() {} }];
    const context = {
      URL, Request, Response, Promise, setTimeout, clearTimeout,
      fetch: async () => { throw new Error('not used'); },
      caches: {
        open: async () => ({ addAll: async () => {} }),
        keys: async () => {
          if (keysFail) throw new Error('cache api unavailable');
          return [...names];
        },
        delete: async (name) => {
          deleteAttempts.push(name);
          if (deleteBehavior === 'false') return false;
          if (deleteBehavior === 'throw') throw new Error('delete failed');
          if (deleteBehavior === 'hang') return new Promise(() => {});
          deleted.push(name);
          names = names.filter((item) => item !== name);
          return true;
        },
      },
      self: {
        location: { origin: 'https://app.test' },
        navigator: { onLine: false },
        clients: {
          matchAll: async () => clients,
          claim: async () => {},
          get: async (id) => clients.find((client) => client.id === id),
        },
        skipWaiting: async () => { skipWaitingCalls++; },
        addEventListener: (type, handler) => { handlers[type] = handler; },
      },
    };
    vm.runInNewContext(source, context);

    async function dispatchInstall() {
      let installation;
      handlers.install({ waitUntil: (value) => { installation = value; } });
      await installation;
    }

    await dispatchInstall();
    assert.equal(skipWaitingCalls, 0, 'ordinary upgrades remain user coordinated');
    names.push('festapp-app-shell-0.19.93+457');
    await dispatchInstall();
    assert.equal(skipWaitingCalls, 1,
      'a pre-coordinator web client must not strand its successor waiting');
    names = names.filter((name) => name !== 'festapp-app-shell-0.19.93+457');
    names.push('festapp-app-shell-0.20.17+501');
    context.self.navigator.onLine = true;
    await dispatchInstall();
    assert.equal(skipWaitingCalls, 2,
      'legacy web HTML without an updater must recover when online status is true');
    context.self.navigator.onLine = false;
    await dispatchInstall();
    assert.equal(skipWaitingCalls, 3,
      'a successful installation must also recover a false-offline legacy shell');
    names = names.filter((name) => name !== 'festapp-app-shell-0.20.17+501');

    const dispatch = async (data, source = clients[0]) => {
      let pending = Promise.resolve();
      let reply;
      handlers.message({
        data,
        source,
        ports: [{ postMessage: (value) => { reply = value; } }],
        waitUntil: (value) => { pending = value; },
      });
      await pending;
      return reply;
    };

    let activation;
    handlers.activate({ waitUntil: (value) => { activation = value; } });
    await activation;
    assert.deepEqual(deleted, [], 'unknown live clients must block automatic cleanup');

    await dispatch({ type: 'FESTAPP_CLIENT_VERSION', version: '2.0.0+2' }, clients[0]);
    assert.deepEqual(deleted, []);
    await dispatch({ type: 'FESTAPP_CLIENT_VERSION', version: '1.5.0+5' }, clients[1]);
    assert.deepEqual(deleted, ['festapp-app-shell-0.9.0+9']);

    const inspection = await dispatch({ type: 'FESTAPP_INSPECT_SHELLS' });
    assert.deepEqual([...inspection.retained], [
      'festapp-app-shell-1.5.0+5', 'festapp-app-shell-2.0.0+2',
    ]);
    assert.deepEqual([...inspection.deletable], [
      'festapp-app-shell-1.0.0+1', 'festapp-app-shell-1.1.0+1',
    ]);
    assert.equal(inspection.blocker, null);
    assert.ok(names.includes('festapp-used-fonts-v1'));

    const pruned = await dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' });
    assert.deepEqual([...pruned.deleted], [
      'festapp-app-shell-1.0.0+1', 'festapp-app-shell-1.1.0+1',
    ]);
    assert.deepEqual([...pruned.deletable], []);
    const currentNavigationSafe = names.includes('festapp-app-shell-2.0.0+2');
    const liveNavigationSafe = names.includes('festapp-app-shell-1.5.0+5');
    assert.equal(currentNavigationSafe && liveNavigationSafe, true,
      'prune must preserve caches needed for an offline cold start');

    names.push('festapp-app-shell-0.7.0+7', 'festapp-app-shell-0.8.0+8');
    const concurrentPrunes = await Promise.all([
      dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' }),
      dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' }),
    ]);
    assert.deepEqual(
      concurrentPrunes.flatMap((result) => [...result.deleted]).sort(),
      ['festapp-app-shell-0.7.0+7', 'festapp-app-shell-0.8.0+8'],
      'concurrent requests must serialize and delete each stale shell once',
    );

    names = names.filter((name) => name !== 'festapp-app-shell-1.5.0+5');
    const missing = await dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' });
    assert.equal(missing.blocker, 'missing-live-shell');
    assert.deepEqual(deleted, [
      'festapp-app-shell-0.9.0+9',
      'festapp-app-shell-1.0.0+1',
      'festapp-app-shell-1.1.0+1',
      'festapp-app-shell-0.7.0+7',
      'festapp-app-shell-0.8.0+8',
    ]);

    keysFail = true;
    const failed = await dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' });
    assert.equal(failed.blocker, 'storage-api-error');
    assert.equal(deleted.length, 5);

    keysFail = false;
    context.self.clients.matchAll = async () => new Promise(() => {});
    const timedOut = await dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' });
    assert.equal(timedOut.blocker, 'storage-api-timeout');
    assert.equal(deleted.length, 5);

    context.self.clients.matchAll = async () => clients;
    names.push('festapp-app-shell-1.5.0+5', 'festapp-app-shell-9.0.0+9');
    deleteBehavior = 'false';
    const rejected = await dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' });
    assert.equal(rejected.blocker, 'cache-delete-rejected');
    assert.deepEqual([...rejected.deleted], []);
    assert.ok(names.includes('festapp-app-shell-9.0.0+9'));

    deleteBehavior = 'throw';
    const deleteError = await dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' });
    assert.equal(deleteError.blocker, 'cache-delete-error');
    assert.deepEqual([...deleteError.deleted], []);

    deleteBehavior = 'hang';
    const deleteTimeout = await dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' });
    assert.equal(deleteTimeout.blocker, 'cache-delete-status-unknown');
    assert.deepEqual([...deleteTimeout.deleted], []);
    const attemptsAfterTimeout = deleteAttempts.length;
    deleteBehavior = 'success';
    const latched = await dispatch({ type: 'FESTAPP_PRUNE_UNUSED_SHELLS' });
    assert.equal(latched.blocker, 'cache-delete-status-unknown');
    assert.equal(deleteAttempts.length, attemptsAfterTimeout,
      'an indeterminate non-cancelable delete must block later mutations');
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
