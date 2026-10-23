import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
const read = p => fs.readFileSync(p, 'utf8');
const inventory = JSON.parse(read('docs/security/abuse-surface-inventory.json'));
const coverage = JSON.parse(read('supabase/functions/test-coverage.json'));

test('abuse enforcement never introduces a business trigger', () => {
  assert.doesNotMatch(read('supabase/migrations/20261016100000_abuse_admission.sql'), /RETURNS\s+trigger\b/i);
  assert.doesNotMatch(read('database/functions/seed/triggers.sql'), /CREATE TRIGGER (?!handle_updated_at\b)/);
  assert.ok(!fs.existsSync('database/functions/notifications/deliver_log_notification.sql'));
});

test('production route changes require an explicit abuse disposition and evidence', () => {
  assert.deepEqual(inventory.edgeFunctions.map(r => r.name).sort(), Object.keys(coverage.production).sort());
  for (const route of inventory.edgeFunctions) {
    assert.deepEqual(route.policies, (coverage.production[route.name].abusePolicy ?? []));
    assert.ok((route.policies.length || route.budgetDisposition === 'bounded-authenticated-protocol') && route.owner && route.reviewBy && route.reason.length > 30);
    assert.ok(fs.existsSync(route.path));
    for (const evidence of route.evidence) assert.ok(fs.existsSync(evidence));
  }
});
test('new domain commands retain their SQL boundary and canonical forward migration', () => {
  for (const op of inventory.operations) {
    assert.ok(read(op.source).includes(`public.${op.admission}(`), op.operation);
    assert.ok(fs.existsSync(op.evidence));
  }
  execFileSync('python3', ['automation/assemble-abuse-migration.py', '--check'], { stdio: 'pipe' });
});
test('each seeded family has a closed required-rule contract, without duplicate rule keys', () => {
  const rows = [...read('database/functions/abuse/seeds.sql').matchAll(/\('([^']+)','([^']+)','(?:actor|unit|organization|recipient|global)','(?:rolling|cumulative|occupancy|bytes|duration|items)'/g)];
  const counts = new Map(); const keys = new Set();
  for (const [, rule, budget] of rows) { assert.ok(!keys.has(rule), rule); keys.add(rule); counts.set(budget, (counts.get(budget) ?? 0) + 1); }
  const required = new Map([...read('database/functions/abuse/policy.sql').matchAll(/WHEN '([^']+)' THEN (\d+)/g)].map(([, key, n]) => [key, Number(n)]));
  for (const [budget, count] of counts) assert.equal(required.get(budget), count, budget);
  assert.doesNotMatch(read('supabase/functions/exchange-login-qr/index.ts'), /new Map|x-forwarded-for/);
});

test('worker routes retain explicit admission or a reviewed compatibility boundary', () => {
  assert.deepEqual(inventory.workers.map(w => w.name).sort(), ['image-worker', 'self-hosted-monitor', 'sync-worker']);
  for (const worker of inventory.workers) {
    assert.ok(worker.owner && worker.reviewBy && worker.routes.length && worker.remaining);
    assert.ok(fs.existsSync(worker.entrypoint));
    for (const path of worker.evidence) assert.ok(fs.existsSync(path));
    for (const route of worker.routes) assert.ok(route.path && route.policy && route.status);
  }
  const image = inventory.workers.find(w => w.name === 'image-worker');
  const explicitPaths = new Set([...read(image.entrypoint).matchAll(/url\.pathname(?: === '([^']+)'|\.startsWith\('([^']+)'\))/g)].map(([, exact, prefix]) => exact ?? prefix));
  assert.deepEqual([...explicitPaths].sort(), image.routes.map(r => r.path).filter(p => !p.startsWith('*')).sort());
  assert.ok(image.routes.some(r => r.path === '*public-read'));
  const sync = inventory.workers.find(w => w.name === 'sync-worker');
  assert.ok(read(sync.entrypoint).includes(sync.routeExpression), 'sync path contract changed; review the abuse inventory');
});

test('unmigrated canonical function changes still fail the immutable-history check', () => {
  const result = spawnSync('python3', ['-c', `
from pathlib import Path
from unittest.mock import patch
import runpy
original = Path.read_text
def changed(path, *args, **kwargs):
    value = original(path, *args, **kwargs)
    if str(path).endswith('/database/functions/occasion_setup/finalize.sql'):
        value = value.replace('Draft review required', 'Unmigrated test-only drift')
    return value
with patch.object(Path, 'read_text', changed):
    runpy.run_path('automation/assemble-abuse-migration.py', run_name='__main__')
`], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Missing forward migration for finalize_occasion_setup_draft/);
});
