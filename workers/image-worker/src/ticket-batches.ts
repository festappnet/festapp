import type { Env } from './types';
import { equalServiceSecret } from './service-auth';

const MAX_BYTES = 16 * 1024 * 1024;
const KEY = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\/(?:resources\/[a-f0-9]{64}|[a-f0-9]{64}\/(?:single|print)-[0-9]{3}\.pdf)$/;

/** Backend capability for create/read of immutable batch artifacts only. */
export async function handleTicketBatches(request: Request, env: Env): Promise<Response> {
  const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
  const reply = (status: number) => new Response(null, { status, headers });
  const uri = new URL(request.url);
  if (uri.hostname !== 'image-api.festapp.net' || uri.search || uri.hash) return reply(404);
  const secret = env.TICKET_BATCH_SERVICE_SECRET;
  const auth = request.headers.get('Authorization') ?? '';
  if (!secret || secret.length < 32) return reply(503);
  if (!auth.startsWith('Bearer ') || auth.length > 512 || !await equalServiceSecret(auth.slice(7), secret)) return reply(401);
  if (!['GET', 'PUT'].includes(request.method)) return reply(405);
  const key = uri.pathname.slice('/service/ticket-batches/'.length);
  if (!KEY.test(key)) return reply(400);
  const storageKey = `ticket-batches/${key}`;
  if (request.method === 'GET') {
    const object = await env.IMAGES_PRIVATE_BUCKET.get(storageKey);
    if (!object) return reply(404);
    if (object.size > MAX_BYTES) return reply(502);
    return new Response(object.body, { headers: { ...headers, 'Content-Type': 'application/octet-stream', 'Content-Length': String(object.size) } });
  }
  const length = Number(request.headers.get('Content-Length'));
  if (!Number.isSafeInteger(length) || length < 1 || length > MAX_BYTES) return reply(413);
  if (!request.body) return reply(400);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) break;
    size += next.value.length;
    if (size > MAX_BYTES || size > length) { await reader.cancel(); return reply(413); }
    chunks.push(next.value);
  }
  if (size !== length) return reply(400);
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const created = await env.IMAGES_PRIVATE_BUCKET.put(storageKey, bytes, {
    onlyIf: { etagDoesNotMatch: '*' }, httpMetadata: { contentType: 'application/octet-stream' },
    customMetadata: { purpose: 'ticket-batch' },
  });
  return reply(created ? 201 : 409);
}
