#!/usr/bin/env node

import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import {
  parseSupabaseOrigin,
  resolvedAuthStorageKey,
} from './lib/supabase_client_config.mjs';
import {
  backendActivationDocument,
  canonicalBackendActivationSha256,
  canonicalBackendProfileSha256,
} from './lib/backend_activation_manifest.mjs';

const buildDir = path.resolve(process.argv[2] || 'build/web');
const expectedVersion = process.argv[3];
const configPath = path.resolve(process.argv[4] || 'automation/project.conf');
const target = process.argv[5] || 'cloudflare';
if (!expectedVersion) {
  throw new Error('Usage: verify_web_build.mjs <build-dir> <expected-version> [project-conf] [cloudflare|static]');
}
assert.ok(['cloudflare', 'static'].includes(target), `unsupported deploy target: ${target}`);
const escapedVersion = expectedVersion.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const manifest = JSON.parse(await readFile(
  path.join(buildDir, 'festapp-version.json'),
  'utf8',
));
assert.equal(manifest.version, expectedVersion, 'manifest version differs from release version');
assert.equal(
  manifest.main,
  `main.dart.${expectedVersion.replace('+', '-')}.js`,
  'manifest points to an unexpected main bundle',
);

const flutterEntry = target === 'cloudflare' ? 'flutter' : 'flutter.html';
const authBridgeEntry = target === 'cloudflare' ? 'auth_bridge' : 'auth_bridge.html';
const [flutterHtml, main, versionedMain, worker, siteManifestText, authBridge] = await Promise.all([
  readFile(path.join(buildDir, flutterEntry), 'utf8'),
  readFile(path.join(buildDir, 'main.dart.js')),
  readFile(path.join(buildDir, manifest.main)),
  readFile(path.join(buildDir, 'festapp_service_worker.js'), 'utf8'),
  readFile(path.join(buildDir, 'site.webmanifest'), 'utf8'),
  readFile(path.join(buildDir, authBridgeEntry), 'utf8'),
]);
assert.match(
  flutterHtml,
  new RegExp(`window\\.__FESTAPP_BUILD_VERSION__\\s*=\\s*"${escapedVersion}"`),
  'Flutter HTML has a different build version',
);
assert.ok(
  flutterHtml.includes(`"mainJsPath":"${manifest.main}"`),
  'Flutter HTML does not load its immutable versioned main bundle',
);
assert.ok(
  !flutterHtml.includes('"mainJsPath":"main.dart.js"'),
  'Flutter HTML still loads the mutable main.dart.js entrypoint',
);
assert.deepEqual(versionedMain, main, 'versioned and canonical main bundles differ');

const projectConfig = await readFile(configPath, 'utf8');
const configValue = (key) => projectConfig.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1]
  .trim()
  .replace(/^(['"])(.*)\1$/, '$2');
const configuredDomain = configValue('DOMAIN');
const configuredAppName = configValue('APP_NAME');
const legalPages = [
  ['PRIVACY_URL', '/privacy/', 'privacy/index.html'],
  ['PRIVACY_CHOICES_URL', '/privacy/choices/', 'privacy/choices/index.html'],
  ['TERMS_URL', '/terms/', 'terms/index.html'],
  ['SUPPORT_URL', '/support/', 'support/index.html'],
];
const expectedLegalOrigin = `https://${configuredDomain}`;
const legalBodies = [];
for (const [key, expectedPath, output] of legalPages) {
  const configuredUrl = configValue(key);
  assert.ok(configuredUrl, `project.conf is missing ${key}`);
  const url = new URL(configuredUrl);
  assert.equal(url.origin, expectedLegalOrigin, `${key} must use the configured deploy origin`);
  assert.equal(url.pathname, expectedPath, `${key} must use the canonical path`);
  assert.equal(url.search, '', `${key} must not contain a query`);
  assert.equal(url.hash, '', `${key} must not contain a fragment`);
  const body = await readFile(path.join(buildDir, output), 'utf8');
  assert.match(body, /<nav aria-label="Právní informace">/, `${output} is not a rendered legal page`);
  assert.match(body, /<h1>[^<]+<\/h1>/, `${output} lacks its legal heading`);
  assert.match(body, new RegExp(`<title>[^<]+ \\| ${configuredAppName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}</title>`), `${output} has foreign tenant branding`);
  assert.doesNotMatch(body, /window\.__FESTAPP_BUILD_VERSION__/, `${output} resolved to the Flutter SPA shell`);
  for (const [, navigationPath] of legalPages) {
    assert.match(body, new RegExp(`href="${navigationPath.replaceAll('/', '\\/')}"`), `${output} lacks the canonical legal navigation`);
  }
  legalBodies.push(body);
}
assert.equal(new Set(legalBodies).size, legalBodies.length, 'legal routes resolve to duplicate fallback content');
const deleteAccountUrl = configValue('DELETE_ACCOUNT_URL');
assert.ok(deleteAccountUrl, 'project.conf is missing DELETE_ACCOUNT_URL');
const parsedDeleteAccountUrl = new URL(deleteAccountUrl);
assert.equal(parsedDeleteAccountUrl.origin, expectedLegalOrigin, 'DELETE_ACCOUNT_URL must use the configured deploy origin');
assert.equal(parsedDeleteAccountUrl.pathname, '/delete-account/', 'DELETE_ACCOUNT_URL must use the canonical path');
const deleteAccountBody = await readFile(path.join(buildDir, 'delete-account/index.html'), 'utf8');
assert.match(deleteAccountBody, /<h1>Smazání účtu<\/h1>/, 'account deletion route lacks its confirmation page');
assert.match(deleteAccountBody, /href="\/privacy\/choices/, 'account deletion page lacks the privacy choices link');
const supabaseUrl = configValue('SUPABASE_URL');
const expectedAnonKey = configValue('SUPABASE_ANON_KEY');
const expectedAuthStorageKey = resolvedAuthStorageKey(
  supabaseUrl,
  configValue('SUPABASE_AUTH_STORAGE_KEY'),
);
const parsedSupabaseUrl = new URL(supabaseUrl);
assert.equal(parsedSupabaseUrl.protocol, 'https:', 'project.conf SUPABASE_URL must use HTTPS');
assert.equal(parsedSupabaseUrl.origin + '/', parsedSupabaseUrl.href.replace(/\/?$/, '/'),
  'project.conf SUPABASE_URL must be an origin without a path, query, or fragment');
const expectedProjectRef = parsedSupabaseUrl.hostname.match(/^([a-z0-9]+)\.supabase\.co$/)?.[1];
const activationTenantId = configValue('BACKEND_ACTIVATION_TENANT_ID');
const activationPhase = configValue('BACKEND_ACTIVATION_PHASE');
const activationCanonicalUrl = configValue('BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL');
const activationCanonicalKey = configValue('BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY');
const activationCanonicalOrganizationValue = configValue(
  'BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID',
);
const activationValues = [
  activationTenantId,
  activationPhase,
  activationCanonicalUrl,
  activationCanonicalKey,
  activationCanonicalOrganizationValue,
];
const activationEnabled = activationValues.some(Boolean);
let expectedCanonicalProfileSha256 = '';
assert.equal(
  activationValues.every(Boolean),
  activationEnabled,
  'backend activation configuration must be complete or entirely disabled',
);
assert.ok(expectedAnonKey, 'project.conf is missing SUPABASE_ANON_KEY');
const expectedDeleteAccountOrigin = activationPhase === 'canonical'
  ? activationCanonicalUrl
  : supabaseUrl;
const expectedDeleteAccountKey = activationPhase === 'canonical'
  ? activationCanonicalKey
  : expectedAnonKey;
assert.ok(
  deleteAccountBody.includes(`${expectedDeleteAccountOrigin}/functions/v1/confirm-account-deletion`),
  'account deletion page targets the wrong backend',
);
assert.ok(
  deleteAccountBody.includes(expectedDeleteAccountKey),
  'account deletion page uses the wrong anon key',
);
const anonPayload = JSON.parse(
  Buffer.from(expectedAnonKey.split('.')[1] || '', 'base64url').toString('utf8'),
);
assert.equal(anonPayload.role, 'anon', 'project.conf Supabase JWT must use the anon role');
assert.equal(anonPayload.iss, 'supabase', 'project.conf Supabase JWT must be issued by Supabase');
if (expectedProjectRef) {
  assert.equal(
    anonPayload.ref,
    expectedProjectRef,
    'project.conf anon JWT belongs to a different Supabase project',
  );
}
assert.ok(
  main.includes(Buffer.from(expectedAnonKey)),
  'compiled Flutter bundle does not contain the configured Supabase anon key',
);
if (activationEnabled) {
  assert.match(activationTenantId, /^[a-z0-9][a-z0-9-]*$/,
    'backend activation tenant must be a lowercase slug');
  assert.ok(['legacy', 'canonical'].includes(activationPhase),
    'backend activation phase must be legacy or canonical');
  assert.equal(parseSupabaseOrigin(activationCanonicalUrl), 'https://api.festapp.net',
    'canonical activation origin must be https://api.festapp.net');
  assert.notEqual(activationCanonicalUrl, supabaseUrl,
    'legacy and canonical activation origins must be distinct');
  const activationCanonicalOrganizationId = Number(activationCanonicalOrganizationValue);
  assert.ok(Number.isSafeInteger(activationCanonicalOrganizationId) &&
    activationCanonicalOrganizationId > 0,
  'canonical activation organization ID must be a positive integer');
  expectedCanonicalProfileSha256 = canonicalBackendProfileSha256({
    tenantId: activationTenantId,
    canonicalOrigin: parseSupabaseOrigin(activationCanonicalUrl),
    canonicalAnonKey: activationCanonicalKey,
    canonicalOrganizationId: activationCanonicalOrganizationId,
  });
  const canonicalAnonPayload = JSON.parse(
    Buffer.from(activationCanonicalKey.split('.')[1] || '', 'base64url').toString('utf8'),
  );
  assert.equal(canonicalAnonPayload.role, 'anon',
    'canonical activation JWT must use the anon role');
  assert.equal(canonicalAnonPayload.iss, 'supabase',
    'canonical activation JWT must be issued by Supabase');
  assert.ok(main.includes(Buffer.from(activationCanonicalUrl)),
    'compiled Flutter bundle lacks the canonical activation origin');
  assert.ok(main.includes(Buffer.from(activationCanonicalKey)),
    'compiled Flutter bundle lacks the canonical activation key');
  assert.equal(
    await readFile(path.join(buildDir, 'backend-activation.json'), 'utf8'),
    backendActivationDocument(activationTenantId, activationPhase),
    'built activation manifest differs from project.conf',
  );
  assert.ok(main.includes(Buffer.from(canonicalBackendActivationSha256(activationTenantId))),
    'compiled Flutter bundle lacks the pinned activation digest');
  assert.ok(main.includes(Buffer.from(expectedCanonicalProfileSha256)),
    'compiled Flutter bundle lacks the canonical profile fingerprint');
}
const loadingLogo = configValue('WEB_LOADING_LOGO_ASSET');
assert.ok(loadingLogo, 'project.conf is missing WEB_LOADING_LOGO_ASSET');
assert.match(
  flutterHtml,
  new RegExp(`<img class="initial-logo" src="${loadingLogo.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"`),
  'Flutter loader does not use the configured tenant asset',
);
assert.doesNotMatch(flutterHtml, /CSM Ostrava 2026/, 'Flutter loader contains foreign tenant branding');

const flutterConfigPath = path.resolve(path.dirname(configPath), '..', 'lib/app_config.dart');
const flutterConfig = await readFile(flutterConfigPath, 'utf8');
if (activationEnabled) {
  assert.match(
    flutterConfig,
    new RegExp(`static const int backendActivationCanonicalOrganizationId = ${activationCanonicalOrganizationValue};`),
    'generated Flutter canonical organization differs from project.conf',
  );
}
for (const [key, dartName] of [
  ['PRIVACY_URL', 'privacyUrl'],
  ['PRIVACY_CHOICES_URL', 'privacyChoicesUrl'],
  ['TERMS_URL', 'termsUrl'],
  ['SUPPORT_URL', 'supportUrl'],
  ['DELETE_ACCOUNT_URL', 'deleteAccountUrl'],
]) {
  const expected = configValue(key).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  assert.match(
    flutterConfig,
    new RegExp(`static const String ${dartName}\\s*=\\s*"${expected}";`),
    `generated Flutter ${dartName} differs from project.conf`,
  );
}
const expectedIsAllUnit = configValue('WEB_IS_ALL_UNIT');
assert.match(
  flutterConfig,
  new RegExp(`static const bool isAllUnit = ${expectedIsAllUnit};`),
  'generated Flutter isAllUnit differs from project.conf',
);
assert.match(
  worker,
  new RegExp(`const BUILD_VERSION = "${escapedVersion}"`),
  'service worker has a different build version',
);
assert.match(worker, /FESTAPP_QUERY_BUILD_VERSION/);

const siteManifest = JSON.parse(siteManifestText);
const configuredStartPath = new URL(siteManifest.start_url, 'https://festapp.test')
  .pathname.replace(/\/$/, '');
const expectedForcedPath = configuredStartPath || null;
const parseForcedPath = (source, owner) => {
  const match = source.match(/const FORCED_OCCASION_PATH = (null|"[^"]+");/);
  assert.ok(match, `${owner} does not expose its forced-occasion routing contract`);
  return JSON.parse(match[1]);
};
assert.equal(
  parseForcedPath(worker, 'service worker'),
  expectedForcedPath,
  'service worker routing differs from site.webmanifest start_url',
);
if (target === 'cloudflare') {
  const edgeWorker = await readFile(path.join(buildDir, '_worker.js'), 'utf8');
  assert.equal(
    parseForcedPath(edgeWorker, 'edge worker'),
    expectedForcedPath,
    'edge worker routing differs from site.webmanifest start_url',
  );
}

const authStorageKey = authBridge.match(
  /const SUPABASE_KEY = '([^']+)'/,
)?.[1];
assert.equal(
  authStorageKey,
  expectedAuthStorageKey,
  'auth bridge does not use the configured Supabase storage key',
);
const webAssetDir = path.join(buildDir, 'web-assets');
const webAssetFiles = (await readdir(webAssetDir)).filter((name) => name.endsWith('.js'));
const webAssetSources = await Promise.all(
  webAssetFiles.map((name) => readFile(path.join(webAssetDir, name), 'utf8')),
);
const webAssetBytes = Buffer.from(webAssetSources.join('\n'));
assert.ok(
  webAssetBytes.includes(Buffer.from(supabaseUrl)),
  'vanilla web bundle does not contain the configured Supabase origin',
);
assert.ok(
  webAssetBytes.includes(Buffer.from(expectedAnonKey)),
  'vanilla web bundle does not contain the configured Supabase anon key',
);
if (activationEnabled) {
  assert.ok(webAssetBytes.includes(Buffer.from(activationCanonicalUrl)),
    'vanilla web bundle lacks the canonical activation origin');
  assert.ok(webAssetBytes.includes(Buffer.from(activationCanonicalKey)),
    'vanilla web bundle lacks the canonical activation key');
  assert.ok(webAssetBytes.includes(Buffer.from(expectedCanonicalProfileSha256)),
    'vanilla web bundle lacks the canonical profile fingerprint');
}
const bundledCloudOrigins = new Set(
  webAssetSources.flatMap((source) =>
    [...source.matchAll(/https:\/\/[a-z0-9]+\.supabase\.co/g)].map((match) => match[0]),
  ),
);
assert.deepEqual(
  [...bundledCloudOrigins],
  [
    ...(expectedProjectRef ? [supabaseUrl] : []),
    ...(activationCanonicalUrl?.match(/^https:\/\/[a-z0-9]+\.supabase\.co$/)
      ? [activationCanonicalUrl] : []),
  ],
  'vanilla web bundle contains a stale Supabase Cloud origin',
);
const bundledAuthKeys = new Set(
  webAssetSources.flatMap((source) =>
    [...source.matchAll(/sb-[a-z0-9-]+-auth-token/g)].map((match) => match[0]),
  ),
);
assert.deepEqual(
  [...bundledAuthKeys],
  [authStorageKey],
  'web client and auth bridge disagree on the Supabase session storage key',
);

console.log(`verify_web_build: ok (${expectedVersion})`);
