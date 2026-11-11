import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import {readFileSync, readFile, readdirSync, writeFileSync} from '../lib/migration_inputs.mjs';
const root = new URL('../../', import.meta.url);
const history = JSON.parse(fs.readFileSync(new URL('automation/historical-sql-manifest.json', root)));
const baseline = JSON.parse(fs.readFileSync(new URL('supabase/baseline/manifest.json', root)));

test('covered original bytes remain readable without active files or Git', async () => {
  const covered = history.files.filter(entry => entry.path.startsWith('supabase/migrations/') && entry.path.split('/').at(-1).slice(0,14) > baseline.compactedForwardsAfter);
  assert.equal(covered.length, 370);
  for (const entry of covered) {
    const file = new URL(entry.path, root);
    assert.equal(fs.existsSync(file), false);
    const bytes = readFileSync(file);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), entry.sha256);
  }
  const entry = covered.at(-1);
  assert.deepEqual(await readFile(new URL(entry.path, root)), readFileSync(new URL(entry.path, root)));
});

test('logical source history and physical active upgrades stay distinct', () => {
  const directory = new URL('supabase/migrations/', root);
  const active = fs.readdirSync(directory).filter(name => name.endsWith('.sql'));
  assert(active.every(name => name.slice(0,14) > baseline.coveredThrough));
  assert.equal(readdirSync(directory).filter(name => name.endsWith('.sql')).length, active.length + 370);
  assert.throws(() => readFileSync(new URL('supabase/migrations/20260101000000_unregistered.sql', root)), /Not a covered historical input/);
});

test('covered inputs cannot be regenerated in the active directory', () => {
  const file = new URL('supabase/migrations/20261106120000_payment_provider_connectors.sql', root);
  assert.equal(fs.existsSync(file), false);
  assert.throws(() => writeFileSync(file, 'SELECT changed;'), /immutable/);
  assert.equal(fs.existsSync(file), false);
});
