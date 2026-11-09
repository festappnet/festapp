import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdtemp, mkdir, writeFile, readFile, lstat, access, rm} from 'node:fs/promises';
import fs from 'node:fs';
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
const storage = createRequire(playground.resolve('@wp-playground/storage'));
const git = storage('isomorphic-git');

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

// Build inert repositories entirely inside a private temporary sandbox. The
// sentinel is outside the checkout but remains inside that disposable sandbox.
const author = {name: 'Fixture', email: 'fixture@example.invalid', timestamp: 1700000000, timezoneOffset: 0};
async function commitTree(dir, tree, parent = []) {
  return git.writeCommit({fs, dir, commit: {tree, parent, author, committer: author, message: 'Fixture'}});
}
function assertUnsafeCheckout(error) {
  if (error.code === 'MultipleGitError') {
    assert.ok(error.errors.length > 0);
    error.errors.forEach(assertUnsafeCheckout);
  } else assert.equal(error.code, 'UnsafeFilepathError');
}
async function checkoutOrRejectUnsafe(dir, ref) {
  try { await git.checkout({fs, dir, ref, force: true}); return true; }
  catch (error) { assertUnsafeCheckout(error); return false; }
}

test('Playground retains ordinary checkout through its actual Git dependency', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'festapp-wp-git-valid-'));
  try {
    await git.init({fs, dir, defaultBranch: 'main'});
    const blob = await git.writeBlob({fs, dir, blob: Buffer.from('fixture content')});
    const tree = await git.writeTree({fs, dir, tree: [{mode: '100644', path: 'normal.txt', oid: blob, type: 'blob'}]});
    const commit = await commitTree(dir, tree);
    await git.writeRef({fs, dir, ref: 'refs/heads/main', value: commit});
    await git.checkout({fs, dir, ref: 'main', force: true});
    assert.equal(await readFile(join(dir, 'normal.txt'), 'utf8'), 'fixture content');
  } finally { await rm(dir, {recursive: true, force: true}); }
});

test('Playground checkout never follows a leading directory symlink outside its worktree', async () => {
  const root = await mkdtemp(join(tmpdir(), 'festapp-wp-git-symlink-'));
  const dir = join(root, 'checkout');
  const outside = join(root, 'outside');
  try {
    await mkdir(dir); await mkdir(outside);
    await writeFile(join(outside, 'sentinel.txt'), 'preserved');
    await git.init({fs, dir, defaultBranch: 'main'});
    const link = await git.writeBlob({fs, dir, blob: Buffer.from('../outside')});
    const initialTree = await git.writeTree({fs, dir, tree: [{mode: '120000', path: 'config', oid: link, type: 'blob'}]});
    const initial = await commitTree(dir, initialTree);
    await git.writeRef({fs, dir, ref: 'refs/heads/main', value: initial});
    const initialAllowed = await checkoutOrRejectUnsafe(dir, 'main');
    if (initialAllowed) {
      assert.equal((await lstat(join(dir, 'config'))).isSymbolicLink(), true);
      const blob = await git.writeBlob({fs, dir, blob: Buffer.from('fixture payload')});
      const child = await git.writeTree({fs, dir, tree: [{mode: '100644', path: 'sentinel.txt', oid: blob, type: 'blob'}]});
      const tree = await git.writeTree({fs, dir, tree: [{mode: '040000', path: 'config', oid: child, type: 'tree'}]});
      const next = await commitTree(dir, tree, [initial]);
      await git.writeRef({fs, dir, ref: 'refs/heads/next', value: next});
      const nextAllowed = await checkoutOrRejectUnsafe(dir, 'next');
      assert.equal(await readFile(join(outside, 'sentinel.txt'), 'utf8'), 'preserved');
      if (nextAllowed) {
        assert.equal((await lstat(join(dir, 'config'))).isSymbolicLink(), false);
        assert.equal(await readFile(join(dir, 'config', 'sentinel.txt'), 'utf8'), 'fixture payload');
      }
    }
    assert.equal(await readFile(join(outside, 'sentinel.txt'), 'utf8'), 'preserved');
  } finally { await rm(root, {recursive: true, force: true}); }
});

test('Playground checkout rejects a raw dotdot tree entry without escaping its worktree', async () => {
  const root = await mkdtemp(join(tmpdir(), 'festapp-wp-git-dotdot-'));
  const dir = join(root, 'checkout');
  try {
    await mkdir(dir);
    await writeFile(join(root, 'sentinel.txt'), 'preserved');
    await git.init({fs, dir, defaultBranch: 'main'});
    const blob = await git.writeBlob({fs, dir, blob: Buffer.from('fixture payload')});
    const child = await git.writeTree({fs, dir, tree: [{mode: '100644', path: 'sentinel.txt', oid: blob, type: 'blob'}]});
    // Untrusted remotes can contain raw tree objects bypassing writeTree's checks.
    const raw = Buffer.concat([Buffer.from('40000 ..\0'), Buffer.from(child, 'hex')]);
    const tree = await git.writeObject({fs, dir, type: 'tree', format: 'content', object: raw});
    const commit = await commitTree(dir, tree);
    await git.writeRef({fs, dir, ref: 'refs/heads/unsafe', value: commit});
    await assert.rejects(git.checkout({fs, dir, ref: 'unsafe', force: true}), {code: 'UnsafeFilepathError'});
    assert.equal(await readFile(join(root, 'sentinel.txt'), 'utf8'), 'preserved');
  } finally { await rm(root, {recursive: true, force: true}); }
});
