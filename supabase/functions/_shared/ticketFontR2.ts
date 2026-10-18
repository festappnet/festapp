import { TicketFontError, type FontStore } from './ticketFonts.ts';

const ENDPOINT = 'https://image-api.festapp.net/service/ticket-fonts/';
const MAX_BYTES = 8 * 1024 * 1024;

/** Transport only. Font IDs, catalog metadata and validation stay in resolver. */
export function createTicketFontR2Store(secret: () => string | undefined, request: typeof fetch = fetch): FontStore {
  async function send(key: string, bytes?: Uint8Array): Promise<Response> {
    if (!/^sha256\/[a-f0-9]{64}\.(ttf|woff)$/.test(key)) throw new TicketFontError('font_storage_key');
    const token = secret();
    if (!token || token.length < 32) throw new TicketFontError('font_storage_config');
    const headers: Record<string, string> = { Authorization: `Bearer ${token}` };
    if (bytes) {
      if (bytes.length < 1 || bytes.length > MAX_BYTES) throw new TicketFontError('font_size');
      headers['Content-Type'] = 'application/octet-stream';
      headers['Content-Length'] = String(bytes.length);
    }
    return request(ENDPOINT + key, {
      method: bytes ? 'PUT' : 'GET', headers,
      body: bytes ? new Uint8Array(bytes).buffer : undefined,
      redirect: 'error', signal: AbortSignal.timeout(15000),
    });
  }
  return {
    async read(key) {
      const response = await send(key);
      if (response.status === 404) return null;
      if (!response.ok || !response.body) throw new TicketFontError('font_storage_read');
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      while (true) {
        const next = await reader.read();
        if (next.done) break;
        size += next.value.length;
        if (size > MAX_BYTES) { await reader.cancel(); throw new TicketFontError('font_size'); }
        chunks.push(next.value);
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      return bytes;
    },
    async create(key, bytes) {
      const response = await send(key, bytes);
      if (response.status === 409) return false;
      if (response.status !== 201) throw new TicketFontError('font_storage_write');
      return true;
    },
  };
}
