import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

test('legacy tenant favicon replaces both Vite entry and public copies', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'festapp-brand-'));
  try {
    await mkdir(path.join(root, 'web'));
    await mkdir(path.join(root, 'web_client'));
    const icon = Buffer.from('selected tenant icon');
    await writeFile(path.join(root, 'web/favicon.ico'), icon);
    await writeFile(path.join(root, 'web_client/favicon.ico'), 'previous product icon');
    await writeFile(path.join(root, 'logo.svg'), '<svg xmlns="http://www.w3.org/2000/svg"/>');
    const result = spawnSync('python3', ['automation/configure_brand_assets.py', '--root', root,
      '--logo', 'logo.svg', '--dark-logo', 'logo.svg', '--loading-style', 'spinner'],
      {cwd: path.resolve(import.meta.dirname, '../..'), encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    for (const target of ['web_client/favicon.ico', 'web_client/public/favicon.ico']) {
      assert.deepEqual(await readFile(path.join(root, target)), icon, target);
    }
  } finally { await rm(root, {recursive: true, force: true}); }
});
