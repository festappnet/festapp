#!/usr/bin/env node

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  parseSupabaseOrigin,
  resolvedAuthStorageKey,
} from '../lib/supabase_client_config.mjs';
import {
  backendActivationDocument,
  canonicalBackendActivationSha256,
  canonicalBackendProfileSha256,
} from '../lib/backend_activation_manifest.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const configPath = path.join(root, 'automation/project.conf');
const source = fs.readFileSync(configPath, 'utf8');
const value = (key) => source.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1]
  .trim()
  .replace(/^(['"])(.*)\1$/, '$2') ?? '';
const escapeRegExp = (input) => input.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const supabaseOrigin = parseSupabaseOrigin(value('SUPABASE_URL'));
const anonKey = value('SUPABASE_ANON_KEY');
const configuredAuthStorageKey = value('SUPABASE_AUTH_STORAGE_KEY');
const authStorageKey = resolvedAuthStorageKey(supabaseOrigin, configuredAuthStorageKey);
const installationGeneration = value('PUSH_APP_GENERATION');
const activationTenantId = value('BACKEND_ACTIVATION_TENANT_ID');
const activationPhase = value('BACKEND_ACTIVATION_PHASE');
const activationCanonicalOriginValue = value('BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL');
const activationCanonicalAnonKey = value('BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY');
const activationCanonicalOrganizationValue = value(
  'BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID',
);
const activationEnabled = Boolean(
  activationTenantId || activationPhase || activationCanonicalOriginValue ||
  activationCanonicalAnonKey || activationCanonicalOrganizationValue
);
const organizationId = Number(value('ORGANIZATION_ID'));
assert.ok(Number.isSafeInteger(organizationId) && organizationId > 0,
  'ORGANIZATION_ID must be a positive integer');
const webOrigin = parseSupabaseOrigin(value('WEB_LINK'));
const authRedirectUrls = [`${webOrigin}/reset-password`, `${webOrigin}/resetPassword`];
const anonSha256 = crypto.createHash('sha256').update(anonKey).digest('hex');
const requireCanonicalCutover = process.argv.includes('--require-canonical-cutover');
const payload = JSON.parse(Buffer.from(anonKey.split('.')[1] || '', 'base64url').toString('utf8'));
assert.equal(payload.role, 'anon', 'SUPABASE_ANON_KEY must use the anon role');
assert.equal(payload.iss, 'supabase', 'SUPABASE_ANON_KEY must be issued by Supabase');

const hostname = new URL(supabaseOrigin).hostname;
const cloudRef = hostname.match(/^([a-z0-9]+)\.supabase\.co$/)?.[1];
const backendMode = cloudRef ? 'supabase-cloud' : 'self-hosted';
if (cloudRef) {
  assert.equal(payload.ref, cloudRef, 'SUPABASE_ANON_KEY belongs to a different cloud project');
} else {
  assert.ok(configuredAuthStorageKey, 'self-hosted release requires explicit SUPABASE_AUTH_STORAGE_KEY continuity');
  assert.ok(installationGeneration, 'self-hosted release requires a non-empty PUSH_APP_GENERATION');
}

let activation = null;
if (activationEnabled) {
  assert.ok(activationTenantId && activationPhase && activationCanonicalOriginValue &&
    activationCanonicalAnonKey && activationCanonicalOrganizationValue,
  'backend activation configuration must be complete');
  assert.match(activationTenantId, /^[a-z0-9][a-z0-9-]*$/,
    'backend activation tenant ID must be a lowercase slug');
  assert.ok(['legacy', 'canonical'].includes(activationPhase),
    'backend activation phase must be legacy or canonical');
  assert.ok(configuredAuthStorageKey,
    'backend activation requires an explicit stable auth storage namespace');
  assert.ok(installationGeneration,
    'backend activation requires a non-empty PUSH_APP_GENERATION');
  const canonicalOrganizationId = Number(activationCanonicalOrganizationValue);
  assert.ok(Number.isSafeInteger(canonicalOrganizationId) && canonicalOrganizationId > 0,
    'canonical activation organization ID must be a positive integer');
  const canonicalOrigin = parseSupabaseOrigin(activationCanonicalOriginValue);
  assert.equal(canonicalOrigin, 'https://api.festapp.net',
    'backend activation canonical origin must be https://api.festapp.net');
  assert.notEqual(canonicalOrigin, supabaseOrigin,
    'backend activation canonical origin must differ from the legacy origin');
  const canonicalPayload = JSON.parse(Buffer.from(
    activationCanonicalAnonKey.split('.')[1] || '', 'base64url',
  ).toString('utf8'));
  assert.equal(canonicalPayload.role, 'anon', 'canonical activation key must use the anon role');
  assert.equal(canonicalPayload.iss, 'supabase', 'canonical activation key must be issued by Supabase');
  const canonicalSha256 = canonicalBackendActivationSha256(activationTenantId);
  const canonicalProfileSha256 = canonicalBackendProfileSha256({
    tenantId: activationTenantId,
    canonicalOrigin,
    canonicalAnonKey: activationCanonicalAnonKey,
    canonicalOrganizationId,
  });
  const manifestUrl = `${webOrigin}/backend-activation.json`;
  const expectedDocument = backendActivationDocument(activationTenantId, activationPhase);
  for (const relative of ['web/backend-activation.json', 'web_client/public/backend-activation.json']) {
    assert.equal(fs.readFileSync(path.join(root, relative), 'utf8'), expectedDocument,
      `${relative} differs from the configured activation phase`);
  }
  activation = {
    tenantId: activationTenantId,
    phase: activationPhase,
    strategy: 'pinned-one-way-manifest',
    manifestUrl,
    canonicalManifestSha256: canonicalSha256,
    canonicalSupabaseOrigin: canonicalOrigin,
    canonicalAnonKeySha256: crypto.createHash('sha256')
      .update(activationCanonicalAnonKey).digest('hex'),
    canonicalOrganizationId,
    canonicalProfileSha256,
    authStorageKey,
    finalRefreshTokenDeltaRequired: true,
  };
}

const manifestValue = process.env.FESTAPP_RELEASE_MANIFEST?.trim();
if (!cloudRef || manifestValue || requireCanonicalCutover || activationEnabled) {
  assert.ok(manifestValue, 'release backend validation requires FESTAPP_RELEASE_MANIFEST');
  const manifest = JSON.parse(fs.readFileSync(path.resolve(manifestValue), 'utf8'));
  const backend = manifest.backend;
  assert.ok(backend, 'release manifest is missing its backend contract');
  assert.equal(backend.mode, backendMode, 'release manifest backend mode mismatch');
  assert.equal(backend.supabaseOrigin, supabaseOrigin, 'release manifest Supabase origin mismatch');
  assert.equal(backend.anonKeySha256, anonSha256, 'release manifest anon-key digest mismatch');
  assert.equal(backend.installationGeneration, installationGeneration,
    'release manifest installation generation mismatch');
  assert.equal(backend.authStorageKey, authStorageKey,
    'release manifest auth storage namespace mismatch');
  assert.equal(backend.organizationId, organizationId,
    'release manifest organization ID mismatch');
  assert.equal(backend.authSiteUrl, webOrigin, 'release manifest Auth site URL mismatch');
  assert.deepEqual(
    [...(backend.authRedirectUrls ?? [])].sort(),
    [...authRedirectUrls].sort(),
    'release manifest Auth redirect allowlist mismatch',
  );
  if (activationEnabled) {
    assert.deepEqual(backend.activation, activation,
      'release manifest backend activation contract mismatch');
  }
  assert.deepEqual(
    backend.allowedWebOrigins,
    [webOrigin],
    'release manifest Edge Function CORS allowlist mismatch',
  );
  if (backend.mode === 'self-hosted' || activationEnabled) {
    const transition = backend.sessionTransition;
    assert.ok(transition, 'self-hosted release manifest is missing its session transition contract');
    assert.equal(transition.strategy, 'refresh-or-reauth',
      'self-hosted session transition must refresh or require normal reauthentication');
    assert.equal(transition.legacyAccessTokenPolicy, 'reject-after-cutover',
      'legacy access tokens must not remain an alternate trust path');
    assert.equal(transition.terminalRefreshPolicy, 'local-sign-out',
      'terminal refresh failures must clear the local session');
    assert.equal(transition.sourceAReauthenticationAllowed, true,
      'the merged source-a cohort must explicitly allow normal reauthentication');
    assert.match(transition.refreshCanaryEvidenceSha256 ?? '', /^[0-9a-f]{64}$/,
      'self-hosted release requires refresh-canary evidence');
  }
  if (requireCanonicalCutover) {
    assert.equal(backend.releaseIntent, 'canonical-cutover',
      'canonical cutover build requires releaseIntent=canonical-cutover');
    assert.ok(backend.mode === 'self-hosted' || activationEnabled,
      'canonical cutover build requires a self-hosted backend or pinned activation transition');
  }
}

const flutterConfig = fs.readFileSync(path.join(root, 'lib/app_config.dart'), 'utf8');
const webConfig = fs.readFileSync(path.join(root, 'web_client/src/app_config.js'), 'utf8');
for (const [text, expression, message] of [
  [flutterConfig, `static const String supabaseUrl = '${escapeRegExp(supabaseOrigin)}';`,
    'generated Flutter Supabase origin is stale'],
  [flutterConfig, `static const String pushAppGeneration = '${escapeRegExp(installationGeneration)}';`,
    'generated Flutter installation generation is stale'],
  [flutterConfig, `static const String supabaseAuthStorageKey = '${escapeRegExp(authStorageKey)}';`,
    'generated Flutter auth storage namespace is stale'],
  [webConfig, `static supabaseUrl = '${escapeRegExp(supabaseOrigin)}';`,
    'generated web Supabase origin is stale'],
  [webConfig, `auth: '${escapeRegExp(authStorageKey)}'`,
    'generated web auth storage namespace is stale'],
]) {
  assert.match(text, new RegExp(expression), message);
}
if (activationEnabled) {
  for (const [text, expected, message] of [
    [flutterConfig, activation.tenantId, 'generated Flutter activation tenant is stale'],
    [flutterConfig, activation.manifestUrl, 'generated Flutter activation URL is stale'],
    [flutterConfig, activation.canonicalManifestSha256,
      'generated Flutter activation digest is stale'],
    [flutterConfig, activation.canonicalSupabaseOrigin,
      'generated Flutter canonical origin is stale'],
    [flutterConfig, activationCanonicalAnonKey, 'generated Flutter canonical key is stale'],
    [flutterConfig, `backendActivationCanonicalOrganizationId = ${activation.canonicalOrganizationId};`,
      'generated Flutter canonical organization is stale'],
    [flutterConfig, activation.canonicalProfileSha256,
      'generated Flutter canonical profile fingerprint is stale'],
    [webConfig, activation.tenantId, 'generated web activation tenant is stale'],
    [webConfig, activation.manifestUrl, 'generated web activation URL is stale'],
    [webConfig, activation.canonicalManifestSha256, 'generated web activation digest is stale'],
    [webConfig, activation.canonicalSupabaseOrigin, 'generated web canonical origin is stale'],
    [webConfig, activationCanonicalAnonKey, 'generated web canonical key is stale'],
    [webConfig, `backendActivationCanonicalOrganizationId = ${activation.canonicalOrganizationId};`,
      'generated web canonical organization is stale'],
    [webConfig, activation.canonicalProfileSha256,
      'generated web canonical profile fingerprint is stale'],
  ]) assert.ok(text.includes(expected), message);
}
assert.ok(flutterConfig.includes(anonKey), 'generated Flutter anon key is stale');
assert.ok(webConfig.includes(anonKey), 'generated web anon key is stale');

console.log(JSON.stringify({
  status: 'pass',
  supabase_origin: supabaseOrigin,
  anon_key_sha256: anonSha256,
  auth_storage_key: authStorageKey,
  installation_generation: installationGeneration || null,
  organization_id: organizationId,
  auth_site_url: webOrigin,
  auth_redirect_urls: authRedirectUrls,
  backend_mode: backendMode,
  session_transition: backendMode === 'self-hosted' || activationEnabled ? 'refresh-or-reauth' : null,
  canonical_cutover: requireCanonicalCutover,
  backend_activation: activation,
}));
