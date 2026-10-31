import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const {fontCapHeightRatio} = createRequire(import.meta.url)('../lib/font_cap_height.cjs');

test('configured bold faces retain their own cap-height metrics', () => {
  assert.equal(fontCapHeightRatio(readFileSync(new URL('../fonts/Gill Sans Bold.otf', import.meta.url))), 0.682);
  assert.equal(fontCapHeightRatio(readFileSync(new URL('../../test/fixtures/fonts/avatar-cerebri-m.ttf', import.meta.url))), 1445 / 2048);
});

test('missing or invalid OpenType metrics use ordinary text alignment', () => {
  for (const bytes of [Buffer.alloc(0), Buffer.from('font fixture'), Buffer.alloc(12)]) {
    assert.equal(fontCapHeightRatio(bytes), null);
  }
});

test('tenant configuration emits metrics from the selected bold face', t => {
  const root = mkdtempSync(path.join(tmpdir(), 'festapp-avatar-font-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  mkdirSync(path.join(root, 'fonts'));
  mkdirSync(path.join(root, 'lib'));
  const regular = readFileSync(new URL('../fonts/Gill Sans Bold.otf', import.meta.url));
  const bold = readFileSync(new URL('../../test/fixtures/fonts/avatar-cerebri-m.ttf', import.meta.url));
  writeFileSync(path.join(root, 'fonts/Regular.otf'), regular);
  writeFileSync(path.join(root, 'fonts/Bold.ttf'), bold);
  writeFileSync(path.join(root, 'lib/theme_config.dart'),
    'static final fontFamily = "Old";\nstatic const double? boldCapHeightRatio = 0.682;\n');
  const result = spawnSync(process.execPath,
    [fileURLToPath(new URL('../configure_fonts.js', import.meta.url)), root,
      'Tenant Font', 'fonts/Regular.otf,fonts/Bold.ttf'], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  const config = readFileSync(path.join(root, 'lib/theme_config.dart'), 'utf8');
  assert.match(config, /fontFamily = "Tenant Font"/);
  assert.match(config, /boldCapHeightRatio = 0\.70556640625/);
  assert.deepEqual(readFileSync(path.join(root, 'web_client/src/assets/fonts/Bold.ttf')), bold);
});
