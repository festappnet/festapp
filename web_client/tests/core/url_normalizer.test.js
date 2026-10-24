import test from 'node:test';
import assert from 'node:assert/strict';
import { legacyHashTarget, normalizeUrl } from '../../src/services/url_normalizer.js';

test('shared legacy routing preserves query and rejects off-origin targets', () => {
  for (const path of ['/form/ples?preview=true', '/scan?occasion=42', '/login-qr?code=a%2Bb', '/event/admin?tab=orders']) {
    assert.equal(legacyHashTarget('https://vstupenky.online/?utm_source=old#' + path), path);
    assert.equal(normalizeUrl('https://preview.pages.dev/#' + path), path.split('?')[0]);
  }
  for (const fragment of ['#ukazka', '#faq', '#reference', '#//evil.invalid/path', '#/https://evil.invalid']) {
    assert.equal(legacyHashTarget('https://vstupenky.online/' + fragment), null);
  }
});
