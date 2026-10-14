#!/usr/bin/env node
// Opt-in real-browser regression: no server, backend, auth data, or paid provider.
// Prerequisites: fvm flutter pub get; installed local agent-browser Chrome.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = path.resolve(import.meta.dirname, '../..');
const packages = path.join(root, '.dart_tool/package_config.json');
assert.ok(existsSync(packages), 'Run fvm flutter pub get before this opt-in test');
const temporary = mkdtempSync(path.join(tmpdir(), 'festapp-storage-multitab-'));
const config = path.join(temporary, 'browser.json');
const session = `festapp-storage-multitab-${process.pid}`;
writeFileSync(config, '{}');
const browserArgs = ['--config', config, '--headed', 'false', '--session', session, '--json'];
function browser(...args) {
  const result = JSON.parse(execFileSync('agent-browser', [...browserArgs, ...args], {
    encoding: 'utf8', timeout: 30000,
  }));
  assert.equal(result.success, true, result.error);
  return result.data;
}
function evaluate(script) {
  const result = JSON.parse(execFileSync('agent-browser', [...browserArgs, 'eval', '--stdin'], {
    input: `(async () => (${script}))()`, encoding: 'utf8', timeout: 30000,
  }));
  assert.equal(result.success, true, result.error);
  return result.data.result;
}
try {
  execFileSync('fvm', ['dart', 'compile', 'js', `--packages=${packages}`,
    path.join(root, 'automation/tests/fixtures/storage_multitab/main.dart'),
    '-o', path.join(temporary, 'main.js')], { cwd: root, stdio: 'pipe', timeout: 60000 });
  writeFileSync(path.join(temporary, 'index.html'),
    '<!DOCTYPE html><html><body>Isolated storage fixture<script src="main.js"></script></body></html>');
  const url = pathToFileURL(path.join(temporary, 'index.html')).href;
  browser('open', url);
  const requester = browser('tab').tabs.find((tab) => tab.active).tabId;
  assert.deepEqual(evaluate("JSON.parse(await openSembastFixture('same-schema'))"),
    { status: 'opened', value: 'value-kept' });
  browser('tab', 'new', url);
  const holder = browser('tab').tabs.find((tab) => tab.active).tabId;
  assert.deepEqual(evaluate("JSON.parse(await openSembastFixture('same-schema'))"),
    { status: 'opened', value: 'value-kept' });

  evaluate(`(async () => {
    const request = indexedDB.open('legacy-schema', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('legacy-preserved');
    await new Promise((resolve, reject) => {
      request.onsuccess = resolve; request.onerror = () => reject(request.error);
    });
    window.legacyHandle = request.result;
    legacyHandle.onversionchange = () => { window.receivedUpgrade = true; };
    const transaction = legacyHandle.transaction('legacy-preserved', 'readwrite');
    transaction.objectStore('legacy-preserved').put('do-not-delete', 'marker');
    await new Promise((resolve) => { transaction.oncomplete = resolve; });
    return true;
  })()`);
  browser('tab', requester);
  const blocked = evaluate(`(async () => {
    const start = performance.now();
    return { ...JSON.parse(await openSembastFixture('legacy-schema')),
      elapsed: performance.now() - start };
  })()`);
  assert.equal(blocked.status, 'open-timeout', 'Real cross-tab upgrade must hit the bounded opener');
  assert.ok(blocked.elapsed >= 4900 && blocked.elapsed < 10000);
  browser('tab', holder);
  assert.equal(evaluate('window.receivedUpgrade'), true,
    'The holder must receive a real IndexedDB versionchange event');
  evaluate('legacyHandle.close()');
  browser('tab', requester);
  const recovered = evaluate(`(async () => {
    let opened;
    for (let attempt = 0; attempt < 100; attempt++) {
      opened = JSON.parse(await openSembastFixture('legacy-schema'));
      if (opened.status === 'opened') break;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    const request = indexedDB.open('legacy-schema');
    await new Promise((resolve, reject) => {
      request.onsuccess = resolve; request.onerror = () => reject(request.error);
    });
    const db = request.result;
    const get = db.transaction('legacy-preserved').objectStore('legacy-preserved').get('marker');
    const marker = await new Promise((resolve) => { get.onsuccess = () => resolve(get.result); });
    db.close();
    return { opened, marker };
  })()`);
  assert.deepEqual(recovered, {
    opened: { status: 'opened', value: 'value-kept' }, marker: 'do-not-delete',
  }, 'Releasing the blocking connection must recover without deleting stored data');
  console.log('storage_multitab_browser.test: same-schema OK; real upgrade blocked/bounded; release recovered; data preserved');
} finally {
  try { browser('close'); } finally { rmSync(temporary, { recursive: true, force: true }); }
}
