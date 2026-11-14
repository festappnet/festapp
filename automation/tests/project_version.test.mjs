#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import os from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parseFlutterVersion } from '../flutter_version.mjs';
import { parseProjectVersion, readProjectVersion } from '../release/project_version.mjs';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

test('version generation stamps both HTML entry points before module loading', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-entry-version-'));
  try {
    for (const directory of ['automation/lib', 'automation/release', 'web', 'web_client/src/services']) {
      fs.mkdirSync(path.join(root, directory), { recursive: true });
    }
    fs.copyFileSync(path.join(projectRoot, 'automation/release/project_version.mjs'), path.join(root, 'automation/release/project_version.mjs'));
    fs.writeFileSync(path.join(root, 'automation/release/software-version.conf'), 'VERSION=1.2.3+456\n');
    fs.copyFileSync(path.join(projectRoot, 'automation/configure_version.js'),
      path.join(root, 'automation/configure_version.js'));
    fs.copyFileSync(path.join(projectRoot, 'automation/lib/write_if_changed.cjs'), path.join(root, 'automation/lib/write_if_changed.cjs'));
    fs.copyFileSync(path.join(projectRoot, 'automation/lib/startup_theme.cjs'), path.join(root, 'automation/lib/startup_theme.cjs'));
    fs.copyFileSync(path.join(projectRoot, 'web_client/src/services/theme_preference.js'), path.join(root, 'web_client/src/services/theme_preference.js'));
    fs.cpSync(path.join(projectRoot, 'web_client/src/runtime'), path.join(root, 'web_client/src/runtime'), {recursive:true});
    for (const entry of ['web/index.html', 'web_client/index.html']) {
      fs.writeFileSync(path.join(root, entry),
        '<meta name="color-scheme" content="light dark"><script>window.__FESTAPP_BUILD_VERSION__ = "old";</script>');
    }
    const result = spawnSync(process.execPath,
      [path.join(root, 'automation/configure_version.js'), '1.2.3+456'], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const entries=['web/index.html','web_client/index.html','web_client/src/version.js'];
    const mtimes=entries.map(entry=>fs.statSync(path.join(root,entry)).mtimeMs);
    const repeated=spawnSync(process.execPath,[path.join(root,'automation/configure_version.js'),'1.2.3+456'],{encoding:'utf8'});
    assert.equal(repeated.status,0,repeated.stderr);
    assert.deepEqual(entries.map(entry=>fs.statSync(path.join(root,entry)).mtimeMs),mtimes);
    for (const entry of ['web/index.html', 'web_client/index.html']) {
      assert.match(fs.readFileSync(path.join(root, entry), 'utf8'), /"1\.2\.3\+456"/);
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('extracts the canonical build number for App Store tooling', () => {
  assert.deepEqual(parseProjectVersion('APP_NAME=Festapp\nVERSION=1.2.3+456\n'), {
    full: '1.2.3+456',
    version: '1.2.3',
    build: '456',
  });
});

test('accepts a quoted version and rejects a missing numeric build', () => {
  assert.equal(parseProjectVersion('VERSION="2.0.0-beta.1+7"\n').version, '2.0.0-beta.1');
  assert.throws(() => parseProjectVersion('VERSION=2.0.0\n'), /numeric-build/);
});

test('extracts the canonical exact Flutter SDK version', () => {
  assert.equal(parseFlutterVersion('APP_NAME=Festapp\nFLUTTER_VERSION=3.47.2\n'), '3.47.2');
  assert.equal(parseFlutterVersion('FLUTTER_VERSION="3.47.2"\n'), '3.47.2');
  assert.throws(() => parseFlutterVersion('FLUTTER_VERSION=stable\n'), /exact semantic version/);
});

test('all version sync entry points use the canonical generator', () => {
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(projectRoot, 'web_client/package.json'), 'utf8'),
  );
  const incrementScript = fs.readFileSync(
    path.join(projectRoot, 'automation/increment_version.js'),
    'utf8',
  );

  assert.equal(packageJson.scripts.prestart, 'node ../automation/configure_version.js');
  assert.match(incrementScript, /automation\/configure_version\.js/);
  assert.doesNotMatch(incrementScript, /sync_version\.js/);
  assert.equal(
    fs.existsSync(path.join(projectRoot, 'web_client/scripts/sync_version.js')),
    false,
  );
});


test('software version ignores tenant config and inherited VERSION environment', () => {
  const expected = readProjectVersion();
  const result = spawnSync(process.execPath, ['automation/release/project_version.mjs', '--json'], {
    cwd: projectRoot, encoding: 'utf8', env: {...process.env, VERSION: '9.9.9+999999'},
  });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), expected);
  const mismatch = spawnSync(process.execPath, ['automation/configure_version.js', '0.0.0+1'], {
    cwd: projectRoot, encoding: 'utf8',
  });
  assert.notEqual(mismatch.status, 0);
  assert.match(mismatch.stderr, /override differs/);
});

test('Android planning requires the tenant to inherit the current software generation', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-software-generation-'));
  const git = (...args) => execFileSync('git', args, {cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();
  try {
    const release = path.join(root, 'automation/release');
    fs.mkdirSync(release, {recursive: true});
    for (const name of ['project_version.mjs', 'android_ci_plan.mjs']) {
      fs.copyFileSync(path.join(projectRoot, 'automation/release', name), path.join(release, name));
    }
    const owner = path.join(release, 'software-version.conf');
    fs.writeFileSync(owner, 'VERSION=1.2.3+456\n');
    git('init', '-b', 'main');
    git('config', 'user.name', 'Release fixture');
    git('config', 'user.email', 'release@example.invalid');
    git('add', '.');
    git('commit', '-m', 'Previous software generation');
    git('branch', 'prod/one');
    fs.writeFileSync(owner, 'VERSION=1.2.4+457\n');
    git('add', '.');
    git('commit', '-m', 'Current software generation');
    git('remote', 'add', 'origin', root);
    const input = path.join(root, 'targets.json');
    fs.writeFileSync(input, '["one"]');
    const plan = () => spawnSync(process.execPath, [path.join(release, 'android_ci_plan.mjs'), 'candidate', input], {
      cwd: root, encoding: 'utf8',
    });
    const stale = plan();
    assert.notEqual(stale.status, 0, JSON.stringify({stdout: stale.stdout, stderr: stale.stderr}));
    assert.match(stale.stderr, /must inherit canonical software 1\.2\.4\+457/);
    git('update-ref', 'refs/heads/prod/one', 'HEAD');
    const current = plan();
    assert.equal(current.status, 0, current.stderr);
    assert.equal(JSON.parse(current.stdout).include[0].sourceSha, git('rev-parse', 'HEAD'));
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('tenant pre-commit preparation cannot increment the shared software version', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-tenant-version-'));
  try {
    fs.mkdirSync(path.join(root, 'automation/release'), {recursive: true});
    fs.copyFileSync(path.join(projectRoot, 'automation/increment_version.js'), path.join(root, 'automation/increment_version.js'));
    fs.writeFileSync(path.join(root, 'automation/tenant-overlay.json'), '{"tenantId":"one"}\n');
    const owner = path.join(root, 'automation/release/software-version.conf');
    const before = 'VERSION=1.2.3+456\n';
    fs.writeFileSync(owner, before);
    const result = spawnSync(process.execPath, [path.join(root, 'automation/increment_version.js')], {
      cwd: root, encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(owner, 'utf8'), before);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
