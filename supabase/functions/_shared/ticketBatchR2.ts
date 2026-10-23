import type { BatchObjectStore } from './ticketBatchDocuments.ts';
const MAX_BYTES = 16 * 1024 * 1024;
/** Private R2 transport. SQL owns access, manifests and fencing. */
export function createTicketBatchR2Store(secret: () => string | undefined, request: typeof fetch = fetch,
  endpoint = 'https://image-api.festapp.net/service/ticket-batches/'): BatchObjectStore {
  const target = new URL(endpoint);
  if ((target.protocol !== 'https:' && !(target.protocol === 'http:' && ['127.0.0.1', 'localhost', 'host.docker.internal'].includes(target.hostname))) || target.username || target.password || target.search || target.hash || !target.pathname.endsWith('/service/ticket-batches/')) throw new Error('batch_storage_config');
  async function send(key: string, bytes?: Uint8Array) {
    if (!/^[a-f0-9-]{36}\/(?:resources\/[a-f0-9]{64}|[a-f0-9]{64}\/(?:single|print)-[0-9]{3}\.pdf)$/.test(key)) throw new Error('batch_storage_key');
    const token = secret();
    if (!token || token.length < 32) throw new Error('batch_storage_config');
    if (bytes && (!bytes.length || bytes.length > MAX_BYTES)) throw new Error('batch_storage_limit');
    return request(target.href + key, { method: bytes ? 'PUT' : 'GET',
      headers: { Authorization: `Bearer ${token}`, ...(bytes ? { 'Content-Length': String(bytes.length), 'Content-Type': 'application/octet-stream' } : {}) },
      body: bytes ? new Uint8Array(bytes).buffer : undefined, redirect: 'error', signal: AbortSignal.timeout(20000) });
  }
  return {
    async read(key) {
      const response = await send(key);
      if (response.status === 404) return null;
      if (!response.ok || !response.body) throw new Error('batch_storage_read');
      const reader = response.body.getReader(), chunks: Uint8Array[] = [];let size = 0;
      while (true) { const next = await reader.read(); if (next.done) break;
        size += next.value.length; if (size > MAX_BYTES) { await reader.cancel(); throw new Error('batch_storage_limit'); } chunks.push(next.value); }
      const bytes = new Uint8Array(size);let offset = 0;for (const chunk of chunks) { bytes.set(chunk, offset);offset += chunk.length; }return bytes;
    },
    async create(key, bytes) { const response = await send(key, bytes); if (![201, 409].includes(response.status)) throw new Error('batch_storage_write'); },
  };
}
