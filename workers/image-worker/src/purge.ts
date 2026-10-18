import type { Env } from './types';
import { IMAGE_TRANSFORM_CONTRACT } from './transform-contract';

export function sourceCacheUrls(sourceUrl: string): string[] {
  const source = new URL(sourceUrl);
  const urls = [sourceUrl];
  if (!IMAGE_TRANSFORM_CONTRACT.publicHosts.includes(source.hostname)) return urls;
  for (const width of IMAGE_TRANSFORM_CONTRACT.widths) {
    for (const format of ['auto','png','webp','jpeg']) {
      const variant = new URL(source);
      variant.searchParams.set('w', String(width));
      variant.searchParams.set('f', format);
      variant.searchParams.set('q', '75');
      if (format === 'auto') {
        for (const accepted of ['avif','webp','original']) {
          variant.searchParams.set('_format', accepted);
          urls.push(variant.href);
        }
      } else urls.push(variant.href);
    }
  }
  if (source.pathname.startsWith(IMAGE_TRANSFORM_CONTRACT.sourcePathPrefix)) {
    for (const options of IMAGE_TRANSFORM_CONTRACT.options) {
      urls.push(`${source.origin}/cdn-cgi/image/${options}/${sourceUrl}`);
    }
  }
  return urls;
}

export class PurgeError extends Error {
  constructor(readonly retryable: boolean, message: string) { super(message); }
}

export async function purgeSourceUrl(env: Env, sourceUrl: string): Promise<void> {
  if (!env.CF_ZONE_ID || !env.CF_CACHE_PURGE_TOKEN) {
    throw new PurgeError(true, 'Cache purge is not configured');
  }
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/zones/${env.CF_ZONE_ID}/purge_cache`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.CF_CACHE_PURGE_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ files: sourceCacheUrls(sourceUrl) }),
    },
  );
  if (!response.ok) {
    throw new PurgeError(response.status === 429 || response.status >= 500, `Cache purge failed (${response.status})`);
  }
}
