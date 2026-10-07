import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test, { beforeEach, afterEach, mock } from 'node:test';

import { AppConfig } from '../../src/app_config.js';
import { BackendActivationService } from '../../src/services/backend_activation_service.js';
import { SupabaseService } from '../../src/services/supabase_service.js';
import { APP_VERSION } from '../../src/version.js';

const resolvedBackend = {
  supabaseUrl: 'https://canonical.fixture.invalid',
  anonKey: 'fixture-anon', organizationId: 12, isCanonical: true,
};
const originalOrganization = AppConfig.organization;
beforeEach(() => mock.method(BackendActivationService.prototype, 'resolve',
  async () => resolvedBackend));
afterEach(() => { mock.restoreAll(); AppConfig.organization = originalOrganization; });

test('unsupported-app header data loads only after Supabase initialization', async () => {
  const mainSource = await readFile(new URL('../../src/main.js', import.meta.url), 'utf8');
  const startupSource = await readFile(
    new URL('../../src/startup/initialize_core_services.js', import.meta.url),
    'utf8',
  );
  assert.match(mainSource, /await initializeCoreServices\(\{[\s\S]*supabaseService: SupabaseService,[\s\S]*rightsService: RightsService,[\s\S]*isAppSupported: AppConfig\.isAppSupported,/,
    'main must provide the configured Supabase and rights services to canonical startup');
  const initializeAt = startupSource.indexOf('await supabaseService.initialize()');
  const rightsAt = startupSource.indexOf(
    'if (!isAppSupported) await rightsService.updateAppData()',
  );
  assert.ok(initializeAt >= 0, 'canonical startup must initialize Supabase');
  assert.ok(rightsAt > initializeAt, 'rights fetch must happen after Supabase initialization');
});

test('Supabase JS persists sessions under the key shared with the auth bridge', () => {
  assert.equal(SupabaseService.tokenKey, AppConfig.Keys.auth);
  assert.equal(SupabaseService.clientOptions.auth.storageKey, AppConfig.Keys.auth);
});

test('all JS backend requests identify their release and build for cutover observation', () => {
  assert.deepEqual(SupabaseService.clientOptions.global.headers, {
    'X-Client-Info': `festapp/${APP_VERSION}/js`,
  });
});

test('backend-origin change refreshes the preserved session before startup', async () => {
  const values = new Map([[SupabaseService.originMarkerKey, 'https://old.example.test']]);
  globalThis.localStorage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
  };
  let refreshInput;
  SupabaseService._client = {
    auth: {
      getSession: async () => ({
        data: { session: { refresh_token: 'preserved-refresh-token' } },
        error: null,
      }),
      refreshSession: async (input) => {
        refreshInput = input;
        return { data: { session: { refresh_token: 'rotated-refresh-token' } }, error: null };
      },
    },
  };
  SupabaseService._initialization = null;

  await SupabaseService.initialize();

  assert.deepEqual(refreshInput, { refresh_token: 'preserved-refresh-token' });
  assert.equal(values.get(SupabaseService.originMarkerKey), resolvedBackend.supabaseUrl);
});

test('invalid historical refresh token clears only the local session and continues anonymously', async () => {
  const values = new Map([
    [SupabaseService.originMarkerKey, 'https://old.example.test'],
    [SupabaseService.tokenKey, 'stored-session'],
  ]);
  globalThis.localStorage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key),
  };
  let signOutOptions;
  SupabaseService._client = {
    auth: {
      getSession: async () => ({
        data: { session: { refresh_token: 'expired-refresh-token' } },
        error: null,
      }),
      refreshSession: async () => ({
        data: { session: null },
        error: { code: 'refresh_token_not_found', message: 'invalid refresh token' },
      }),
      signOut: async (options) => { signOutOptions = options; return { error: null }; },
    },
  };
  SupabaseService._initialization = null;

  await SupabaseService.initialize();

  assert.deepEqual(signOutOptions, { scope: 'local' });
  assert.equal(values.has(SupabaseService.tokenKey), false);
  assert.equal(values.get(SupabaseService.originMarkerKey), resolvedBackend.supabaseUrl);
});

test('failed cutover refresh does not advance the backend-origin marker', async () => {
  const values = new Map([[SupabaseService.originMarkerKey, 'https://old.example.test']]);
  globalThis.localStorage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
  };
  SupabaseService._client = {
    auth: {
      getSession: async () => ({
        data: { session: { refresh_token: 'preserved-refresh-token' } },
        error: null,
      }),
      refreshSession: async () => ({ data: { session: null }, error: new Error('offline') }),
    },
  };
  SupabaseService._initialization = null;

  await assert.rejects(SupabaseService.initialize(), /offline/);
  assert.equal(values.get(SupabaseService.originMarkerKey), 'https://old.example.test');
});
