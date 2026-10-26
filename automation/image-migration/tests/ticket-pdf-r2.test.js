/**
 * Test that R2 image URLs used by ticket PDF generation are resolvable.
 *
 * These tests verify URL resolution (HTTP 200, correct content-type),
 * NOT full PDF generation (which requires Deno runtime + Supabase edge function).
 *
 * Requires: TEST_WORKER_URL environment variable (e.g. https://img.festapp.net)
 * If not set, all tests are skipped gracefully.
 *
 * Run: node --test automation/image-migration/tests/ticket-pdf-r2.test.js
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

const TEST_WORKER_URL = process.env.TEST_WORKER_URL;

const skip = !TEST_WORKER_URL;

describe('Ticket PDF R2 Image URL Resolution', { skip }, () => {
  it('default ticket background image is resolvable at R2 URL', async () => {
    const url = `${TEST_WORKER_URL}/default.jpg`;
    const response = await fetch(url);

    assert.equal(response.status, 200, `Expected 200 for ${url}, got ${response.status}`);

    const contentType = response.headers.get('content-type');
    assert.ok(
      contentType && contentType.startsWith('image/'),
      `Expected image/* content-type, got ${contentType}`
    );

    const contentLength = response.headers.get('content-length');
    assert.ok(
      contentLength && parseInt(contentLength, 10) > 0,
      `Expected content-length > 0, got ${contentLength}`
    );
  });

  it('hvezdamorska logo is resolvable at R2 URL', async () => {
    const url = `${TEST_WORKER_URL}/hvezdamorska/hvezdamorskaCKlogo.png`;
    const response = await fetch(url);

    assert.equal(response.status, 200, `Expected 200 for ${url}, got ${response.status}`);

    const contentType = response.headers.get('content-type');
    assert.ok(
      contentType && contentType.startsWith('image/'),
      `Expected image/* content-type, got ${contentType}`
    );

    const contentLength = response.headers.get('content-length');
    assert.ok(
      contentLength && parseInt(contentLength, 10) > 0,
      `Expected content-length > 0, got ${contentLength}`
    );
  });

  it('editor/ path is publicly fetchable without auth', async () => {
    const url = `${TEST_WORKER_URL}/editor/default.jpg`;
    const response = await fetch(url);

    // Should be 200 (if file exists) or 404 (if not placed there) but NOT 401 or 403
    assert.notEqual(response.status, 401, `editor/ path should not require auth (got 401)`);
    assert.notEqual(response.status, 403, `editor/ path should not be forbidden (got 403)`);
  });
});
