import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { digest, type ObjectStore } from './publisher.js';

export class R2S3ObjectStore implements ObjectStore {
  constructor(private readonly client: S3Client, private readonly bucket: string) {}

  async putImmutable(key: string, bytes: Uint8Array, contentType: string): Promise<void> {
    try {
      const existing = await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      if (existing.ContentLength !== bytes.byteLength) throw new Error(`immutable key collision: ${key}`);
      return;
    } catch (error) {
      if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode !== 404) throw error;
    }
    await this.client.send(new PutObjectCommand({ Bucket: this.bucket, Key: key, Body: bytes, ContentType: contentType, CacheControl: 'public, max-age=31536000, immutable' }));
    const verified = await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
    if (verified.ContentLength !== bytes.byteLength) throw new Error(`R2 verification failed: ${key}`);
  }

  async putHead(key: string, bytes: Uint8Array, expectedPreviousEtag?: string): Promise<{ etag: string; head: unknown }> {
    const next = JSON.parse(new TextDecoder().decode(bytes)) as { catalog?: { revision?: number }; live?: { revision?: number } };
    let previousEtag = expectedPreviousEtag;
    try {
      const current = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
      previousEtag = current.ETag;
      const currentBytes = new Uint8Array(await current.Body!.transformToByteArray());
      const old = JSON.parse(new TextDecoder().decode(currentBytes)) as typeof next;
      const oldCatalog = Number(old.catalog?.revision ?? -1), newCatalog = Number(next.catalog?.revision ?? -1);
      const oldLive = Number(old.live?.revision ?? -1), newLive = Number(next.live?.revision ?? -1);
      if (newCatalog === oldCatalog && newLive === oldLive) {
        return { etag: current.ETag ?? `"${await digest(currentBytes)}"`, head: old };
      }
      if (newCatalog < oldCatalog || newLive < oldLive) throw new Error('refusing stale R2 head');
    } catch (error) {
      const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode;
      if (status !== 404) throw error;
    }
    await this.client.send(new PutObjectCommand({ Bucket: this.bucket, Key: key, Body: bytes, ContentType: 'application/json', CacheControl: 'public, max-age=0, must-revalidate', ...(previousEtag ? { IfMatch: previousEtag } : { IfNoneMatch: '*' }) }));
    const verified = await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
    return { etag: verified.ETag ?? `"${await digest(bytes)}"`, head: next };
  }

  async exists(key: string): Promise<boolean> {
    try {
      await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return true;
    } catch (error) {
      if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode === 404) return false;
      throw error;
    }
  }

  async deleteExact(key: string): Promise<void> {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }
}
