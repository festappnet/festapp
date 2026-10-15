import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, cpSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

test('tenant generator produces truthful standalone HTML and removes page/nav on tenant switch', t => {
  const root = mkdtempSync(join(tmpdir(), 'festapp-seo-generator-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, 'automation/release'), { recursive: true });
  mkdirSync(join(root, 'web_client'), { recursive: true });
  cpSync(new URL('../release/render_organizer_page.mjs', import.meta.url), join(root, 'automation/release/render_organizer_page.mjs'));
  cpSync(new URL('../release/organizers', import.meta.url), join(root, 'automation/release/organizers'), { recursive: true });
  cpSync(new URL('../../web_client/index.html', import.meta.url), join(root, 'web_client/index.html'));
  const config = join(root, 'automation/project.conf');
  writeFileSync(config, 'DOMAIN=vstupenky.online\nWEB_LINK=https://vstupenky.online\nAPP_NAME="Tickets & events"\nTHEME_SEED_3=#4465a6\n');
  const render = () => {
    const run = spawnSync(process.execPath, [join(root, 'automation/release/render_organizer_page.mjs'), '--config', config], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
  };
  render();
  const output = join(root, 'web/organizers-page');
  const html = readFileSync(output, 'utf8');
  assert.ok(html.includes('Tickets &amp; events'));
  assert.ok(html.includes('href="https://vstupenky.online/pro-poradatele"'));
  assert.equal((html.match(/<h1[ >]/g) || []).length, 1);
  assert.ok(html.includes('href="/?create=1"'));
  assert.ok(html.includes('info@festapp.net'));
  assert.ok(!html.includes('{{'));
  assert.ok(!html.includes('fonts.googleapis.com'));
  render(); assert.equal(readFileSync(output, 'utf8'), html);
  const builtIndex = join(root, 'web_client/built.html');
  writeFileSync(builtIndex, '<link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet"><link rel="stylesheet" href="/web-assets/index-fixture.css">');
  const bundleOutput = join(root, 'bundle/organizers-page');
  const build = spawnSync(process.execPath, [join(root, 'automation/release/render_organizer_page.mjs'), '--config', config, '--built-index', builtIndex, '--output', bundleOutput], { encoding: 'utf8' });
  assert.equal(build.status, 0, build.stderr);
  const bundled = readFileSync(bundleOutput, 'utf8');
  assert.ok(bundled.includes('href="/web-assets/index-fixture.css"'));
  assert.ok(!bundled.includes('fonts.googleapis.com'));
  assert.equal(readFileSync(output, 'utf8'), html, 'compiled theme must not alter the deterministic source leaf');

  writeFileSync(config, 'DOMAIN=other.invalid\nWEB_LINK=https://other.invalid\nAPP_NAME=Other\n');
  render(); assert.equal(existsSync(output), false);
  assert.ok(!readFileSync(join(root, 'web_client/index.html'), 'utf8').includes('href="/pro-poradatele"'));
});

test('actual build stamping uses configured canonical origin and the shared classifier', t => {
  const root = mkdtempSync(join(tmpdir(), 'festapp-worker-stamp-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
  const worker = join(root, 'worker.js'); const config = join(root, 'project.conf');
  writeFileSync(worker, script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1]);
  writeFileSync(config, 'WEB_LINK=https://vstupenky.online\nAPP_NAME=Tickets\nFORCE_OCCASION_LINK=\nIS_APP_SUPPORTED=true\n');
  const python = script.match(/python3 - build\/web\/_worker.js automation\/project.conf <<'PY'\n([\s\S]*?)\nPY/)[1];
  const result = spawnSync('python3', ['-', worker, config], { input: python, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const source = readFileSync(worker, 'utf8');
  assert.ok(source.includes('const CANONICAL_ORIGIN = "https://vstupenky.online";'));
  assert.ok(source.includes('const ORGANIZERS_ENABLED = true;'));
  assert.ok(source.includes('function classifyOccasions('));
  assert.ok(!source.includes('// SHARED_CATALOG_CLASSIFICATION'));
});
