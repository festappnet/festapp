import { describe, expect, it, vi } from 'vitest';
import { handleRequest, type Env, type ResponseCache } from '../src/index';

const body = JSON.stringify({ protocol: 1, serverTime: '2026-08-02T12:00:00Z' });

function environment(found = true): Env {
  return {
    SYNC_MISS_BUDGET: { limit: vi.fn(async () => ({ success: true })) },
    PUBLIC_SYNC: {
      get: vi.fn(async () =>
        found
          ? {
              body,
              httpEtag: '"head-digest"',
            }
          : null),
    } as unknown as R2Bucket,
  };
}

function memoryCache(): ResponseCache {
  const entries = new Map<string, Response>();
  return {
    match: vi.fn(async (request) => entries.get(request.url)?.clone()),
    put: vi.fn(async (request, response) => {
      entries.set(request.url, response.clone());
    }),
  };
}

describe('public sync head', () => {
  it('reads only the scoped R2 head and emits bounded revalidation headers', async () => {
    const env = environment();
    const cache = memoryCache();
    const response = await handleRequest(
      new Request('https://sync.festapp.net/v1/public-sync/7/42/head'),
      env,
      undefined,
      cache,
    );
    expect(response.status).toBe(200);
    expect(await response.text()).toBe(body);
    expect(response.headers.get('cache-control')).toContain('s-maxage=5');
    expect(response.headers.get('cache-control')).toBe(
      'public, max-age=0, must-revalidate, s-maxage=5',
    );
    expect(env.PUBLIC_SYNC.get).toHaveBeenCalledWith(
      'client-sync/v1/7/42/public-head.json',
    );
  });

  it('returns 304 for the current ETag without reading any database', async () => {
    const env = environment();
    const cache = memoryCache();
    await handleRequest(
      new Request('https://sync.festapp.net/v1/public-sync/7/42/head'),
      env,
      undefined,
      cache,
    );
    const response = await handleRequest(
      new Request('https://sync.festapp.net/v1/public-sync/7/42/head', {
        headers: { 'If-None-Match': '"head-digest"' },
      }),
      env,
      undefined,
      cache,
    );
    expect(response.status).toBe(304);
    expect(await response.text()).toBe('');
    expect(env.PUBLIC_SYNC.get).toHaveBeenCalledOnce();
  });

  it('accepts the weak ETag emitted after Cloudflare content encoding', async () => {
    const env = environment();
    const cache = memoryCache();
    await handleRequest(new Request('https://sync.festapp.net/v1/public-sync/7/42/head'), env, undefined, cache);
    const response = await handleRequest(
      new Request('https://sync.festapp.net/v1/public-sync/7/42/head', {
        headers: { 'If-None-Match': 'W/"head-digest"' },
      }),
      env,
      undefined,
      cache,
    );
    expect(response.status).toBe(304);
  });

  it('does not expose an arbitrary bucket key', async () => {
    const env = environment();
    const response = await handleRequest(
      new Request('https://sync.festapp.net/client-sync/v1/7/42/private.json'),
      env,
      undefined,
      memoryCache(),
    );
    expect(response.status).toBe(404);
    expect(env.PUBLIC_SYNC.get).not.toHaveBeenCalled();
  });

  it('serves a sequential GET and HEAD from one canonical cache entry', async () => {
    const env = environment();
    const cache = memoryCache();
    const first = await handleRequest(new Request('https://sync.festapp.net/v1/public-sync/7/42/head'), env, undefined, cache);
    const second = await handleRequest(new Request('https://sync.festapp.net/v1/public-sync/7/42/head', { method: 'HEAD' }), env, undefined, cache);
    expect(await first.text()).toBe(body);
    expect(await second.text()).toBe('');
    expect(env.PUBLIC_SYNC.get).toHaveBeenCalledOnce();
  });

  it('does not fragment the canonical cache key with query strings', async () => {
    const env = environment();
    const cache = memoryCache();
    await handleRequest(new Request('https://sync.festapp.net/v1/public-sync/7/42/head?first=1'), env, undefined, cache);
    await handleRequest(new Request('https://sync.festapp.net/v1/public-sync/7/42/head?second=2'), env, undefined, cache);
    expect(env.PUBLIC_SYNC.get).toHaveBeenCalledOnce();
  });

  it('caches not-published responses for five seconds', async () => {
    const env = environment(false);
    const cache = memoryCache();
    const request = new Request('https://sync.festapp.net/v1/public-sync/7/42/head');
    expect((await handleRequest(request, env, undefined, cache)).status).toBe(404);
    expect((await handleRequest(request, env, undefined, cache)).status).toBe(404);
    expect(env.PUBLIC_SYNC.get).toHaveBeenCalledOnce();
  });

  it('does not cache OPTIONS or method errors', async () => {
    const env = environment();
    const cache = memoryCache();
    expect((await handleRequest(new Request('https://sync.festapp.net/v1/public-sync/7/42/head', { method: 'OPTIONS' }), env, undefined, cache)).status).toBe(204);
    expect((await handleRequest(new Request('https://sync.festapp.net/v1/public-sync/7/42/head', { method: 'POST' }), env, undefined, cache)).status).toBe(405);
    expect(cache.put).not.toHaveBeenCalled();
    expect(env.PUBLIC_SYNC.get).not.toHaveBeenCalled();
  });
});

it('blocks random misses before R2 while serving an existing cache hit', async () => {
  const env = environment(); const cache = memoryCache();
  const known = new Request('https://sync.festapp.net/v1/public-sync/7/42/head');
  await handleRequest(known, env, undefined, cache);
  vi.mocked(env.SYNC_MISS_BUDGET.limit).mockResolvedValue({ success: false });
  expect((await handleRequest(new Request('https://sync.festapp.net/v1/public-sync/7/43/head'), env, undefined, cache)).status).toBe(429);
  expect((await handleRequest(known, env, undefined, cache)).status).toBe(200);
  expect(env.PUBLIC_SYNC.get).toHaveBeenCalledTimes(1);
});
