import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const requestTool = path.join(root, 'automation/release/google_play_request.mjs');
const planTool = path.join(root, 'automation/release/google_play_plan.mjs');

test('request helper creates a deterministic exact listing confirmation', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'play-request-'));
  const input = path.join(directory, 'input.json');
  const outputA = path.join(directory, 'request-a.json');
  const outputB = path.join(directory, 'request-b.json');
  fs.writeFileSync(input, JSON.stringify({
    packageName: 'example.app',
    operation: 'listing.update',
    language: 'cs-CZ',
    listing: { title: 'Example', shortDescription: 'Description' },
  }));

  const first = JSON.parse(execFileSync(process.execPath, [requestTool, input, outputA], { encoding: 'utf8' }));
  const second = JSON.parse(execFileSync(process.execPath, [requestTool, input, outputB], { encoding: 'utf8' }));
  const request = JSON.parse(fs.readFileSync(outputA, 'utf8'));

  assert.deepEqual(first, second);
  assert.deepEqual(fs.readFileSync(outputA), fs.readFileSync(outputB));
  assert.match(request.confirmation, /^listing\.update\|example\.app\|cs-CZ\|[a-f0-9]{64}$/);
  assert.equal(fs.statSync(outputA).mode & 0o777, 0o600);
});

test('batch planner accepts supported operations and rejects more than thirty', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'play-plan-'));
  const valid = path.join(directory, 'valid.json');
  fs.writeFileSync(valid, JSON.stringify([
    { tenant: 'example', packageName: 'example.app', operation: 'app.inspect', requestSha256: 'a'.repeat(64) },
  ]));
  const matrix = JSON.parse(execFileSync(process.execPath, [planTool, valid], { encoding: 'utf8' }));
  assert.equal(matrix.include.length, 1);

  const invalid = path.join(directory, 'invalid.json');
  fs.writeFileSync(invalid, JSON.stringify(Array.from({ length: 31 }, (_, index) => ({
    tenant: `example-${index}`,
    packageName: `example.app${index}`,
    operation: 'app.inspect',
    requestSha256: 'b'.repeat(64),
  }))));
  const result = spawnSync(process.execPath, [planTool, invalid], { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /1 to 30/);
});
