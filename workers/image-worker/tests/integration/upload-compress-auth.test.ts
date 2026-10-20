/**
 * Integration test for upload with compression, auth failures, and cleanup.
 *
 * Tests:
 *   1. Upload a large image → verify it gets compressed by the Images binding
 *   2. Upload a small image → verify it is stored as-is (no transform)
 *   3. Fetch uploaded images → verify they are accessible
 *   4. Delete uploaded images → verify cleanup (404 after delete)
 *   5. Auth failures: no token, fake token, missing fields
 *   6. Delete by unauthorized user is rejected
 *
 * Environment (reads from ../../.env.local or env vars):
 *   DATABASE_URL     - Direct PostgreSQL connection (for test user creation)
 *   SUPABASE_URL     - Supabase project URL
 *
 * Also uses the anon key from the project's AppConfig.
 *
 * The test creates a temporary user via direct DB insert, signs in via
 * Supabase Auth to get a JWT, runs all tests, then cleans up everything.
 *
 * Run: npm run test:integration
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

// ─── Config ──────────────────────────────────────────────────────

// Load a simple KEY=VALUE file (used for .env.local and automation/project.conf).
function loadKeyValueFile(path: string): Record<string, string> {
  const vars: Record<string, string> = {};
  try {
    const content = readFileSync(path, 'utf-8');
    for (const line of content.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eqIdx = trimmed.indexOf('=');
      if (eqIdx === -1) continue;
      const key = trimmed.slice(0, eqIdx).trim();
      let value = trimmed.slice(eqIdx + 1).trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
      vars[key] = value;
    }
  } catch {
    // file not found — fall back to other sources
  }
  return vars;
}

const envLocal = loadKeyValueFile(resolve(__dirname, '../../../../.env.local'));
const projectConf = loadKeyValueFile(
  resolve(__dirname, '../../../../automation/project.conf')
);
const env = (key: string) =>
  process.env[key] || envLocal[key] || projectConf[key] || '';

const WORKER_URL = process.env.TEST_WORKER_URL || projectConf.IMAGE_API_URL || 'https://image-api.festapp.net';
const PROJECT_ID = process.env.TEST_IMAGE_PROJECT_ID || projectConf.IMAGE_PROJECT_ID || 'default';
const PUBLIC_ORIGIN = PROJECT_ID === 'a' ? 'https://a.img.festapp.net' : 'https://img.festapp.net';
const SUPABASE_URL = env('SUPABASE_URL');
const DATABASE_URL = env('DATABASE_URL');
const ANON_KEY = env('SUPABASE_ANON_KEY');
// OCCASION_ID is auto-discovered from DB in beforeAll if not provided.
let OCCASION_ID = process.env.TEST_OCCASION_ID || '';

function isLocalDatabase(databaseUrl: string): boolean {
  try {
    const hostname = new URL(databaseUrl).hostname;
    return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '::1';
  } catch {
    return false;
  }
}

// The remote worker validates JWTs against the configured Supabase project.
// A user inserted into the isolated local database can never authenticate
// there, so keep this remote integration test out of local schema test runs.
const skip =
  !SUPABASE_URL || !DATABASE_URL || !ANON_KEY || isLocalDatabase(DATABASE_URL);

// Minimal valid JPEG (1x1 pixel, 107 bytes)
const MINIMAL_JPEG = new Uint8Array([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
  0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
  0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12,
  0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20,
  0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29,
  0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32,
  0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01,
  0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00, 0x1f, 0x00,
  0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
  0x08, 0x09, 0x0a, 0x0b, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00,
  0x3f, 0x00, 0x7b, 0x40, 0x1b, 0xff, 0xd9,
]);

// ─── Test user management via direct DB ──────────────────────────

const TEST_EMAIL = `test-imgworker-${Date.now()}@integration-test.local`;
const TEST_PASSWORD = `Test!${Date.now()}`;
let testUserId: string | null = null;
let testJwt: string | null = null;

/** Lazy-load pg to avoid dependency issues if not installed */
async function getPool() {
  const { default: pg } = await import('pg');
  return new pg.Pool({ connectionString: DATABASE_URL, max: 2 });
}

/** Create a temporary test user via direct DB + Supabase Auth sign-in. */
async function createTestUser(): Promise<{ id: string; jwt: string }> {
  const pool = await getPool();
  try {
    // 1. Generate a UUID for the test user
    const idResult = await pool.query('SELECT gen_random_uuid() AS id');
    const userId = idResult.rows[0].id;

    // 2. Hash the password using Supabase's crypt function
    const hashResult = await pool.query(
      `SELECT extensions.crypt($1, extensions.gen_salt('bf')) AS hash`,
      [TEST_PASSWORD]
    );
    const passwordHash = hashResult.rows[0].hash;

    // 3. Insert into auth.users (same pattern as create_user_in_organization_with_data_pure.sql)
    await pool.query(
      `INSERT INTO auth.users (
        id, instance_id, email, encrypted_password,
        email_confirmed_at, aud, role, created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data,
        confirmation_token, email_change, email_change_token_new, recovery_token
      ) VALUES (
        $1, '00000000-0000-0000-0000-000000000000', $2, $3,
        now(), 'authenticated', 'authenticated', now(), now(),
        '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        '', '', '', ''
      )`,
      [userId, TEST_EMAIL, passwordHash]
    );

    // 4. Insert auth.identities — required by GoTrue for email/password sign-in
    //    provider_id is varchar, user_id is uuid — use separate params to avoid type ambiguity
    await pool.query(
      `INSERT INTO auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
       VALUES (gen_random_uuid(), $1::varchar, $2::uuid, jsonb_build_object('sub', $3::text, 'email', $4::text), 'email', NULL, now(), now())`,
      [userId, userId, userId, TEST_EMAIL]
    );

    // 5. Ensure user_info record exists (trigger may or may not create it)
    await pool.query(
      `INSERT INTO public.user_info (id, name, surname, sex)
       VALUES ($1, 'Integration', 'Test', 'male')
       ON CONFLICT (id) DO NOTHING`,
      [userId]
    );

    // 6. Grant editor permission on the test occasion
    await pool.query(
      `INSERT INTO public.occasion_users (occasion, "user", is_editor)
       VALUES ($1, $2, true)
       ON CONFLICT DO NOTHING`,
      [parseInt(OCCASION_ID, 10), userId]
    );

    // 7. Sign in via Supabase Auth API to get a valid JWT
    const signInResp = await fetch(
      `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
      {
        method: 'POST',
        headers: {
          apikey: ANON_KEY,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email: TEST_EMAIL, password: TEST_PASSWORD }),
      }
    );
    if (!signInResp.ok) {
      const text = await signInResp.text();
      throw new Error(`Sign-in failed: ${signInResp.status} ${text}`);
    }
    const session = (await signInResp.json()) as { access_token: string };

    return { id: userId, jwt: session.access_token };
  } finally {
    await pool.end();
  }
}

/** Delete the temporary test user and all related data. */
async function deleteTestUser(userId: string): Promise<void> {
  const pool = await getPool();
  try {
    // Clean up in reverse dependency order
    await pool.query(
      `DELETE FROM public.images WHERE link LIKE '%integration-test%' OR link LIKE '%test-small%' OR link LIKE '%test-large%' OR link LIKE '%test-delete%' OR link LIKE '%duplicate-name%'`
    );
    await pool.query(
      `DELETE FROM public.occasion_users WHERE "user" = $1`,
      [userId]
    );
    await pool.query(
      `DELETE FROM public.user_info WHERE id = $1`,
      [userId]
    );
    // Delete auth identities first (FK to auth.users)
    await pool.query(
      `DELETE FROM auth.identities WHERE user_id = $1`,
      [userId]
    );
    await pool.query(
      `DELETE FROM auth.sessions WHERE user_id = $1`,
      [userId]
    );
    await pool.query(
      `DELETE FROM auth.refresh_tokens WHERE parent IN (
        SELECT token FROM auth.refresh_tokens WHERE session_id IN (
          SELECT id FROM auth.sessions WHERE user_id = $1
        )
      ) OR session_id IN (
        SELECT id FROM auth.sessions WHERE user_id = $1
      )`,
      [userId]
    );
    await pool.query(
      `DELETE FROM auth.users WHERE id = $1`,
      [userId]
    );
  } finally {
    await pool.end();
  }
}

// ─── Helpers ─────────────────────────────────────────────────────

async function uploadFile(
  file: Uint8Array,
  filename: string,
  options: {
    jwt?: string;
    occasionId?: string;
    extraFields?: Record<string, string>;
    omitFile?: boolean;
    omitOccasion?: boolean;
  } = {}
): Promise<Response> {
  const formData = new FormData();
  if (!options.omitFile) {
    formData.append('file', new Blob([file], { type: 'image/jpeg' }), filename);
  }
  if (!options.omitOccasion) {
    formData.append('occasionId', options.occasionId || OCCASION_ID);
  }
  formData.append('projectId', PROJECT_ID);
  if (options.extraFields) {
    for (const [k, v] of Object.entries(options.extraFields)) {
      formData.append(k, v);
    }
  }

  const headers: Record<string, string> = {};
  const jwt = options.jwt !== undefined ? options.jwt : testJwt!;
  if (jwt) {
    headers['Authorization'] = `Bearer ${jwt}`;
  }

  return fetch(`${WORKER_URL}/upload`, {
    method: 'POST',
    headers,
    body: formData,
  });
}

async function deleteKey(key: string, jwt?: string): Promise<Response> {
  return fetch(`${WORKER_URL}/delete`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${jwt || testJwt!}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(key.startsWith('private/')
      ? { key, projectId: PROJECT_ID }
      : { links: [`${PUBLIC_ORIGIN}/${key}`], projectId: PROJECT_ID }),
  });
}

// ─── Test Suite ──────────────────────────────────────────────────

describe.skipIf(skip)('Upload, Compress, Auth & Cleanup', () => {
  const uploadedKeys: string[] = [];

  beforeAll(async () => {
    if (skip) return;
    if (!OCCASION_ID) {
      const pool = await getPool();
      try {
        const result = await pool.query(
          'SELECT id FROM public.occasions ORDER BY id LIMIT 1'
        );
        if (result.rows.length === 0) {
          throw new Error(
            'No occasions found in DB — set TEST_OCCASION_ID env to a valid occasion id.'
          );
        }
        OCCASION_ID = String(result.rows[0].id);
        console.log(`Auto-discovered TEST_OCCASION_ID: ${OCCASION_ID}`);
      } finally {
        await pool.end();
      }
    }
    const { id, jwt } = await createTestUser();
    testUserId = id;
    testJwt = jwt;
    console.log(`Test user created: ${TEST_EMAIL} (${id})`);
  }, 30_000);

  afterAll(async () => {
    // Clean up R2 images
    if (testJwt) {
      for (const key of uploadedKeys) {
        try { await deleteKey(key); } catch { /* best-effort */ }
      }
    }
    // Clean up test user
    if (testUserId) {
      await deleteTestUser(testUserId);
      console.log(`Test user deleted: ${TEST_EMAIL}`);
    }
  }, 30_000);

  // ── Auth failures ─────────────────────────────────────────────

  describe('Auth failures', () => {
    it('rejects upload with no Authorization header (401)', async () => {
      const resp = await uploadFile(MINIMAL_JPEG, 'no-auth.jpg', { jwt: '' });
      expect(resp.status).toBe(401);
    });

    it('rejects upload with fake JWT (403)', async () => {
      const resp = await uploadFile(MINIMAL_JPEG, 'fake-jwt.jpg', {
        jwt: 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDAifQ.xyz',
      });
      expect(resp.status).toBe(403);
    });

    it('rejects upload with malformed bearer prefix (401)', async () => {
      // Build a proper form body but use a non-"Bearer" authorization scheme
      const formData = new FormData();
      formData.append('file', new Blob([MINIMAL_JPEG], { type: 'image/jpeg' }), 'x.jpg');
      formData.append('occasionId', OCCASION_ID);
      formData.append('projectId', PROJECT_ID);
      const resp = await fetch(`${WORKER_URL}/upload`, {
        method: 'POST',
        headers: { Authorization: 'Basic dXNlcjpwYXNz' },
        body: formData,
      });
      expect(resp.status).toBe(401);
    });
  });

  // ── Validation failures ───────────────────────────────────────

  describe('Validation failures', () => {
    it('rejects upload without file field (400)', async () => {
      const resp = await uploadFile(MINIMAL_JPEG, 'x.jpg', { omitFile: true });
      expect(resp.status).toBe(400);
    });

    it('rejects upload without occasionId or unitId (400)', async () => {
      const resp = await uploadFile(MINIMAL_JPEG, 'x.jpg', { omitOccasion: true });
      expect(resp.status).toBe(400);
    });

    it('rejects non-POST method (405)', async () => {
      const resp = await fetch(`${WORKER_URL}/upload`, { method: 'GET' });
      expect(resp.status).toBe(405);
    });
  });

  // ── Small image (no transform) ────────────────────────────────

  describe('Small image (no transform)', () => {
    let url: string;
    let key: string;

    it('uploads without transform', async () => {
      const resp = await uploadFile(MINIMAL_JPEG, 'test-small.jpg');
      expect(resp.status).toBe(200);

      const json = (await resp.json()) as { url: string; key: string };
      // Allow any *.img.festapp.net subdomain (multi-instance routing).
      expect(json.url).toMatch(/^https:\/\/(?:[a-z]+\.)?img\.festapp\.net\//);
      expect(json.key).toMatch(/^images\//);

      url = json.url;
      key = json.key;
      uploadedKeys.push(key);
    });

    it('stored as-is (size = input size)', async () => {
      const resp = await fetch(url);
      expect(resp.status).toBe(200);
      const body = await resp.arrayBuffer();
      expect(body.byteLength).toBe(MINIMAL_JPEG.byteLength);
    });

    it('delete succeeds', async () => {
      const resp = await deleteKey(key);
      expect(resp.status).toBe(200);
      uploadedKeys.splice(uploadedKeys.indexOf(key), 1);
    });

    it('returns 404 after delete', async () => {
      await new Promise((r) => setTimeout(r, 500));
      expect((await fetch(url)).status).toBe(404);
    });
  });

  // ── Large image (with transform) ──────────────────────────────

  describe('Large image (with transform)', () => {
    let url: string;
    let key: string;
    let inputSize: number;

    it('uploads and compresses a real photo', async () => {
      const imgResp = await fetch('https://picsum.photos/2000/3000.jpg');
      expect(imgResp.ok).toBe(true);
      const buf = await imgResp.arrayBuffer();
      inputSize = buf.byteLength;

      const resp = await uploadFile(
        new Uint8Array(buf),
        'test-large-compress.jpg',
        { extraFields: { maxBytes: '1', maxEdge: '800', quality: '60' } }
      );
      expect(resp.status).toBe(200);

      const json = (await resp.json()) as { url: string; key: string };
      url = json.url;
      key = json.key;
      uploadedKeys.push(key);
    }, 30_000);

    it('output is smaller than input', async () => {
      const resp = await fetch(url);
      expect(resp.status).toBe(200);
      const outputBuf = await resp.arrayBuffer();
      expect(outputBuf.byteLength).toBeGreaterThan(0);
      expect(outputBuf.byteLength).toBeLessThan(inputSize);
    });

    it('content-type is image/jpeg', async () => {
      const resp = await fetch(url);
      expect(resp.headers.get('content-type')).toBe('image/jpeg');
    });

    it('delete succeeds', async () => {
      const resp = await deleteKey(key);
      expect(resp.status).toBe(200);
      uploadedKeys.splice(uploadedKeys.indexOf(key), 1);
    });

    it('returns 404 after delete', async () => {
      await new Promise((r) => setTimeout(r, 500));
      expect((await fetch(url)).status).toBe(404);
    });
  });

  // ── Delete auth failures ──────────────────────────────────────

  describe('Delete auth failures', () => {
    let key: string;

    it('uploads test image', async () => {
      const resp = await uploadFile(MINIMAL_JPEG, 'test-delete-auth.jpg');
      expect(resp.status).toBe(200);
      key = ((await resp.json()) as { key: string }).key;
      uploadedKeys.push(key);
    });

    it('rejects delete with no auth (401)', async () => {
      const resp = await fetch(`${WORKER_URL}/delete`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key }),
      });
      expect(resp.status).toBe(401);
    });

    it('rejects delete with fake JWT (403)', async () => {
      const resp = await deleteKey(key, 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIwIn0.xxx');
      expect(resp.status).toBe(403);
    });

    it('rejects delete with invalid key prefix (400)', async () => {
      const resp = await deleteKey('not-images/x.jpg');
      expect(resp.status).toBe(400);
    });

    it('rejects delete without key field (400)', async () => {
      const resp = await fetch(`${WORKER_URL}/delete`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${testJwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({}),
      });
      expect(resp.status).toBe(400);
    });

    it('cleans up test image', async () => {
      const resp = await deleteKey(key);
      expect(resp.status).toBe(200);
      uploadedKeys.splice(uploadedKeys.indexOf(key), 1);
    });
  });

  // ── Unique keys ───────────────────────────────────────────────

  describe('Unique keys', () => {
    it('same filename produces different keys', async () => {
      const r1 = await uploadFile(MINIMAL_JPEG, 'duplicate-name.jpg');
      const r2 = await uploadFile(MINIMAL_JPEG, 'duplicate-name.jpg');
      expect(r1.status).toBe(200);
      expect(r2.status).toBe(200);

      const k1 = ((await r1.json()) as { key: string }).key;
      const k2 = ((await r2.json()) as { key: string }).key;
      uploadedKeys.push(k1, k2);

      expect(k1).not.toBe(k2);

      await deleteKey(k1);
      await deleteKey(k2);
      uploadedKeys.splice(uploadedKeys.indexOf(k1), 1);
      uploadedKeys.splice(uploadedKeys.indexOf(k2), 1);
    });
  });

  // ── Private file access ────────────────────────────────────

  describe('Private file access', () => {
    const privateKey = `private/test-private-${Date.now()}.jpg`;
    // Public origin (e.g. https://a.img.festapp.net) discovered from the upload
    // response. Routes to the bucket matching the project's SUPABASE_URL.
    let publicOrigin: string = WORKER_URL;
    // Worker's serve-private.ts currently verifies JWTs against env.SUPABASE_URL
    // (the default project) only. When running against a non-default instance
    // (subdomain other than img.festapp.net), the editor-permission RPC always
    // fails because the JWT issuer doesn't match. Skip the editor-auth checks
    // in that case; they require a worker code change + per-instance anon keys.
    let crossInstance = false;

    it('uploads to private/ path', async () => {
      const formData = new FormData();
      formData.append('file', new Blob([MINIMAL_JPEG], { type: 'image/jpeg' }), 'test-private.jpg');
      formData.append('key', privateKey);
      formData.append('occasionId', OCCASION_ID);
      formData.append('projectId', PROJECT_ID);

      const resp = await fetch(`${WORKER_URL}/upload`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${testJwt}` },
        body: formData,
      });
      expect(resp.status).toBe(200);
      const json = (await resp.json()) as { url: string };
      publicOrigin = new URL(json.url).origin;
      crossInstance = false;
      uploadedKeys.push(privateKey);
    });

    it('rejects unauthenticated request to private/ (401)', async () => {
      const resp = await fetch(`${publicOrigin}/${privateKey}?projectId=${PROJECT_ID}`);
      expect(resp.status).toBe(401);
    });

    it('allows authenticated editor request to private/ (200)', async (ctx) => {
      if (crossInstance) ctx.skip();
      const resp = await fetch(`${publicOrigin}/${privateKey}?projectId=${PROJECT_ID}`, {
        headers: { Authorization: `Bearer ${testJwt}` },
      });
      expect(resp.status).toBe(200);
      expect(resp.headers.get('content-type')).toMatch(/^image\//);
    });

    it('returns 404 for non-existent private file', async (ctx) => {
      if (crossInstance) ctx.skip();
      const resp = await fetch(`${publicOrigin}/private/nonexistent-${Date.now()}.jpg?projectId=${PROJECT_ID}`, {
        headers: { Authorization: `Bearer ${testJwt}` },
      });
      expect(resp.status).toBe(404);
    });

    it('cleans up private test file', async () => {
      const resp = await deleteKey(privateKey);
      expect(resp.status).toBe(200);
      uploadedKeys.splice(uploadedKeys.indexOf(privateKey), 1);
    });
  });
});
