#!/usr/bin/env node

import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';

function normalizedOrigin(value, label) {
  const url = new URL(value);
  assert.equal(url.protocol, 'https:', `${label} must use HTTPS`);
  assert.equal(url.pathname, '/', `${label} must not contain a path`);
  return url.origin;
}

function escapedRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export async function verifyLegacyOriginRedirect({
  legacyOrigin,
  canonicalOrigin,
  expectedVersion,
  fetchImpl = fetch,
}) {
  const legacy = normalizedOrigin(legacyOrigin, 'legacy origin');
  const canonical = normalizedOrigin(canonicalOrigin, 'canonical origin');
  assert.notEqual(legacy, canonical, 'legacy and canonical origins must differ');
  assert.ok(expectedVersion, 'expectedVersion is required');

  const nonce = `${Date.now()}-${Math.random()}`;
  const redirectPaths = [
    '/',
    `/form/__festapp_redirect_probe?source=${nonce}`,
    `/web-assets/__festapp_missing_chunk__.js?source=${nonce}`,
  ];
  for (const pathname of redirectPaths) {
    const response = await fetchImpl(`${legacy}${pathname}`, {
      redirect: 'manual',
      cache: 'no-store',
    });
    assert.equal(response.status, 301, `legacy path did not return 301: ${pathname}`);
    assert.equal(
      response.headers.get('location'),
      `${canonical}${pathname}`,
      `legacy path did not preserve path/query: ${pathname}`,
    );
  }

  const retirement = await fetchImpl(`${legacy}/festapp_service_worker.js?source=${nonce}`, {
    redirect: 'manual',
    cache: 'no-store',
  });
  assert.equal(retirement.status, 200, 'retirement service worker is unavailable');
  assert.match(retirement.headers.get('content-type') || '', /javascript/i, 'retirement worker is not JavaScript');
  const retirementSource = await retirement.text();
  assert.match(retirementSource, /FESTAPP_LEGACY_ORIGIN_RETIREMENT/, 'retirement worker marker is missing');
  assert.match(
    retirementSource,
    new RegExp(`CANONICAL_ORIGIN\\s*=\\s*(['"])${escapedRegExp(canonical)}\\1`),
    'retirement worker canonical origin is wrong',
  );

  const pushWorker = await fetchImpl(`${legacy}/push/OneSignalSDKWorker.js?source=${nonce}`, {
    redirect: 'manual',
    cache: 'no-store',
  });
  assert.equal(pushWorker.status, 200, 'legacy OneSignal worker boundary is unavailable');

  const manifestResponse = await fetchImpl(`${canonical}/festapp-version.json?source=${nonce}`, {
    cache: 'no-store',
  });
  assert.equal(manifestResponse.status, 200, 'canonical release manifest is unavailable');
  const manifest = await manifestResponse.json();
  assert.equal(manifest.version, expectedVersion, 'canonical release version is stale');
}

async function main() {
  const [legacyOrigin, canonicalOrigin, expectedVersion] = process.argv.slice(2);
  if (!legacyOrigin || !canonicalOrigin || !expectedVersion) {
    throw new Error('Usage: verify_legacy_origin_redirect.mjs LEGACY_ORIGIN CANONICAL_ORIGIN VERSION');
  }
  await verifyLegacyOriginRedirect({ legacyOrigin, canonicalOrigin, expectedVersion });
  console.log(`legacy origin redirect: ok (${legacyOrigin} -> ${canonicalOrigin}, ${expectedVersion})`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`legacy origin redirect: FAILED (${error.message})`);
    process.exitCode = 1;
  });
}
