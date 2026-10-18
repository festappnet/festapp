import { webcrypto } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { handleAccountAssets } from '../../src/account-assets';
import worker from '../../src/index';
import type { Env } from '../../src/types';
import { purgeSourceUrl } from '../../src/purge';

vi.stubGlobal('crypto', webcrypto);
vi.mock('../../src/purge', () => ({ purgeSourceUrl: vi.fn() }));
const secret = 'account-only-capability-012345678901234567890';
const sha256 = 'a'.repeat(64);
const key = `assets/storage/editor-files/${'b'.repeat(20)}/${'c'.repeat(64)}/${sha256}`;
const head = vi.fn(), remove = vi.fn();
const env = { ASSET_CLEANUP_SERVICE_SECRET: secret, IMAGES_PRIVATE_BUCKET: { head, delete: remove }, IMAGES_BUCKET: { head, delete: remove } } as unknown as Env;
const request = (body: unknown = { bucket: 'festapp-images-private', key, sha256 }, token = secret, host = 'image-api') => new Request(`https://${host}.festapp.net/service/account-assets`, { method: 'DELETE', headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body) });
beforeEach(() => { vi.resetAllMocks(); });

describe('service-only account asset cleanup', () => {
  it('deletes a verified private asset and treats absence as an idempotent replay', async () => {
    head.mockResolvedValueOnce({ customMetadata: { sha256 } }).mockResolvedValueOnce(null);
    expect((await handleAccountAssets(request(), env)).status).toBe(204);
    expect((await handleAccountAssets(request(), env)).status).toBe(204);
    expect(remove).toHaveBeenCalledExactlyOnceWith(key);
    expect(purgeSourceUrl).not.toHaveBeenCalled();
  });
  it('retries public purge after an already completed delete', async () => {
    head.mockResolvedValue(null);
    vi.mocked(purgeSourceUrl).mockRejectedValueOnce(new Error('purge failed')).mockResolvedValueOnce(undefined);
    const publicRequest = () => request({ bucket: 'festapp-images', key, sha256 });
    await expect(handleAccountAssets(publicRequest(), env)).rejects.toThrow('purge failed');
    expect((await handleAccountAssets(publicRequest(), env)).status).toBe(204);
    expect(purgeSourceUrl).toHaveBeenCalledTimes(2);
  });
  it('rejects wrong host, user/font credentials, noncanonical buckets and fonts', async () => {
    expect((await worker.fetch(request(undefined, secret, 'img'), env)).status).toBe(404);
    expect((await handleAccountAssets(request(undefined, 'user-jwt'), env)).status).toBe(401);
    expect((await handleAccountAssets(request(), { ...env, ASSET_CLEANUP_SERVICE_SECRET: undefined })).status).toBe(503);
    expect((await handleAccountAssets(request({ bucket: 'festapp-images-akhweb', key, sha256 }), env)).status).toBe(400);
    expect((await handleAccountAssets(request({ bucket: 'festapp-images-private', key: 'ticket-fonts/sha256/' + sha256 + '.ttf', sha256 }), env)).status).toBe(400);
    expect(head).not.toHaveBeenCalled();
  });
  it('does not delete hash conflicts or oversized request bodies', async () => {
    head.mockResolvedValue({ customMetadata: { sha256: 'wrong' } });
    expect((await handleAccountAssets(request(), env)).status).toBe(409);
    expect((await handleAccountAssets(request('x'.repeat(5000)), env)).status).toBe(413);
    expect(remove).not.toHaveBeenCalled();
  });
});
