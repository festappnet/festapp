import { ClientSyncPublisher } from './publisher.js';
import { R2NativeObjectStore } from './r2_object_store.js';
import { ClientSyncRetention } from './retention.js';
import { SupabasePublisherDatabase } from './supabase_database.js';

export interface Env {
  PUBLIC_SYNC: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  SYNC_ASSET_ORIGIN: string;
  SYNC_SCOPE_IDS: string;
  PUBLISHER_WAKE_TOKEN: string;
  SYNC_RETENTION_APPLY: string;
  SYNC_ARTIFACT_RETENTION_DAYS: string;
  SYNC_RECEIPT_RETENTION_DAYS: string;
}

const PUBLICATION_TICK_PATH = '/v1/internal/publication-tick';
const MAX_BODY_BYTES = 256;

function scopeIds(value: string): number[] {
  const parsed = value.split(',').map((item) => Number(item.trim()));
  if (!parsed.length || parsed.some((item) => !Number.isSafeInteger(item) || item <= 0)) {
    throw new Error('SYNC_SCOPE_IDS must contain positive integer IDs');
  }
  return parsed;
}

export function createWorkerPublisher(env: Env): ClientSyncPublisher {
  return new ClientSyncPublisher(
    new SupabasePublisherDatabase(
      env.SUPABASE_URL,
      env.SUPABASE_SERVICE_ROLE_KEY,
      scopeIds(env.SYNC_SCOPE_IDS),
    ),
    new R2NativeObjectStore(env.PUBLIC_SYNC),
    env.SYNC_ASSET_ORIGIN,
  );
}

export function createWorkerRetention(env: Env): ClientSyncRetention {
  const database = new SupabasePublisherDatabase(
    env.SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY,
    scopeIds(env.SYNC_SCOPE_IDS),
  );
  return new ClientSyncRetention(
    database,
    new R2NativeObjectStore(env.PUBLIC_SYNC),
    Number(env.SYNC_ARTIFACT_RETENTION_DAYS),
    Number(env.SYNC_RECEIPT_RETENTION_DAYS),
    () => new Date(),
  );
}

async function tokenMatches(actual: string | null, expected: string): Promise<boolean> {
  if (!actual?.startsWith('Bearer ') || !expected) return false;
  const encoder = new TextEncoder();
  const [actualHash, expectedHash] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(actual.slice(7))),
    crypto.subtle.digest('SHA-256', encoder.encode(expected)),
  ]);
  const left = new Uint8Array(actualHash);
  const right = new Uint8Array(expectedHash);
  let difference = left.length ^ right.length;
  for (let index = 0; index < Math.max(left.length, right.length); index++) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}

async function readBoundedBody(request: Request): Promise<string> {
  if (!request.body) return '';
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > MAX_BODY_BYTES) {
      await reader.cancel();
      throw new RangeError('body_too_large');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

export async function handlePublicationTick(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname !== PUBLICATION_TICK_PATH) {
    return Response.json({ code: 'not_found' }, { status: 404 });
  }
  if (request.method !== 'POST') {
    return Response.json({ code: 'method_not_allowed' }, { status: 405, headers: { Allow: 'POST' } });
  }
  if (!(await tokenMatches(request.headers.get('Authorization'), env.PUBLISHER_WAKE_TOKEN))) {
    return Response.json({ code: 'unauthorized' }, { status: 401 });
  }
  const declaredLength = Number(request.headers.get('Content-Length') ?? 0);
  if (!Number.isFinite(declaredLength) || declaredLength > MAX_BODY_BYTES) {
    return Response.json({ code: 'body_too_large' }, { status: 413 });
  }
  let body: string;
  try {
    body = await readBoundedBody(request);
  } catch (error) {
    if (!(error instanceof RangeError)) throw error;
    return Response.json({ code: 'body_too_large' }, { status: 413 });
  }
  if (body.trim() && body.trim() !== '{}') {
    return Response.json({ code: 'body_not_allowed' }, { status: 400 });
  }
  const startedAt = Date.now();
  const correlationId = crypto.randomUUID();
  const publishedScopes = await createWorkerPublisher(env).runOnce();
  return Response.json({
    status: 'ok',
    elapsedMs: Date.now() - startedAt,
    publishedScopes,
    correlationId,
  });
}

export default {
  fetch: handlePublicationTick,
  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    if (controller.cron === '17 3 * * *') {
      const result = await createWorkerRetention(env).runOnce({
        apply: env.SYNC_RETENTION_APPLY === 'true',
      });
      console.info(JSON.stringify({ event: 'client_sync_retention', ...result }));
      return;
    }
    try {
      const publishedScopes = await createWorkerPublisher(env).runOnce();
      console.info(JSON.stringify({ event: 'client_sync_publish', publishedScopes }));
    } catch (error) {
      const errors = error instanceof AggregateError ? error.errors : [error];
      console.error(JSON.stringify({
        event: 'client_sync_publish_failed',
        errors: errors.map((item) => item instanceof Error ? item.message : String(item)),
      }));
      throw error;
    }
  },
} satisfies ExportedHandler<Env>;
