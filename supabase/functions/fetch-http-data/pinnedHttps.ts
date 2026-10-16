import { buildConnector, Client } from 'npm:undici@6.29.1';
import { isIP } from 'node:net';

/** Pin the TCP destination without replacing Host, SNI or certificate identity.
 * Each hop has its own client; it cannot borrow another host's pooled socket.
 * The client closes on EOF, error, cancellation and request failure.
 */
export async function fetchPinnedHttps(url: URL, init: RequestInit, address: string): Promise<Response> {
  if (!isIP(address)) throw new TypeError('Expected a vetted IP address');
  const hostname = url.hostname.replace(/^\[|\]$/g, '');
  const connect = buildConnector({ timeout: 15_000, allowH2: false, rejectUnauthorized: true });
  const client = new Client(url.origin, {
    headersTimeout: 15_000, bodyTimeout: 15_000, maxHeaderSize: 32 * 1024,
    connect: (options, callback) => connect({ ...options, hostname: address, servername: hostname }, callback),
  });
  try {
    const upstream = await client.request({
      path: url.pathname + url.search, method: 'GET',
      headers: { 'accept-encoding': 'identity' }, signal: init.signal ?? undefined,
    });
    const headers = new Headers();
    for (const [key, value] of Object.entries(upstream.headers)) {
      if (value !== undefined) headers.set(key, Array.isArray(value) ? value.join(', ') : value);
    }
    if ([204, 205, 304].includes(upstream.statusCode)) {
      await client.destroy();
      return new Response(null, { status: upstream.statusCode, headers });
    }
    const iterator = upstream.body[Symbol.asyncIterator]();
    return new Response(new ReadableStream<Uint8Array>({
      async pull(controller) {
        try {
          const chunk = await iterator.next();
          if (chunk.done) { await client.destroy(); controller.close(); }
          else controller.enqueue(chunk.value);
        } catch (error) { await client.destroy(); controller.error(error); }
      },
      async cancel() { await client.destroy(); },
    }), { status: upstream.statusCode, headers });
  } catch (error) { await client.destroy(); throw error; }
}
