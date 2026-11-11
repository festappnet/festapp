import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { timed } from '../../scripts/test_timings.mjs';

test('timing records failed work, keeps caller error, and omits error contents', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'festapp-timing-'));
  const original = process.env.FESTAPP_TIMINGS;
  const destination = join(directory, 'timings.jsonl');
  process.env.FESTAPP_TIMINGS = destination;
  try {
    const error = new Error('private fixture content');
    await assert.rejects(timed('fixture', async () => { throw error; }, {testId:'example'}), e => e === error);
    const text = readFileSync(destination, 'utf8');
    const event = JSON.parse(text);
    assert.equal(event.success, false);
    assert.equal(event.testId, 'example');
    assert.ok(event.seconds >= 0);
    assert.equal(event.clock, 'process-performance');
    assert.ok(!text.includes('private fixture content'));
  } finally {
    if (original === undefined) delete process.env.FESTAPP_TIMINGS;
    else process.env.FESTAPP_TIMINGS = original;
    rmSync(directory, {recursive:true,force:true});
  }
});
