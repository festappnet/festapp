import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  discoverDenoTests,
  evaluateEdgeFunctionTestCoverage,
} from '../hetzner-supabase/merge/edge-function-test-coverage.mjs';

test('Deno discovery includes both repository test naming conventions', () => {
  const tests = discoverDenoTests();
  assert.ok(tests.includes('supabase/functions/bank-mail-parser/test_parser.ts'));
  assert.ok(tests.includes('supabase/functions/notify/webhookAuth_test.ts'));
  const runner = fs.readFileSync('automation/test_all.sh', 'utf8');
  assert.match(runner, /-name "\*_test\.ts"/);
  assert.match(runner, /edge-function-test-coverage\.mjs/);
});

test('every production Edge Function has executable smoke and behavior coverage', () => {
  const result = evaluateEdgeFunctionTestCoverage();
  assert.equal(result.status, 'pass', result.blockers.join('\n'));
  assert.equal(result.unknownFunctions.length, 0);
  assert.equal(result.uncoveredFunctions.length, 0);
  assert.equal(result.productionFunctions, 19);
  assert.equal(result.excludedFunctions, 1);
});
