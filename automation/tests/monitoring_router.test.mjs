import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
const patch = new URL('../hetzner-supabase/runtime/patch-function-monitoring.py', import.meta.url).pathname;
test('router patch is idempotent and rejects dispatch drift before writing', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-monitoring-router-'));
  const file = path.join(dir, 'index.ts');
  try {
    fs.writeFileSync(file, 'return await worker.fetch(req)\n');
    assert.equal(spawnSync('python3', [patch, file]).status, 0);
    const source = fs.readFileSync(file, 'utf8');
    assert.match(source, /monitorEdgeRequest\(service_name/);
    assert.equal(spawnSync('python3', [patch, file]).status, 0);
    assert.equal(fs.readFileSync(file, 'utf8'), source);
    fs.writeFileSync(file, 'return worker.request(req)');
    assert.notEqual(spawnSync('python3', [patch, file]).status, 0);
    assert.equal(fs.readFileSync(file, 'utf8'), 'return worker.request(req)');
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
