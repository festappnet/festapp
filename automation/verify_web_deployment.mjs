#!/usr/bin/env node
import { readConfig, resolveContext } from './release/organizers/context.mjs';
import { verifyMarketingHtml } from './release/organizers/verify.mjs';

import assert from 'node:assert/strict';
import { webProfileContract } from './lib/web_profile_contract.mjs';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

const origin = new URL(process.argv[2]).origin;
const expectedVersion = process.argv[3];
const configPath = path.resolve(process.argv[4] || 'automation/project.conf');
const publicOrigin = new URL(process.argv[5] || origin).origin;
const maxAttempts = Number(process.env.FESTAPP_VERIFY_ATTEMPTS || 30);
const requiredConsecutive = Number(process.env.FESTAPP_VERIFY_CONSECUTIVE || 3);
if (!expectedVersion) {
  throw new Error('Usage: verify_web_deployment.mjs <origin> <expected-version>');
}
const escapedVersion = expectedVersion.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const projectConfig = await readFile(configPath, 'utf8');
const configValue = (key) => projectConfig.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1]
  .trim()
  .replace(/^(['"])(.*)\1$/, '$2');
const profile = webProfileContract(configValue);
const legalRoutes = [
  ['PRIVACY_URL', '/privacy/', profile.legalPageMarker],
  ['PRIVACY_CHOICES_URL', '/privacy/choices/', profile.legalPageMarker],
  ['TERMS_URL', '/terms/', profile.legalPageMarker],
  ['SUPPORT_URL', '/support/', profile.legalPageMarker],
  ['DELETE_ACCOUNT_URL', '/delete-account/', profile.deletionPageMarker],
];
for (const [key, expectedPath] of legalRoutes) {
  const value = configValue(key);
  assert.ok(value, `project.conf is missing ${key}`);
  const url = new URL(value);
  assert.equal(url.origin, publicOrigin, `${key} differs from the public application origin`);
  assert.equal(url.pathname, expectedPath, `${key} does not use its canonical path`);
}

function versionFromHtml(html) {
  return html.match(/window\.__FESTAPP_BUILD_VERSION__\s*=\s*"([^"]+)"/)?.[1];
}

function assertRevalidated(response, label) {
  const value = response.headers.get('cache-control') || '';
  assert.match(
    value,
    /(?:no-cache|no-store|max-age=0|must-revalidate)/i,
    `${label} is missing revalidation cache headers: ${value || '(empty)'}`,
  );
}

async function fetchFresh(pathname) {
  const url = new URL(pathname, origin);
  url.searchParams.set('release-probe', `${expectedVersion}-${Date.now()}-${Math.random()}`);
  return fetch(url, {
    cache: 'no-store',
    headers: { 'cache-control': 'no-cache', pragma: 'no-cache' },
  });
}

const marketing = resolveContext(readConfig(configPath));
async function verifyOnce() {
  for (const page of marketing.pages) {
    const response = await fetchFresh(page.path);
    assert.equal(response.status,200,`marketing ${page.path}`);
    verifyMarketingHtml(await response.text(),page,marketing);
  }

  const [htmlResponse, manifestResponse, mainResponse, workerResponse, ...legalResponses] = await Promise.all([
    fetchFresh('/admin'),
    fetchFresh('/festapp-version.json'),
    fetchFresh('/main.dart.js'),
    fetchFresh('/festapp_service_worker.js'),
    ...legalRoutes.map(([, pathname]) => fetchFresh(pathname)),
  ]);
  for (const [label, response] of [
    ['HTML', htmlResponse],
    ['manifest', manifestResponse],
    ['main.dart.js', mainResponse],
    ['service worker', workerResponse],
  ]) {
    assert.equal(response.status, 200, `${label} returned HTTP ${response.status}`);
    assertRevalidated(response, label);
  }
  if (configValue('DEPLOY_TARGET') === 'cloudflare') {
    assert.equal(
      htmlResponse.headers.get('x-festapp-runtime'),
      'cloudflare-pages',
      'production domain is not served by the canonical Cloudflare Pages worker',
    );
  }
  for (let index = 0; index < legalResponses.length; index++) {
    const response = legalResponses[index];
    const [key] = legalRoutes[index];
    assert.equal(response.status, 200, `${key} returned HTTP ${response.status}`);
    assert.match(response.headers.get('content-type') || '', /^text\/html\b/i, `${key} is not HTML`);
    assertRevalidated(response, key);
  }

  const [html, manifest, main, worker] = await Promise.all([
    htmlResponse.text(),
    manifestResponse.json(),
    mainResponse.arrayBuffer(),
    workerResponse.text(),
  ]);
  const legalBodies = await Promise.all(legalResponses.map((response) => response.text()));
  for (let index = 0; index < legalBodies.length; index++) {
    const [key, , marker] = legalRoutes[index];
    assert.match(legalBodies[index], marker, `${key} resolved to a fallback or incomplete page`);
  }
  assert.equal(new Set(legalBodies).size, legalBodies.length, 'legal routes return duplicate fallback content');
  assert.equal(versionFromHtml(html), expectedVersion, 'HTML version is stale');
  assert.equal(manifest.version, expectedVersion, 'manifest version is stale');
  assert.equal(
    manifest.main,
    `main.dart.${expectedVersion.replace('+', '-')}.js`,
    'manifest points to the wrong main bundle',
  );
  assert.ok(
    html.includes(`"mainJsPath":"${manifest.main}"`),
    'live Flutter HTML does not load the manifest-selected immutable main bundle',
  );
  assert.ok(
    !html.includes('"mainJsPath":"main.dart.js"'),
    'live Flutter HTML still loads the service-worker-cacheable main.dart.js',
  );
  for (const script of [
    'festapp_update_prompt.js', 'festapp_flutter_bootstrap_guard.js', 'festapp_pwa_bridge.js',
  ]) {
    assert.ok(html.includes(`src="${script.replace(/\.js$/, `.${expectedVersion.replaceAll('+', '-')}.js`)}?v=${encodeURIComponent(expectedVersion)}"`),
      `Flutter support script ${script} is not bound to this release`);
  }
  assert.match(
    worker,
    new RegExp(`const BUILD_VERSION = "${escapedVersion}"`),
    'service worker version is stale',
  );

  const versionedResponse = await fetchFresh(`/${manifest.main}`);
  assert.equal(versionedResponse.status, 200, 'versioned main bundle is missing');
  assert.ok(
    Buffer.from(await versionedResponse.arrayBuffer()).equals(Buffer.from(main)),
    'canonical and versioned main bundles differ',
  );
  for (const [chunk] of Buffer.from(main).toString().matchAll(/main\.dart\.[^"'\s]+\.part\.js/g)) {
    assert.ok(chunk.startsWith(`${manifest.main}_`), `Mutable deferred library: ${chunk}`);
    const response = await fetchFresh(`/${chunk}`);
    assert.equal(response.status, 200, `Missing deferred library: ${chunk}`);
    assert.ok((await response.text()).includes('$__dart_deferred_initializers__'), `Invalid deferred library: ${chunk}`);
  }

}

let consecutive = 0;
let lastError;
for (let attempt = 1; attempt <= maxAttempts; attempt++) {
  try {
    await verifyOnce();
    consecutive++;
    if (consecutive >= requiredConsecutive) {
      console.log(`verify_web_deployment: ok (${expectedVersion}, ${consecutive} consecutive probes)`);
      process.exit(0);
    }
  } catch (error) {
    consecutive = 0;
    lastError = error;
  }
  await new Promise((resolve) => setTimeout(resolve, 2000));
}

console.error(`verify_web_deployment: FAILED for ${origin} (${expectedVersion})`);
console.error(lastError?.message || lastError);
process.exit(1);
