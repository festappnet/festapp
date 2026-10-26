import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';

import {
  parseProjectConfig,
  releaseLaneContractErrors,
} from '../release/release_lane_preflight.mjs';
import { storeManifestShapeErrors } from '../release/store_manifest_contract.mjs';

const repoRoot = '/public/festapp';
const config = parseProjectConfig([
  'BACKEND_ACTIVATION_TENANT_ID=hvezdamorska',
  'IOS_BUNDLE_ID=festapp.hvezdamorska',
  'ANDROID_APPLICATION_ID=fstapp.hvezdamorska',
].join('\n'));
const manifest = {
  schemaVersion: 2,
  bundleId: 'festapp.hvezdamorska',
  androidPackage: 'fstapp.hvezdamorska',
  releaseBranch: 'prod/hvezdamorska',
  backend: {
    releaseIntent: 'canonical-cutover',
    activation: { tenantId: 'hvezdamorska' },
  },
};

test('one external schema-2 manifest may own both web and mobile release lanes', () => {
  for (const mode of ['web', 'mobile']) {
    assert.deepEqual(releaseLaneContractErrors({
      manifest,
      config,
      manifestPath: '/private/festappseed/release/store-listings/hvezdamorska/config.json',
      mode,
      repoRoot,
    }), []);
  }
});

test('mobile lane fails closed on wrong identities, branch and repository-local manifest', () => {
  const errors = releaseLaneContractErrors({
    manifest: {
      ...manifest,
      schemaVersion: 1,
      bundleId: 'invented.bundle',
      androidPackage: '',
      releaseBranch: 'main',
      backend: { releaseIntent: 'backend-transition', activation: { tenantId: 'festapp' } },
    },
    config,
    manifestPath: path.join(repoRoot, 'release.json'),
    mode: 'mobile',
    repoRoot,
  });
  assert.ok(errors.some((error) => error.includes('schemaVersion 2')));
  assert.ok(errors.some((error) => error.includes('activation tenant')));
  assert.ok(errors.some((error) => error.includes('canonical-cutover')));
  assert.ok(errors.some((error) => error.includes('outside the public Festapp repository')));
  assert.ok(errors.some((error) => error.includes('bundleId')));
  assert.ok(errors.some((error) => error.includes('androidPackage')));
  assert.ok(errors.some((error) => error.includes('releaseBranch')));
});

test('store manifest fails closed before deep validation when structural sections are absent', () => {
  assert.deepEqual(storeManifestShapeErrors({ schemaVersion: 2 }), [
    'app-store manifest is missing object target',
    'app-store manifest is missing object apple',
    'app-store manifest is missing object urls',
    'app-store manifest is missing object screenshots',
  ]);
});

test('store manifest rejects empty or malformed structural sections', () => {
  assert.deepEqual(storeManifestShapeErrors({
    target: {},
    apple: {},
    urls: { marketing: 'http://invalid', privacy: '', privacyChoices: null, support: '/support' },
    screenshots: {},
  }), [
    'app-store manifest target.name is missing',
    'app-store manifest target.locale is missing',
    'app-store manifest apple.storeName is missing',
    'app-store manifest urls.marketing must be an absolute HTTPS URL',
    'app-store manifest urls.privacy must be an absolute HTTPS URL',
    'app-store manifest urls.privacyChoices must be an absolute HTTPS URL',
    'app-store manifest urls.support must be an absolute HTTPS URL',
    'app-store manifest screenshots must define at least one device set',
  ]);
});
