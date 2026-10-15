import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

// Run the actual orchestrator against simulated suite executables. A failed
// child must never become a green release gate after a later successful suite.
for (const [web, flutter, expected] of [[0, 0, 0], [17, 0, 1], [0, 23, 1]]) {
  test(`test_all propagates web=${web}, flutter=${flutter} to status ${expected}`, t => {
    const root = mkdtempSync(join(tmpdir(), 'festapp-test-status-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    for (const name of ['automation', 'web_client', 'bin']) mkdirSync(join(root, name));
    copyFileSync(new URL('../test_all.sh', import.meta.url), join(root, 'automation/test_all.sh'));
    writeFileSync(join(root, 'automation/test_client.sh'), '#!/bin/sh\nexec fvm flutter test\n', { mode: 0o755 });
    for (const [name, code] of [['npm', web], ['fvm', flutter], ['pg_isready', 1]]) {
      writeFileSync(join(root, 'bin', name), `#!/bin/sh\necho 'fixture ${name} executed'\nexit ${code}\n`, { mode: 0o755 });
    }
    const run = spawnSync('bash', [join(root, 'automation/test_all.sh'), 'web', 'flutter'], {
      encoding: 'utf8', timeout: 15_000,
      env: { ...process.env, DATABASE_URL: '', SUPABASE_URL: '', PATH: join(root, 'bin') + ':' + process.env.PATH },
    });
    assert.equal(run.status, expected, run.stdout + run.stderr);
    assert.match(run.stdout, /fixture fvm executed/, 'later suites still run after web failure');
  });
}
