import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { deleteAccountAssets, type AccountAsset } from './accountAssets.ts';

const secret = 'cleanup-only-server-secret-01234567890123456789';
const sha256 = 'a'.repeat(64);
const asset: AccountAsset = { assetId: '11111111-1111-4111-8111-111111111111', bucket: 'festapp-images-private', key: `assets/storage/editor-files/${'b'.repeat(20)}/${'c'.repeat(64)}/${sha256}`, sha256 };

Deno.test('R2 deletion acknowledgement follows remote success; replay resumes the same object', async () => {
  const events: string[] = [];
  let acknowledged = false;
  const deps = {
    getBatch: async () => acknowledged ? [] : [asset], secret: () => secret,
    fetch: async (url: string | URL | Request, init?: RequestInit) => {
      assertEquals(url, 'https://image-api.festapp.net/service/account-assets');
      assertEquals(init?.redirect, 'error');
      assertEquals(JSON.parse(init?.body as string), { bucket: asset.bucket, key: asset.key, sha256 });
      events.push('remote'); return new Response(null, { status: 204 });
    },
    acknowledge: async () => { events.push('ack'); if (events.length === 2) throw new Error('lost SQL connection'); acknowledged = true; },
  };
  await assertRejects(() => deleteAccountAssets('request', deps), Error, 'lost SQL');
  await deleteAccountAssets('request', deps);
  assertEquals(events, ['remote', 'ack', 'remote', 'ack']);
});

Deno.test('R2 failure never acknowledges; malformed identity rejects the whole batch before deletion', async () => {
  let calls = 0;
  const deps = {
    getBatch: async () => [asset], secret: () => secret,
    fetch: async () => { calls++; return new Response(null, { status: 503 }); },
    acknowledge: async () => { throw new Error('must not acknowledge'); },
  };
  await assertRejects(() => deleteAccountAssets('request', deps), Error, 'retryable');
  assertEquals(calls, 1);
  await assertRejects(() => deleteAccountAssets('request', { ...deps, getBatch: async () => [asset, { ...asset, key: 'ticket-fonts/sha256/private.ttf' }] }), Error, 'asset_inventory');
  assertEquals(calls, 1);
});

Deno.test('dedicated cleanup capability is required only for a nonempty valid job', async () => {
  const deps = { getBatch: async () => [], secret: () => undefined, acknowledge: async () => {} };
  await deleteAccountAssets('request', deps);
  await assertRejects(() => deleteAccountAssets('request', { ...deps, getBatch: async () => [asset] }), Error, 'asset_cleanup_config');
});
