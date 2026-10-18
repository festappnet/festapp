import { Readable } from 'node:stream';

// The authenticated remote bindings are an operational transport, not an
// application service or a deployed route. Only this adapter can write, and
// only to the canonical pair. Workerd receives at most one bounded object;
// source streaming/hashing and durable receipts remain owned by verified-copy.
export function remoteR2Transport(bindings, maxObjectBytes = 64 * 1024 * 1024) {
  const names = {
    'festapp-images': 'ASSETS_PUBLIC',
    'festapp-images-private': 'ASSETS_PRIVATE',
    'festapp-images-a': 'SOURCE_A',
    'festapp-images-a-private': 'SOURCE_A_PRIVATE',
  };
  const bucket = name => {
    if (!Object.hasOwn(names, name) || !bindings[names[name]]) throw new Error('unexpected_r2_bucket');
    return bindings[names[name]];
  };
  const read = async (name, key) => {
    const object = await bucket(name).get(key);
    return object ? { stream: Readable.fromWeb(object.body), contentType: object.httpMetadata?.contentType } : null;
  };
  return {
    read,
    destination: {
      exists: async (name, key) => (await bucket(name).head(key)) !== null,
      read,
      async create(name, key, body, options) {
        if (!['festapp-images', 'festapp-images-private'].includes(name)) throw new Error('source_write_forbidden');
        if (!Number.isSafeInteger(options.contentLength) || options.contentLength < 0 || options.contentLength > maxObjectBytes) {
          throw new Error('remote_object_memory_bound');
        }
        const chunks = [];
        let size = 0;
        for await (const chunk of body) {
          size += chunk.length;
          if (size > options.contentLength) throw new Error('source_changed');
          chunks.push(chunk);
        }
        if (size !== options.contentLength) throw new Error('source_changed');
        // Passing bytes gives R2 an exact known length. Never use an unbounded
        // stream workaround or an unconditional retry on this boundary.
        const result = await bucket(name).put(key, Buffer.concat(chunks, size), {
          onlyIf: { etagDoesNotMatch: '*' },
          httpMetadata: { contentType: options.contentType },
          customMetadata: { sha256: options.sha256 },
        });
        if (result === null) throw Object.assign(new Error('conditional_create_conflict'), { code: 'PRECONDITION_FAILED' });
      },
    },
  };
}
