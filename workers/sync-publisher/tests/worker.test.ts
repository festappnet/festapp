import { describe, expect, it, vi } from 'vitest';
import { handlePublicationTick, type Env } from '../src/worker.js';

function environment(): Env {
  return {
    PUBLIC_SYNC: {} as R2Bucket,
    SUPABASE_URL: 'https://database.test',
    SUPABASE_SERVICE_ROLE_KEY: 'service-key',
    SYNC_ASSET_ORIGIN: 'https://assets.test',
    SYNC_SCOPE_IDS: '643',
    PUBLISHER_WAKE_TOKEN: 'wake-secret',
    SYNC_RETENTION_APPLY: 'false',
    SYNC_ARTIFACT_RETENTION_DAYS: '7',
    SYNC_RECEIPT_RETENTION_DAYS: '30',
  };
}

describe('publication tick boundary', () => {
  it.each([
    ['missing token', new Request('https://publisher.test/v1/internal/publication-tick', { method: 'POST' }), 401],
    ['wrong token', new Request('https://publisher.test/v1/internal/publication-tick', { method: 'POST', headers: { Authorization: 'Bearer wrong' } }), 401],
    ['wrong path', new Request('https://publisher.test/v1/internal/other', { method: 'POST' }), 404],
    ['wrong method', new Request('https://publisher.test/v1/internal/publication-tick'), 405],
  ])('rejects %s before database access', async (_name, request, status) => {
    const fetchMock = vi.spyOn(globalThis, 'fetch');
    expect((await handlePublicationTick(request, environment())).status).toBe(status);
    expect(fetchMock).not.toHaveBeenCalled();
    fetchMock.mockRestore();
  });

  it('rejects caller-selected scope data before database access', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch');
    const response = await handlePublicationTick(new Request(
      'https://publisher.test/v1/internal/publication-tick',
      { method: 'POST', headers: { Authorization: 'Bearer wake-secret' }, body: JSON.stringify({ scopeId: 999 }) },
    ), environment());
    expect(response.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
    fetchMock.mockRestore();
  });

  it('bounds a chunked body even without Content-Length', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch');
    const response = await handlePublicationTick(new Request(
      'https://publisher.test/v1/internal/publication-tick',
      { method: 'POST', headers: { Authorization: 'Bearer wake-secret' }, body: 'x'.repeat(257) },
    ), environment());
    expect(response.status).toBe(413);
    expect(fetchMock).not.toHaveBeenCalled();
    fetchMock.mockRestore();
  });

  it('uses configured scopes for an authenticated empty tick', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('[]'));
    const response = await handlePublicationTick(new Request(
      'https://publisher.test/v1/internal/publication-tick',
      { method: 'POST', headers: { Authorization: 'Bearer wake-secret' } },
    ), environment());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(expect.objectContaining({ status: 'ok', publishedScopes: 0 }));
    expect(fetchMock).toHaveBeenCalledWith(
      'https://database.test/rest/v1/rpc/claim_client_projection_dirty_scopes_v1',
      expect.objectContaining({ body: JSON.stringify({ p_scope_ids: [643], p_limit: 1000 }) }),
    );
    fetchMock.mockRestore();
  });
});
