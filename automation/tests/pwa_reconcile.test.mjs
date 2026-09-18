import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import vm from 'node:vm';

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
    assert.equal(skipWaitingCalls, 1,
      'the affected shell stays user coordinated when online status is true');
    context.self.navigator.onLine = false;
    await dispatchInstall();
    assert.equal(skipWaitingCalls, 2,
      'a successfully installed worker must replace the false-offline shell');
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
