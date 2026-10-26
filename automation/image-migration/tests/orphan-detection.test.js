/**
 * Smoke tests for the orphan detection script (find-orphans.js).
 *
 * Tests 1-2 run without any environment variables.
 * Test 3 requires DATABASE_URL, CF_ACCOUNT_ID, R2_ACCESS_KEY_ID,
 *   R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME to run against live infrastructure.
 *
 * Run: node --test automation/image-migration/tests/orphan-detection.test.js
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const scriptPath = path.resolve(__dirname, '..', 'find-orphans.js');

describe('Orphan Detection Script', () => {
  it('find-orphans.js loads without syntax errors', () => {
    // node --check validates syntax without executing
    execSync(`node --check ${scriptPath}`, { encoding: 'utf8' });
    // If we get here, the syntax check passed
    assert.ok(true, 'Script has valid syntax');
  });

  it('find-orphans.js shows missing env vars message when no config', () => {
    try {
      // Run with empty env to trigger missing env var check
      execSync(`node ${scriptPath}`, {
        encoding: 'utf8',
        env: { PATH: process.env.PATH, NODE_PATH: process.env.NODE_PATH },
        timeout: 10000,
      });
      // If script exits 0, that's unexpected without env vars
      assert.fail('Expected script to exit with code 1 due to missing env vars');
    } catch (err) {
      // execSync throws on non-zero exit code
      const stderr = err.stderr || err.message || '';
      assert.ok(
        stderr.includes('Missing required environment variables'),
        `Expected stderr to mention missing env vars, got: ${stderr.substring(0, 200)}`
      );
    }
  });

  const hasEnvVars =
    process.env.DATABASE_URL &&
    process.env.CF_ACCOUNT_ID &&
    process.env.R2_ACCESS_KEY_ID &&
    process.env.R2_SECRET_ACCESS_KEY &&
    process.env.R2_BUCKET_NAME;

  it('find-orphans.js accepts --json flag without error', { skip: !hasEnvVars ? 'Requires DATABASE_URL, CF_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME' : false }, async () => {
    const output = execSync(`node ${scriptPath} --json`, {
      encoding: 'utf8',
      timeout: 60000,
    });

    // Verify output is valid JSON
    const parsed = JSON.parse(output);
    assert.ok(Array.isArray(parsed), 'Output should be a JSON array');

    // Each element should have key and size
    if (parsed.length > 0) {
      assert.ok('key' in parsed[0], 'Each orphan should have a key field');
      assert.ok('size' in parsed[0], 'Each orphan should have a size field');
    }
  });
});
