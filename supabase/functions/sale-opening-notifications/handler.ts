import { saleOpeningProtection } from './protection.ts';
import { emailPayloadHash, sealEmail } from '../_shared/emailPayload.ts';

export const saleOpeningHash = emailPayloadHash;
const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
};
const response = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers });
type Rpc = (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: { code?: string } | null }>;
export function saleOpeningHandler(rpc: Rpc, seal = sealEmail, protection = saleOpeningProtection()) {
  return async (request: Request): Promise<Response> => {
    if (request.method === 'OPTIONS') return new Response('ok', { headers });
    if (request.method !== 'POST') return response({ error: 'method_not_allowed' }, 405);
    try {
      // Bound streaming input as well as Content-Length; never log the body.
      const reader = request.body?.getReader();
      if (!reader) return response({ error: 'invalid_request' }, 400);
      let size = 0; const parts: Uint8Array[] = [];
      while (true) {
        const { done, value } = await reader.read(); if (done) break;
        size += value.length;
        if (size > 4096) { await reader.cancel(); return response({ error: 'request_too_large' }, 413); }
        parts.push(value);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const part of parts) { bytes.set(part, offset); offset += part.length; }
      const body = JSON.parse(new TextDecoder().decode(bytes));
      const { operation } = body;
      const payload: Record<string, unknown> = {};
      if (operation === 'protection') {
        return response({ok:true, ...protection.publicConfig()});
      }
      if (operation === 'subscribe') {
        if (typeof body.formLink !== 'string' || body.formLink.length > 256 || typeof body.email !== 'string' ||
          body.email.length > 320 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email.trim()) ||
          !['cs','en','de','sk','pl','uk'].includes(body.lang)) return response({ error: 'invalid_contact' }, 400);
        if (!await protection.verify(body.botToken, body.formLink, body.email)) return response({error:'verification_failed'}, 400);
        Object.assign(payload, { formLink: body.formLink, email: body.email, lang: body.lang });
        for (const purpose of ['unsubscribe']) {
          const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('');
          payload[purpose] = { hash: await saleOpeningHash(token), envelope: await seal({ token }) };
        }
      } else if (operation === 'unsubscribe' && typeof body.token === 'string' && /^[0-9a-f]{64}$/.test(body.token)) {
        payload.tokenHash = await saleOpeningHash(body.token);
      } else return response({ error: 'invalid_action' }, 400);
      const result = await rpc('sale_opening_notification_command', { p_operation: operation, p_payload: payload });
      if (result.error) return response({ error: result.error.code === 'PT429' ? 'try_later' : result.error.code === '22023' && operation !== 'subscribe' ? 'invalid_link' : 'action_unavailable' }, result.error.code === 'PT429' ? 429 : 400);
      // Collection never creates mail. Do not let anonymous requests wake the
      // shared worker; maintenance owns launch admission and queue dispatch.
      return response(result.data);
    } catch { return response({ error: 'request_failed' }, 503); }
  };
}
