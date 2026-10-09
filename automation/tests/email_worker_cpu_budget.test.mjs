import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { spawnSync } from 'node:child_process';

const runtime = new URL('../hetzner-supabase/runtime/', import.meta.url);
const patch = new URL('patch-function-email-cpu-budget.py', runtime).pathname;

test('email PDF preparation gets a bounded CPU budget while other routes retain defaults', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'email-cpu-'));
  try {
    const file = path.join(dir, 'index.ts');
    const source = 'checkAuthorization(req);\n    const worker = await EdgeRuntime.userWorkers.create({\n      servicePath,\n      memoryLimitMb,\n      envVars,\n    })\n';
    fs.writeFileSync(file, source);
    assert.equal(spawnSync('python3', [patch, file]).status, 0);
    const result = fs.readFileSync(file, 'utf8');
    const options = result.slice(result.indexOf('create(') + 7, result.lastIndexOf(')'));
    for (const service_name of ['process-email-queue', 'bank-sync-webhook', 'send-ticket-order', 'google-auth-start']) {
      const actual = vm.runInNewContext(`(${options})`, { service_name, servicePath: 'path', memoryLimitMb: 512, envVars: [] });
      assert.equal(actual.cpuTimeSoftLimitMs, service_name === 'process-email-queue' ? 20000 : undefined);
      assert.equal(actual.cpuTimeHardLimitMs, service_name === 'process-email-queue' ? 30000 : undefined);
      assert.equal(actual.memoryLimitMb, 512);
    }
    assert.ok(result.startsWith('checkAuthorization(req);\n'));
    assert.equal(spawnSync('python3', [patch, file]).status, 0);
    assert.equal(fs.readFileSync(file, 'utf8'), result);
    for (const invalid of ['unrecognized router', source.replace('      envVars,', '      cpuTimeHardLimitMs: 0,\n      envVars,')]) {
      fs.writeFileSync(file, invalid);
      assert.notEqual(spawnSync('python3', [patch, file]).status, 0);
      assert.equal(fs.readFileSync(file, 'utf8'), invalid);
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('bundle installs and runtime upgrades preserve the email CPU policy', () => {
  const installer = fs.readFileSync(new URL('install-production-function-bundle.sh', runtime), 'utf8');
  const upgrade = fs.readFileSync(new URL('upgrade-installed-production-runtime.sh', runtime), 'utf8');
  assert.match(installer, /patch-function-email-cpu-budget.py/);
  assert.match(upgrade, /install_runtime_file "\$SCRIPT_DIR\/patch-function-email-cpu-budget.py" "\$COMPOSE_DIR\/patch-function-email-cpu-budget.py"/);
  assert.match(upgrade, /patch-function-static-assets.py patch-function-email-cpu-budget.py/);
});
