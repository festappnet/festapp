import type { Env } from './types';
import { resolveProjectByHostname } from './project-registry';
import { IMAGE_TRANSFORM_CONTRACT } from './transform-contract';

/** Public cache hits are independent of SQL and of the miss limiter. */
export async function handlePublicServe(
  request: Request,
  env: Env,
  ctx?: ExecutionContext,
  cache: Pick<Cache, "match" | "put"> | undefined =
    typeof caches === "undefined" ? undefined : caches.default,
): Promise<Response> {
  if (!["GET", "HEAD"].includes(request.method)) {
    return new Response("Method not allowed", { status: 405 });
  }
  const project = resolveProjectByHostname(env, new URL(request.url).hostname);
  if (project.authContract !== "festapp") {
    return servePublicObject(request, env);
  }
  const url = new URL(request.url);
  const transform = ["w", "f", "q"].some((k) => url.searchParams.has(k));
  const widthText = url.searchParams.get("w");
  const width = widthText === null
    ? Math.max(...IMAGE_TRANSFORM_CONTRACT.widths)
    : Number(widthText);
  const format = url.searchParams.get("f") ?? "auto";
  if (
    transform &&
    (!Number.isSafeInteger(width) || width <= 0 ||
      !["auto", "png", "webp", "jpeg", "jpg"].includes(format))
  ) {
    return new Response("Invalid image variant", { status: 400 });
  }
  url.search = "";
  url.hash = "";
  if (transform) {
    const preset = IMAGE_TRANSFORM_CONTRACT.widths.find((w) => w >= width) ??
      Math.max(...IMAGE_TRANSFORM_CONTRACT.widths);
    const quality = new URLSearchParams(
      IMAGE_TRANSFORM_CONTRACT.options[0].replaceAll(",", "&"),
    ).get("quality")!;
    url.searchParams.set("w", String(preset));
    url.searchParams.set("f", format === "jpg" ? "jpeg" : format);
    url.searchParams.set("q", quality);
  }
  const cacheUrl = new URL(url);
  if (transform && format === "auto") {
    const accept = request.headers.get("Accept") ?? "";
    cacheUrl.searchParams.set(
      "_format",
      accept.includes("image/avif")
        ? "avif"
        : accept.includes("image/webp")
        ? "webp"
        : "original",
    );
  }
  const key = new Request(cacheUrl, { method: "GET" });
  const cached = await cache?.match(key);
  if (cached) {
    if (
      cached.headers.has("etag") &&
      request.headers.get("If-None-Match") === cached.headers.get("etag")
    ) return new Response(null, { status: 304, headers: cached.headers });
    return new Response(request.method === "HEAD" ? null : cached.body, {
      status: cached.status,
      headers: cached.headers,
    });
  }
  try {
    if (
      !(await env.IMAGE_READ_MISS_BUDGET!.limit({ key: "festapp-public-read" }))
        .success
    ) {
      return new Response("Try again later", {
        status: 429,
        headers: { "Retry-After": "60", "Cache-Control": "no-store" },
      });
    }
  } catch {
    return new Response("Temporarily unavailable", {
      status: 503,
      headers: { "Cache-Control": "no-store" },
    });
  }
  const headers = new Headers(request.headers);
  if (transform) headers.delete("If-None-Match");
  const result = await servePublicObject(
    new Request(url, { method: request.method, headers }),
    env,
  );
  if (result.status === 200 && request.method === "GET" && cache) {
    const write = cache.put(key, result.clone()).catch(() => {});
    if (ctx) ctx.waitUntil(write);
    else await write;
  }
  return result;
}

/**
 * Serve public files from R2 with cache headers, conditional requests,
 * and optional on-the-fly image transforms via query parameters.
 *
 * Query params (all optional — omit for original):
 *   w  — target width in px (scale-down, preserve aspect ratio)
 *   f  — output format: 'auto' (negotiate from Accept), 'webp', 'jpeg', 'png'
 *   q  — quality 1-100
 *
 * When transform params are present and the Images binding is available,
 * the image is resized/re-encoded on the fly. The transformed variant
 * gets its own cache key (params are part of the URL).
 */

async function servePublicObject(
  request: Request,
  env: Env
): Promise<Response> {
  const url = new URL(request.url);
  const key = url.pathname.slice(1); // Remove leading /

  if (!key) {
    return new Response('Not found', { status: 404 });
  }

  const bucket = resolveProjectByHostname(env, url.hostname).publicBucket;

  // HEAD request — metadata only
  if (request.method === 'HEAD') {
    const head = await bucket.head(key);
    if (!head) {
      return new Response(null, { status: 404 });
    }
    const headers = new Headers();
    head.writeHttpMetadata(headers);
    headers.set('etag', head.httpEtag);
    headers.set('Cache-Control', 'public, max-age=31536000, immutable');
    return new Response(null, { status: 200, headers });
  }

  // GET request
  const object = await bucket.get(key);
  if (!object) {
    return new Response('Not found', { status: 404 });
  }

  // Conditional request — return 304 if etag matches
  const ifNoneMatch = request.headers.get('If-None-Match');
  if (ifNoneMatch && ifNoneMatch === object.httpEtag) {
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('etag', object.httpEtag);
    headers.set('Cache-Control', 'public, max-age=31536000, immutable');
    return new Response(null, { status: 304, headers });
  }

  // Parse optional transform query params
  const wParam = url.searchParams.get('w');
  const fParam = url.searchParams.get('f');
  const qParam = url.searchParams.get('q');
  const wantTransform = !!(wParam || fParam || qParam);

  if (wantTransform && env.IMAGES) {
    try {
      const width = wParam ? parseInt(wParam, 10) : undefined;
      const quality = qParam ? parseInt(qParam, 10) : undefined;

      // Resolve output format
      let outputFormat: string;
      if (fParam === 'auto') {
        const accept = request.headers.get('Accept') || '';
        if (accept.includes('image/avif')) {
          outputFormat = 'image/avif';
        } else if (accept.includes('image/webp')) {
          outputFormat = 'image/webp';
        } else {
          outputFormat = object.httpMetadata?.contentType || 'image/jpeg';
        }
      } else if (fParam === 'webp') {
        outputFormat = 'image/webp';
      } else if (fParam === 'png') {
        outputFormat = 'image/png';
      } else if (fParam === 'jpeg' || fParam === 'jpg') {
        outputFormat = 'image/jpeg';
      } else {
        outputFormat = object.httpMetadata?.contentType || 'image/jpeg';
      }

      // Build transform options
      const transformOpts: Record<string, unknown> = { fit: 'scale-down' };
      if (width) {
        transformOpts.width = width;
      }

      const outputOpts: Record<string, unknown> = { format: outputFormat };
      if (quality && !outputFormat.includes('png')) {
        outputOpts.quality = quality;
      }

      // Images binding .input() expects a ReadableStream
      const transformed = await env.IMAGES
        .input(object.body)
        .transform(transformOpts)
        .output(outputOpts);
      const resp = transformed.response();

      const headers = new Headers();
      headers.set('Content-Type', outputFormat);
      headers.set('Cache-Control', 'public, max-age=31536000, immutable');
      headers.set('Vary', 'Accept');

      return new Response(resp.body, { headers });
    } catch (err) {
      // Transform failed — re-fetch original from R2 (stream was consumed)
      console.error('image_transform_failed');
      const fallback = await bucket.get(key);
      if (fallback) {
        const headers = new Headers();
        fallback.writeHttpMetadata(headers);
        headers.set('etag', fallback.httpEtag);
        headers.set('Cache-Control', 'public, max-age=31536000, immutable');
        return new Response(fallback.body, { headers });
      }
      return new Response('Not found', { status: 404 });
    }
  }

  // Serve original (no transform requested)
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('etag', object.httpEtag);
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');

  return new Response(object.body, { headers });
}
