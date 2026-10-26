import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { remoteR2Transport } from '../lib/remote-r2.js';
import { copyVerifiedAsset } from '../lib/verified-copy.js';
import { createHash } from 'node:crypto';

test('remote copy preserves immutable bytes, MIME and conditional create; resume verifies again', async () => {
  let stored, writes = 0, reads = 0;
  const binding = {
    head: async () => stored ? {} : null,
    get: async () => { reads++; return stored ? { body: new Blob([stored.bytes]).stream(), httpMetadata: stored.options.httpMetadata } : null; },
    put: async (key, bytes, options) => {
      writes++; assert.deepEqual(options.onlyIf, { etagDoesNotMatch: '*' });
      stored = { bytes, options }; return {};
    },
  };
  const transport = remoteR2Transport({ ASSETS_PUBLIC: binding });
  const bytes = Buffer.from('identical file bytes');
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  const asset = { identity: { bucket: 'public-files', key: 'fixture.pdf' }, source: { size: bytes.length, sha256 },
    destination: { bucket: 'festapp-images', key: 'assets/storage/fixture' }, visibility: 'public', contentType: 'application/pdf' };
  const receipts = [];
  const deps = { destination: transport.destination, openSource: async () => ({ stream: Readable.from([bytes]), done: Promise.resolve() }),
    persistReceipt: async r => receipts.push(r) };
  await copyVerifiedAsset(asset, deps);
  await copyVerifiedAsset(asset, deps);
  assert.equal(writes, 1); assert.equal(reads, 2); assert.equal(receipts.length, 2);
  assert.equal(stored.options.customMetadata.sha256, sha256);
  stored.bytes = Buffer.from('conflicting data');
  await assert.rejects(copyVerifiedAsset(asset, deps), /destination_conflict/);
  assert.equal(receipts.length, 2);
});

test('remote adapter refuses source writes, oversized files, partial streams and conflicting create', async () => {
  let writes = 0;
  const transport = remoteR2Transport({ ASSETS_PUBLIC: { put: async () => { writes++; return null; } }, SOURCE_A: {} }, 3);
  const options = { contentLength: 3, contentType: 'application/pdf', sha256: 'a'.repeat(64) };
  await assert.rejects(transport.destination.create('festapp-images-a', 'key', Readable.from(['abc']), options), /source_write_forbidden/);
  await assert.rejects(transport.destination.create('festapp-images', 'key', Readable.from(['abcd']), { ...options, contentLength: 4 }), /memory_bound/);
  await assert.rejects(transport.destination.create('festapp-images', 'key', Readable.from(['a']), options), /source_changed/);
  assert.equal(writes, 0);
  await assert.rejects(transport.destination.create('festapp-images', 'key', Readable.from([Buffer.from('abc')]), options), { code: 'PRECONDITION_FAILED' });
  assert.equal(writes, 1);
});
