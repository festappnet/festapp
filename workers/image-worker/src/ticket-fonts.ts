import {readPreparedFont} from '../../../supabase/functions/_shared/ticketPreparedFont';
import type { Env } from './types';
import { equalServiceSecret } from './service-auth';

const MAX_BYTES = 8 * 1024 * 1024;
const KEY = /^sha256\/([a-f0-9]{64})\.(ttf|woff|metrics-v1\.json)$/;

/** Dedicated server-to-server capability: immutable font read/create only.
 * No browser/User JWT, list, delete, arbitrary key or public bucket access.
 * Replays cannot overwrite a winner, including after a lost PUT response.
 */
export async function handleTicketFonts(request: Request, env: Env): Promise<Response> {
  const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
  const reply = (status: number) => new Response(null, { status, headers });
  const uri = new URL(request.url);
  if (uri.hostname !== 'image-api.festapp.net' || uri.search || uri.hash) return reply(404);
  const secret = env.TICKET_FONT_SERVICE_SECRET;
  const auth = request.headers.get('Authorization') ?? '';
  if (!secret || secret.length < 32) return reply(503);
  if (!auth.startsWith('Bearer ') || auth.length > 512 || !await equalServiceSecret(auth.slice(7), secret)) return reply(401);
  if (!['GET', 'PUT'].includes(request.method)) return reply(405);
  const key = uri.pathname.slice('/service/ticket-fonts/'.length);
  const match = KEY.exec(key);
  if (!match) return reply(400);
  const storageKey = `ticket-fonts/${key}`;
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
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
  if(match[2]==='metrics-v1.json'){
    try {await readPreparedFont(bytes,match[1]);}catch{return reply(422);}
    // A sidecar can only attest an already published immutable font.
    const font=await env.IMAGES_PRIVATE_BUCKET.head(`ticket-fonts/sha256/${match[1]}.ttf`)
      ??await env.IMAGES_PRIVATE_BUCKET.head(`ticket-fonts/sha256/${match[1]}.woff`);
    if(!font)return reply(409);
  }else if (hash !== match[1]) return reply(422);
  const created = await env.IMAGES_PRIVATE_BUCKET.put(storageKey, bytes, {
    onlyIf: { etagDoesNotMatch: '*' },
    httpMetadata: { contentType: 'application/octet-stream' },
    customMetadata: { sha256: hash, purpose: 'ticket-font' },
  });
  return reply(created ? 201 : 409);
}
