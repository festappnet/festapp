import type { ObjectStore } from './publisher.js';

type Head = { catalog?: { revision?: number }; live?: { revision?: number } };

function decode(bytes: ArrayBuffer | Uint8Array): Head {
  return JSON.parse(new TextDecoder().decode(bytes)) as Head;
}

function revisions(head: Head): [number, number] {
  return [Number(head.catalog?.revision ?? -1), Number(head.live?.revision ?? -1)];
}

export class R2NativeObjectStore implements ObjectStore {
  constructor(private readonly bucket: R2Bucket) {}

  async putImmutable(key: string, bytes: Uint8Array, contentType: string): Promise<void> {
    const existing = await this.bucket.head(key);
    if (existing) {
      if (existing.size !== bytes.byteLength) throw new Error(`immutable key collision: ${key}`);
      return;
    }

    const stored = await this.bucket.put(key, bytes, {
      onlyIf: { etagDoesNotMatch: '*' },
      httpMetadata: {
        contentType,
        cacheControl: 'public, max-age=31536000, immutable',
      },
    });
    const verified = stored ?? await this.bucket.head(key);
    if (!verified || verified.size !== bytes.byteLength) throw new Error(`R2 verification failed: ${key}`);
  }

  async putHead(key: string, bytes: Uint8Array): Promise<{ etag: string; head: unknown }> {
    const next = decode(bytes);
    const current = await this.bucket.get(key);
    if (current) {
      const old = decode(await current.arrayBuffer());
      const [oldCatalog, oldLive] = revisions(old);
      const [newCatalog, newLive] = revisions(next);
      if (oldCatalog === newCatalog && oldLive === newLive) {
        return { etag: current.httpEtag, head: old };
      }
      if (newCatalog < oldCatalog || newLive < oldLive) throw new Error('refusing stale R2 head');
    }

    const stored = await this.bucket.put(key, bytes, {
      onlyIf: current ? { etagMatches: current.etag } : { etagDoesNotMatch: '*' },
      httpMetadata: {
        contentType: 'application/json',
        cacheControl: 'public, max-age=0, must-revalidate',
      },
    });
    if (stored) return { etag: stored.httpEtag, head: next };

    const winner = await this.bucket.get(key);
    if (!winner) throw new Error('R2 conditional head write failed without a winner');
    const accepted = decode(await winner.arrayBuffer());
    const [acceptedCatalog, acceptedLive] = revisions(accepted);
    const [newCatalog, newLive] = revisions(next);
    if (acceptedCatalog < newCatalog || acceptedLive < newLive) {
      throw new Error('R2 concurrent head did not include the pending revisions');
    }
    return { etag: winner.httpEtag, head: accepted };
  }

  async exists(key: string): Promise<boolean> {
    return (await this.bucket.head(key)) !== null;
  }

  async deleteExact(key: string): Promise<void> {
    await this.bucket.delete(key);
  }
}
