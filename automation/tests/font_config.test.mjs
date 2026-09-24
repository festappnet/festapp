import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-font-config-'));
const script = path.resolve('automation/configure_fonts.js');
const write = (name, content) => {
  const target = path.join(root, name);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, content);
};

try {
  write('automation/fonts/Futura PT Book.ttf', 'shared-font');
  write('fonts/Cerebri-Sans-Regular.ttf', 'tenant-regular');
  write('fonts/Cerebri-Sans-Bold.ttf', 'tenant-bold');
  write('pubspec.yaml', 'flutter:\n  fonts:\n    - family: Futura\n      fonts:\n        - asset: fonts/Futura PT Book.ttf\n  assets:\n    - assets/icons/\n');
  write('web_client/src/theme_config.css', "@font-face { font-family: 'Futura'; src: url('old.ttf'); }\nbody { font-family: 'Futura', sans-serif; }\n");
  write('lib/theme_config.dart', 'static final fontFamily = "Futura";\n');

  const configured = 'fonts/Cerebri-Sans-Regular.ttf,fonts/Cerebri-Sans-Bold.ttf';
  execFileSync('node', [script, root, 'Cerebri-Sans', configured], { stdio: 'pipe' });
  const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
  const css = fs.readFileSync(path.join(root, 'web_client/src/theme_config.css'), 'utf8');
  assert.match(pubspec, /family: Cerebri-Sans/);
  assert.match(pubspec, /asset: fonts\/Cerebri-Sans-Regular\.ttf/);
  assert.match(pubspec, /asset: fonts\/Cerebri-Sans-Bold\.ttf/);
  assert.doesNotMatch(pubspec, /asset: fonts\/Futura/);
  assert.match(css, /Cerebri-Sans-Regular\.ttf/);
  assert.match(css, /Cerebri-Sans-Bold\.ttf/);
  assert.doesNotMatch(css, /FuturaPTBook\.ttf/);
  assert.equal(fs.readFileSync(path.join(root, 'web_client/src/assets/fonts/Cerebri-Sans-Regular.ttf'), 'utf8'), 'tenant-regular');
  assert.match(fs.readFileSync(path.join(root, 'lib/theme_config.dart'), 'utf8'), /fontFamily = "Cerebri-Sans"/);

  assert.throws(() => execFileSync('node', [script, root, 'Cerebri-Sans', 'fonts/../automation/fonts/Futura PT Book.ttf'], { stdio: 'pipe' }));
  assert.throws(() => execFileSync('node', [script, root, 'Cerebri-Sans', 'fonts/Missing.ttf'], { stdio: 'pipe' }));
  console.log('Font configuration passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
