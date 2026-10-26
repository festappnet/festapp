import assert from 'node:assert/strict';
import test from 'node:test';
import { verifyLegacyOriginRedirect } from '../verify_legacy_origin_redirect.mjs';

const legacy = 'https://legacy.example.net';
const canonical = 'https://canonical.example.net';
const version = '0.19.93+453';

function response(body, status, headers = {}) {
  return new Response(body, { status, headers });
}

function compliantFetch(url, options = {}) {
  const parsed = new URL(url);
  assert.equal(options.redirect === 'manual' || parsed.origin === canonical, true);
  if (parsed.origin === canonical) {
    return response(JSON.stringify({ version }), 200, { 'content-type': 'application/json' });
  }
  if (parsed.pathname === '/festapp_service_worker.js') {
    return response(
      `const FESTAPP_LEGACY_ORIGIN_RETIREMENT=true; const CANONICAL_ORIGIN='${canonical}';`,
      200,
      { 'content-type': 'application/javascript' },
    );
  }
  if (parsed.pathname === '/push/OneSignalSDKWorker.js') {
    return response('importScripts("onesignal.js")', 200, { 'content-type': 'application/javascript' });
  }
  return response('', 301, { location: canonical + parsed.pathname + parsed.search });
}

test('accepts a path-preserving redirect with retirement and push boundaries', async () => {
  await verifyLegacyOriginRedirect({
    legacyOrigin: legacy,
    canonicalOrigin: canonical,
    expectedVersion: version,
    fetchImpl: compliantFetch,
  });
});

test('rejects a legacy origin that still serves the application', async () => {
  await assert.rejects(
    verifyLegacyOriginRedirect({
      legacyOrigin: legacy,
      canonicalOrigin: canonical,
      expectedVersion: version,
      fetchImpl: (url, options) => {
        if (new URL(url).origin === legacy && new URL(url).pathname === '/') {
          return response('<html>legacy app</html>', 200, { 'content-type': 'text/html' });
        }
        return compliantFetch(url, options);
      },
    }),
    /legacy path did not return 301/,
  );
});
