#!/usr/bin/env node

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import {
  derivedAuthStorageKey,
  parseSupabaseOrigin,
  resolvedAuthStorageKey,
} from '../lib/supabase_client_config.mjs';
import {
  backendActivationDocument,
  canonicalBackendActivationSha256,
  canonicalBackendProfileSha256,
} from '../lib/backend_activation_manifest.mjs';

const root = path.resolve(import.meta.dirname, '../..');

test('live database test entrypoints default only to the canonical self-hosted API', () => {
  const entrypoints = [
    'tests/integration/bank_import_real.js',
    'web_client/tests/core/rpc_security.test.js',
  ].map((relative) => fs.readFileSync(path.join(root, relative), 'utf8'));

  for (const source of entrypoints) {
    assert.match(source, /https:\/\/api\.festapp\.net/);
    assert.doesNotMatch(source, /https:\/\/[a-z0-9-]+\.supabase\.co/);
    assert.match(source, /Refusing non-canonical Supabase test target/);
  }
});

test('Supabase client origin accepts cloud and self-hosted HTTPS origins only', () => {
  assert.equal(parseSupabaseOrigin('https://api.festapp.net/'), 'https://api.festapp.net');
  for (const invalid of [
    'http://api.festapp.net',
    'https://user:pass@api.festapp.net',
    'https://api.festapp.net/rest/v1',
    'https://api.festapp.net?tenant=a',
    'https://api.festapp.net#fragment',
  ]) assert.throws(() => parseSupabaseOrigin(invalid));
});

test('auth storage namespace is deterministic and may be explicitly kept across cutover', () => {
  assert.equal(
    derivedAuthStorageKey('https://kjdpmixlnhntmxjedpxh.supabase.co'),
    'sb-kjdpmixlnhntmxjedpxh-auth-token',
  );
  assert.equal(
    derivedAuthStorageKey('https://api.example.com'),
    'sb-selfhost-d0c43d3885064d9a-auth-token',
  );
  assert.equal(
    resolvedAuthStorageKey('https://api.example.com', 'sb-existing-cloud-auth-token'),
    'sb-existing-cloud-auth-token',
  );
  assert.throws(() => resolvedAuthStorageKey('https://api.example.com', '../unsafe'));
});

test('web, Android and iOS release builders share the client cutover preflight', () => {
  const android = fs.readFileSync(path.join(root, 'automation/release/android_release.ps1'), 'utf8');
  const ios = fs.readFileSync(path.join(root, 'automation/release/ios_build_and_upload.sh'), 'utf8');
  const web = fs.readFileSync(path.join(root, 'automation/build_web_bundle.sh'), 'utf8');
  for (const source of [android, ios, web]) {
    assert.match(source, /client_cutover_preflight\.mjs/);
    assert.match(source, /FESTAPP_CANONICAL_CUTOVER_RELEASE/);
  }
  assert.doesNotMatch(web, /cutover_preflight_args/,
    'web release preflight must remain compatible with macOS Bash 3.2 and set -u');
  assert.doesNotMatch(ios, /cutover_preflight_args/,
    'iOS release preflight must remain compatible with macOS Bash 3.2 and set -u');
});

const jwt = (payload) => [
  Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url'),
  Buffer.from(JSON.stringify(payload)).toString('base64url'),
  'test-signature',
].join('.');

function makePreflightFixture({ origin, key, generation, authStorageKey, backend,
  activation = null }) {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-cutover-preflight-'));
  for (const relative of ['automation/release', 'automation/lib', 'lib', 'web_client/src']) {
    fs.mkdirSync(path.join(fixture, relative), { recursive: true });
  }
  fs.copyFileSync(
    path.join(root, 'automation/release/client_cutover_preflight.mjs'),
    path.join(fixture, 'automation/release/client_cutover_preflight.mjs'),
  );
  fs.copyFileSync(
    path.join(root, 'automation/lib/supabase_client_config.mjs'),
    path.join(fixture, 'automation/lib/supabase_client_config.mjs'),
  );
  fs.copyFileSync(
    path.join(root, 'automation/lib/backend_activation_manifest.mjs'),
    path.join(fixture, 'automation/lib/backend_activation_manifest.mjs'),
  );
  if (activation) {
    fs.mkdirSync(path.join(fixture, 'web'), { recursive: true });
    fs.mkdirSync(path.join(fixture, 'web_client/public'), { recursive: true });
    const document = backendActivationDocument(activation.tenantId, activation.phase);
    fs.writeFileSync(path.join(fixture, 'web/backend-activation.json'), document);
    fs.writeFileSync(path.join(fixture, 'web_client/public/backend-activation.json'), document);
  }
  const activationProfileSha256 = activation ? canonicalBackendProfileSha256({
    tenantId: activation.tenantId,
    canonicalOrigin: activation.canonicalOrigin,
    canonicalAnonKey: activation.canonicalKey,
    canonicalOrganizationId: activation.canonicalOrganizationId,
  }) : '';
  fs.writeFileSync(path.join(fixture, 'automation/project.conf'), [
    `SUPABASE_URL=${origin}`,
    `SUPABASE_ANON_KEY=${key}`,
    `SUPABASE_AUTH_STORAGE_KEY=${authStorageKey}`,
    `BACKEND_ACTIVATION_TENANT_ID=${activation?.tenantId ?? ''}`,
    `BACKEND_ACTIVATION_PHASE=${activation?.phase ?? ''}`,
    `BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL=${activation?.canonicalOrigin ?? ''}`,
    `BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY=${activation?.canonicalKey ?? ''}`,
    `BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=${activation?.canonicalOrganizationId ?? ''}`,
    `PUSH_APP_GENERATION=${generation}`,
    'ORGANIZATION_ID=12',
    'WEB_LINK=https://app.example.test',
  ].join('\n'));
  fs.writeFileSync(path.join(fixture, 'lib/app_config.dart'), [
    `static const String supabaseUrl = '${origin}';`,
    `static const String anonKey = '${key}';`,
    `static const String pushAppGeneration = '${generation}';`,
    `static const String supabaseAuthStorageKey = '${authStorageKey}';`,
    `static const String backendActivationTenantId = '${activation?.tenantId ?? ''}';`,
    `static const String backendActivationManifestUrl = '${activation ? 'https://app.example.test/backend-activation.json' : ''}';`,
    `static const String backendActivationCanonicalManifestSha256 = '${activation ? canonicalBackendActivationSha256(activation.tenantId) : ''}';`,
    `static const String backendActivationCanonicalSupabaseUrl = '${activation?.canonicalOrigin ?? ''}';`,
    `static const String backendActivationCanonicalAnonKey = '${activation?.canonicalKey ?? ''}';`,
    `static const int backendActivationCanonicalOrganizationId = ${activation?.canonicalOrganizationId ?? 0};`,
    `static const String backendActivationCanonicalProfileSha256 = '${activationProfileSha256}';`,
  ].join('\n'));
  fs.writeFileSync(path.join(fixture, 'web_client/src/app_config.js'), [
    `static supabaseUrl = '${origin}';`,
    `static anonKey = '${key}';`,
    `static backendActivationTenantId = '${activation?.tenantId ?? ''}';`,
    `static backendActivationManifestUrl = '${activation ? 'https://app.example.test/backend-activation.json' : ''}';`,
    `static backendActivationCanonicalManifestSha256 = '${activation ? canonicalBackendActivationSha256(activation.tenantId) : ''}';`,
    `static backendActivationCanonicalSupabaseUrl = '${activation?.canonicalOrigin ?? ''}';`,
    `static backendActivationCanonicalAnonKey = '${activation?.canonicalKey ?? ''}';`,
    `static backendActivationCanonicalOrganizationId = ${activation?.canonicalOrganizationId ?? 0};`,
    `static backendActivationCanonicalProfileSha256 = '${activationProfileSha256}';`,
    `auth: '${authStorageKey}'`,
  ].join('\n'));
  const manifest = path.join(fixture, 'release.json');
  fs.writeFileSync(manifest, JSON.stringify({ backend }));
  return { fixture, manifest };
}

function runPreflight(fixture, manifest, ...args) {
  return spawnSync(process.execPath, [
    path.join(fixture, 'automation/release/client_cutover_preflight.mjs'),
    ...args,
  ], {
    cwd: fixture,
    encoding: 'utf8',
    env: { ...process.env, FESTAPP_RELEASE_MANIFEST: manifest ?? '' },
  });
}

test('self-hosted canonical cutover preflight binds manifest, key, generation and generated clients', () => {
  const origin = 'https://api.festapp.net';
  const key = jwt({ iss: 'supabase', role: 'anon' });
  const generation = 'selfhost_cutover_v1';
  const authStorageKey = 'sb-legacy-cloud-auth-token';
  const anonKeySha256 = crypto.createHash('sha256').update(key).digest('hex');
  const { fixture, manifest } = makePreflightFixture({
    origin, key, generation, authStorageKey,
    backend: {
      mode: 'self-hosted',
      releaseIntent: 'canonical-cutover',
      supabaseOrigin: origin,
      anonKeySha256,
      installationGeneration: generation,
      authStorageKey,
      organizationId: 12,
      authSiteUrl: 'https://app.example.test',
      authRedirectUrls: [
        'https://app.example.test/reset-password',
        'https://app.example.test/resetPassword',
      ],
      allowedWebOrigins: ['https://app.example.test'],
      sessionTransition: {
        strategy: 'refresh-or-reauth',
        legacyAccessTokenPolicy: 'reject-after-cutover',
        terminalRefreshPolicy: 'local-sign-out',
        sourceAReauthenticationAllowed: true,
        refreshCanaryEvidenceSha256: 'a'.repeat(64),
      },
    },
  });
  try {
    const passed = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.equal(passed.status, 0, passed.stderr);

    const missingManifest = runPreflight(fixture, null, '--require-canonical-cutover');
    assert.notEqual(missingManifest.status, 0);

    const configPath = path.join(fixture, 'automation/project.conf');
    const validConfig = fs.readFileSync(configPath, 'utf8');
    fs.writeFileSync(configPath, validConfig.replace(
      /^PUSH_APP_GENERATION=.*$/m, 'PUSH_APP_GENERATION=',
    ));
    const missingGeneration = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.notEqual(missingGeneration.status, 0);
    assert.match(missingGeneration.stderr, /non-empty PUSH_APP_GENERATION/);
    fs.writeFileSync(configPath, validConfig.replace(
      /^SUPABASE_AUTH_STORAGE_KEY=.*$/m, 'SUPABASE_AUTH_STORAGE_KEY=',
    ));
    const missingAuthKey = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.notEqual(missingAuthKey.status, 0);
    assert.match(missingAuthKey.stderr, /explicit SUPABASE_AUTH_STORAGE_KEY/);
    fs.writeFileSync(configPath, validConfig);

    const flutterPath = path.join(fixture, 'lib/app_config.dart');
    const validFlutter = fs.readFileSync(flutterPath, 'utf8');
    fs.writeFileSync(flutterPath, validFlutter.replace(origin, 'https://stale.example.test'));
    const staleFlutter = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.notEqual(staleFlutter.status, 0);
    assert.match(staleFlutter.stderr, /generated Flutter Supabase origin is stale/);
    fs.writeFileSync(flutterPath, validFlutter);

    const webPath = path.join(fixture, 'web_client/src/app_config.js');
    const validWeb = fs.readFileSync(webPath, 'utf8');
    fs.writeFileSync(webPath, validWeb.replace(key, 'stale-anon-key'));
    const staleWeb = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.notEqual(staleWeb.status, 0);
    assert.match(staleWeb.stderr, /generated web anon key is stale/);
    fs.writeFileSync(webPath, validWeb);

    const wrongManifest = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    wrongManifest.backend.anonKeySha256 = '0'.repeat(64);
    fs.writeFileSync(manifest, JSON.stringify(wrongManifest));
    const mismatch = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.notEqual(mismatch.status, 0);
    assert.match(mismatch.stderr, /anon-key digest mismatch/);

    wrongManifest.backend.anonKeySha256 = anonKeySha256;
    wrongManifest.backend.organizationId = 9;
    fs.writeFileSync(manifest, JSON.stringify(wrongManifest));
    const wrongOrganization = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.notEqual(wrongOrganization.status, 0);
    assert.match(wrongOrganization.stderr, /organization ID mismatch/);

    wrongManifest.backend.organizationId = 12;
    delete wrongManifest.backend.sessionTransition.refreshCanaryEvidenceSha256;
    fs.writeFileSync(manifest, JSON.stringify(wrongManifest));
    const missingRefreshEvidence = runPreflight(
      fixture,
      manifest,
      '--require-canonical-cutover',
    );
    assert.notEqual(missingRefreshEvidence.status, 0);
    assert.match(missingRefreshEvidence.stderr, /refresh-canary evidence/);
  } finally {
    fs.rmSync(fixture, { recursive: true, force: true });
  }
});

test('transition release binds a pinned one-way activation and stable session namespace', () => {
  const legacyRef = 'legacyslunovratref';
  const origin = `https://${legacyRef}.supabase.co`;
  const key = jwt({ iss: 'supabase', role: 'anon', ref: legacyRef });
  const canonicalKey = jwt({ iss: 'supabase', role: 'anon' });
  const authStorageKey = `sb-${legacyRef}-auth-token`;
  const activation = {
    tenantId: 'festivalslunovrat',
    phase: 'legacy',
    canonicalOrigin: 'https://api.festapp.net',
    canonicalKey,
    canonicalOrganizationId: 19,
  };
  const backend = {
    mode: 'supabase-cloud',
    releaseIntent: 'canonical-cutover',
    supabaseOrigin: origin,
    anonKeySha256: crypto.createHash('sha256').update(key).digest('hex'),
    installationGeneration: 'slunovrat_transition_v1',
    authStorageKey,
    organizationId: 12,
    authSiteUrl: 'https://app.example.test',
    authRedirectUrls: [
      'https://app.example.test/reset-password',
      'https://app.example.test/resetPassword',
    ],
    allowedWebOrigins: ['https://app.example.test'],
    activation: {
      tenantId: activation.tenantId,
      phase: activation.phase,
      strategy: 'pinned-one-way-manifest',
      manifestUrl: 'https://app.example.test/backend-activation.json',
      canonicalManifestSha256: canonicalBackendActivationSha256(activation.tenantId),
      canonicalSupabaseOrigin: activation.canonicalOrigin,
      canonicalAnonKeySha256: crypto.createHash('sha256').update(canonicalKey).digest('hex'),
      canonicalOrganizationId: activation.canonicalOrganizationId,
      canonicalProfileSha256: canonicalBackendProfileSha256({
        tenantId: activation.tenantId,
        canonicalOrigin: activation.canonicalOrigin,
        canonicalAnonKey: activation.canonicalKey,
        canonicalOrganizationId: activation.canonicalOrganizationId,
      }),
      authStorageKey,
      finalRefreshTokenDeltaRequired: true,
    },
    sessionTransition: {
      strategy: 'refresh-or-reauth',
      legacyAccessTokenPolicy: 'reject-after-cutover',
      terminalRefreshPolicy: 'local-sign-out',
      sourceAReauthenticationAllowed: true,
      refreshCanaryEvidenceSha256: 'a'.repeat(64),
    },
  };
  const { fixture, manifest } = makePreflightFixture({
    origin, key, generation: 'slunovrat_transition_v1', authStorageKey,
    backend, activation,
  });
  try {
    const passed = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.equal(passed.status, 0, passed.stderr);

    const configPath = path.join(fixture, 'automation/project.conf');
    fs.writeFileSync(configPath, fs.readFileSync(configPath, 'utf8').replace(
      /^BACKEND_ACTIVATION_PHASE=.*$/m,
      'BACKEND_ACTIVATION_PHASE=canonical',
    ));
    for (const relative of [
      'web/backend-activation.json',
      'web_client/public/backend-activation.json',
    ]) {
      fs.writeFileSync(
        path.join(fixture, relative),
        backendActivationDocument(activation.tenantId, 'canonical'),
      );
    }
    backend.activation.phase = 'canonical';
    fs.writeFileSync(manifest, JSON.stringify({ backend }));
    const canonicalPhase = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.equal(canonicalPhase.status, 0, canonicalPhase.stderr);

    fs.writeFileSync(
      path.join(fixture, 'web/backend-activation.json'),
      backendActivationDocument(activation.tenantId, 'legacy'),
    );
    const mismatchedPhase = runPreflight(fixture, manifest);
    assert.notEqual(mismatchedPhase.status, 0);
    assert.match(mismatchedPhase.stderr, /differs from the configured activation phase/);
  } finally {
    fs.rmSync(fixture, { recursive: true, force: true });
  }
});

test('canonical cutover mode refuses an otherwise valid Supabase Cloud manifest', () => {
  const ref = 'abcdefghijklmnopqrst';
  const origin = `https://${ref}.supabase.co`;
  const key = jwt({ iss: 'supabase', role: 'anon', ref });
  const authStorageKey = `sb-${ref}-auth-token`;
  const anonKeySha256 = crypto.createHash('sha256').update(key).digest('hex');
  const { fixture, manifest } = makePreflightFixture({
    origin, key, generation: '', authStorageKey,
    backend: {
      mode: 'supabase-cloud',
      releaseIntent: 'canonical-cutover',
      supabaseOrigin: origin,
      anonKeySha256,
      installationGeneration: '',
      authStorageKey,
      organizationId: 12,
      authSiteUrl: 'https://app.example.test',
      authRedirectUrls: [
        'https://app.example.test/reset-password',
        'https://app.example.test/resetPassword',
      ],
      allowedWebOrigins: ['https://app.example.test'],
    },
  });
  try {
    const result = runPreflight(fixture, manifest, '--require-canonical-cutover');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /requires a self-hosted backend or pinned activation transition/);
  } finally {
    fs.rmSync(fixture, { recursive: true, force: true });
  }
});
