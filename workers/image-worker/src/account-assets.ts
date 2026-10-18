import type { Env } from './types';
import { equalServiceSecret } from './service-auth';
import { purgeSourceUrl } from './purge';

/** Dedicated deletion capability for hash-immutable migrated user assets only.
 * SQL owns the account/job/owner binding. Acknowledgement follows R2+purge;
 * loss of a response is safe to replay, including after object deletion.
 */
export async function handleAccountAssets(request: Request, env: Env): Promise<Response> {
  const reply = (status: number) => new Response(null, { status, headers: { 'Cache-Control': 'private, no-store' } });
  const uri = new URL(request.url);
  if (uri.hostname !== 'image-api.festapp.net' || uri.pathname !== '/service/account-assets' || uri.search) return reply(404);
  const secret = env.ASSET_CLEANUP_SERVICE_SECRET;
  const auth = request.headers.get('Authorization') ?? '';
  if (!secret || secret.length < 32) return reply(503);
  if (!auth.startsWith('Bearer ') || auth.length > 512 || !await equalServiceSecret(auth.slice(7), secret)) return reply(401);
  if (request.method !== 'DELETE') return reply(405);
  // Bound actual streamed bytes as well as the untrusted declared length.
  if (!request.body || Number(request.headers.get('Content-Length') || 0) > 4096) return reply(413);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = []; let size = 0;
  while (true) {
    const next = await reader.read(); if (next.done) break;
    size += next.value.length;
    if (size > 4096) { await reader.cancel(); return reply(413); }
    chunks.push(next.value);
  }
  let body: { bucket?: unknown; key?: unknown; sha256?: unknown };
  try {
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    body = JSON.parse(new TextDecoder().decode(bytes));
    if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some(key => !['bucket', 'key', 'sha256'].includes(key))) return reply(400);
  } catch { return reply(400); }
  const { bucket, key, sha256 } = body;
  if (typeof key !== 'string' || typeof sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(sha256)
    || !/^(assets|images)\/storage\/[A-Za-z0-9_-]+\/[a-f0-9]{20}\/[a-f0-9]{64}\/[a-f0-9]{64}$/.test(key)
    || !key.endsWith('/' + sha256)) return reply(400);
  const storage = bucket === 'festapp-images' ? env.IMAGES_BUCKET
    : bucket === 'festapp-images-private' ? env.IMAGES_PRIVATE_BUCKET : null;
  if (!storage) return reply(400);
  const object = await storage.head(key);
  if (object && object.customMetadata?.sha256 !== sha256) return reply(409);
  if (object) await storage.delete(key);
  if (bucket === 'festapp-images') await purgeSourceUrl(env, `https://img.festapp.net/${key}`);
  return reply(204);
}
