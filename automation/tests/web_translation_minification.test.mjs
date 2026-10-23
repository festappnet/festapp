import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readFile, readdir, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { minifyWebTranslations } from '../minify_web_translations.mjs';

test('built catalogs retain every locale and exact decoded values, without formatting overhead', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'festapp-translations-'));
  try {
    const source = new URL('../../assets/translations/', import.meta.url);
    await cp(source, path.join(root, 'assets/translations'), { recursive: true });
    const files = (await readdir(source)).filter(file => file.endsWith('.json'));
    const expected = await Promise.all(files.map(async file =>
      [file, JSON.parse(await readFile(new URL(file, source), 'utf8'))]));
    const result = await minifyWebTranslations(root);
    assert.equal(result.files, files.length);
    assert.ok(result.afterBytes <= result.beforeBytes);
    assert.deepEqual((await readdir(path.join(root, 'assets/translations'))).filter(file => file.endsWith('.json')).sort(), files.sort());
    for (const [file, value] of expected) {
      assert.deepEqual(JSON.parse(await readFile(path.join(root, 'assets/translations', file), 'utf8')), value);
    }
    const repeated = await minifyWebTranslations(root);
    assert.equal(repeated.beforeBytes, result.afterBytes);
    assert.equal(repeated.afterBytes, result.afterBytes);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('embedded whitespace, HTML, placeholders and Unicode are content; malformed JSON fails closed', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'festapp-translation-content-'));
  try {
    const directory = path.join(root, 'assets/translations');
    await mkdir(directory, { recursive: true });
    const value = { label: '  Příliš žluťoučký  ', html: '<p>{{tickets}}\n  line</p>', list: ['a\tb', '😀'] };
    await writeFile(path.join(directory, 'cs.json'), JSON.stringify(value, null, 4));
    await minifyWebTranslations(root);
    assert.deepEqual(JSON.parse(await readFile(path.join(directory, 'cs.json'), 'utf8')), value);
    await writeFile(path.join(directory, 'cs.json'), '{invalid');
    await assert.rejects(minifyWebTranslations(root), SyntaxError);
  } finally { await rm(root, { recursive: true, force: true }); }
});
