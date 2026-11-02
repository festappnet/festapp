import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdtemp, mkdir, writeFile, access, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import test from 'node:test';

// Exercise the actual transitive consumers, not an independently installed glob/qs.
const require = createRequire(import.meta.url);
const wp = createRequire(require.resolve('@wordpress/env/package.json'));
const {rimraf, rimrafSync} = wp('rimraf');
const playground = createRequire(wp.resolve('@wp-playground/cli/package.json'));
const express = playground('express');
const expressRequire = createRequire(playground.resolve('express/package.json'));
const qs = expressRequire('qs');

test('wp-env rimraf retains async and sync glob cleanup without deleting unrelated paths', async () => {
  const root = await mkdtemp(join(tmpdir(), 'festapp-wp-deps-'));
  try {
    await mkdir(join(root, 'async-target'));
    await writeFile(join(root, 'async-target', 'nested.txt'), 'fixture');
    await writeFile(join(root, 'sync-target'), 'fixture');
    await writeFile(join(root, 'keep.txt'), 'fixture');
    assert.equal(await rimraf(join(root, 'async-*'), {glob: true}), true);
    await assert.rejects(access(join(root, 'async-target')), {code: 'ENOENT'});
    assert.equal(rimrafSync(join(root, 'sync-*'), {glob: true}), true);
    await assert.rejects(access(join(root, 'sync-target')), {code: 'ENOENT'});
    await access(join(root, 'keep.txt'));
  } finally { await rm(root, {recursive: true, force: true}); }
});

test('Playground Express retains extended query parsing with patched qs', async () => {
  const app = express();
  app.set('query parser', 'extended');
  app.get('/query', (request, response) => response.json(request.query));
  const server = app.listen(0, '127.0.0.1');
  try {
    await once(server, 'listening');
    const response = await fetch(`http://127.0.0.1:${server.address().port}/query?user[name]=Fixture&tags[]=a&tags[]=b`);
    assert.deepEqual(await response.json(), {user: {name: 'Fixture'}, tags: ['a', 'b']});
    assert.doesNotThrow(() => qs.stringify({values: [{toString: 'non-callable'}]}, {arrayFormat: 'comma'}));
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});
