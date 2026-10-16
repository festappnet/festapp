export interface Env {
  PUBLIC_SYNC: R2Bucket;
  SYNC_MISS_BUDGET: { limit(input: { key: string }): Promise<{ success: boolean }> };
}

export interface ResponseCache {
  match(request: Request): Promise<Response | undefined>;
  put(request: Request, response: Response): Promise<void>;
}

const PATH = /^\/v1\/public-sync\/(\d+)\/(\d+)\/head$/;
const CACHE_CONTROL = 'public, max-age=0, must-revalidate, s-maxage=5';
const NOT_PUBLISHED_CACHE_CONTROL = 'public, max-age=0, must-revalidate, s-maxage=5';

function responseHeaders(etag: string): Headers {
  return new Headers({
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': CACHE_CONTROL,
    ETag: etag,
    Vary: 'Accept-Encoding',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
    'Access-Control-Allow-Headers': 'If-None-Match',
    'X-Content-Type-Options': 'nosniff',
  });
}

function matchesEtag(header: string | null, current: string): boolean {
  if (!header) return false;
  return header.split(',').some((candidate) => {
    const normalized = candidate.trim().replace(/^W\//, '');
    return normalized === '*' || normalized === current;
  });
}

function canonicalCacheKey(request: Request): Request {
  const url = new URL(request.url);
  url.hash = '';
  url.search = '';
  return new Request(url.toString(), { method: 'GET' });
}

function forCaller(request: Request, cached: Response): Response {
  const headers = new Headers(cached.headers);
  const etag = headers.get('ETag');
  if (cached.status === 200 && etag && matchesEtag(request.headers.get('If-None-Match'), etag)) {
    return new Response(null, { status: 304, headers });
  }
  return new Response(request.method === 'HEAD' ? null : cached.body, {
    status: cached.status,
    statusText: cached.statusText,
    headers,
  });
}

export async function handleRequest(
  request: Request,
  env: Env,
  ctx?: ExecutionContext,
  cache: ResponseCache = (caches as unknown as { default: ResponseCache }).default,
): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: responseHeaders('"options"') });
  }
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD, OPTIONS' } });
  }

  const url = new URL(request.url);
  const match = PATH.exec(url.pathname);
  if (!match || !Number.isSafeInteger(Number(match[1])) || !Number.isSafeInteger(Number(match[2])) || Number(match[1]) <= 0 || Number(match[2]) <= 0) return new Response('Not found', { status: 404 });

  const cacheKey = canonicalCacheKey(request);
  const cached = await cache.match(cacheKey);
  if (cached) return forCaller(request, cached);

  // Native per-location protection bounds random cache misses without SQL or a
  // user-controlled key. It is best effort, not a globally exact billing cap.
  try {
    if (!(await env.SYNC_MISS_BUDGET.limit({ key: 'public-head-miss' })).success) {
      return new Response('Try again later', { status: 429, headers: { 'Retry-After': '60', 'Cache-Control': 'no-store' } });
    }
  } catch { return new Response('Temporarily unavailable', { status: 503 }); }

  const [, organizationId, occasionId] = match;
  const object = await env.PUBLIC_SYNC.get(
    `client-sync/v1/${organizationId}/${occasionId}/public-head.json`,
  );
  if (!object) {
    const headers = responseHeaders('"not-published"');
    headers.set('Cache-Control', NOT_PUBLISHED_CACHE_CONTROL);
    const response = Response.json(
      { protocol: 1, code: 'not_published' },
      { status: 404, headers },
    );
    const population = cache.put(cacheKey, response.clone()).catch((error: unknown) => {
      console.warn(JSON.stringify({ event: 'public_sync_cache_put_failed', message: error instanceof Error ? error.message : String(error) }));
    });
    if (ctx) ctx.waitUntil(population); else await population;
    return forCaller(request, response);
  }

  const etag = object.httpEtag;
  const headers = responseHeaders(etag);
  const response = new Response(object.body, {
    status: 200,
    headers,
  });
  const population = cache.put(cacheKey, response.clone()).catch((error: unknown) => {
    console.warn(JSON.stringify({ event: 'public_sync_cache_put_failed', message: error instanceof Error ? error.message : String(error) }));
  });
  if (ctx) ctx.waitUntil(population); else await population;
  return forCaller(request, response);
}

export default {
  fetch(request, env, ctx) {
    return handleRequest(request, env, ctx);
  },
} satisfies ExportedHandler<Env>;
