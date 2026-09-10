'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const { FileBackend } = require('/app/dist/storage/backend/file.js');
const { withOptionalVersion } = require('/app/dist/storage/backend/adapter.js');

function fail(message) {
  process.stderr.write(`${message}\n`, () => process.exit(1));
}

async function digest(file) {
  const sha256 = crypto.createHash('sha256');
  const md5 = crypto.createHash('md5');
  let bytes = 0;
  for await (const chunk of fs.createReadStream(file)) {
    bytes += chunk.length;
    sha256.update(chunk);
    md5.update(chunk);
  }
  return { bytes, sha256: sha256.digest('hex'), md5: md5.digest('hex') };
}

async function main() {
  const encoded = process.env.FESTAPP_STORAGE_DESCRIPTOR;
  if (!encoded || !/^[A-Za-z0-9_-]+$/.test(encoded)) throw new Error('invalid storage descriptor');
  const descriptor = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
  const { bucket, name, version, mimetype, cacheControl, expectedSize } = descriptor;
  if (![bucket, name, version, mimetype, cacheControl].every((value) => typeof value === 'string') ||
      !Number.isSafeInteger(expectedSize) || expectedSize < 0 ||
      !/^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/.test(bucket) ||
      !/^[0-9a-f-]{36}$/i.test(version) || !name || name.includes('\\') || name.includes('\0') ||
      name.split('/').some((part) => !part || part === '.' || part === '..')) {
    throw new Error('invalid storage descriptor fields');
  }
  const backend = new FileBackend();
  const internalBucket = process.env.GLOBAL_S3_BUCKET;
  const tenantId = process.env.TENANT_ID;
  if (!internalBucket || !tenantId) throw new Error('Storage tenant location is unavailable');
  const backendKey = `${tenantId}/${bucket}/${name}`;
  const file = backend.resolveSecurePath(withOptionalVersion(`${internalBucket}/${backendKey}`, version));
  if (!fs.existsSync(file)) throw new Error('target Storage payload is missing');
  const head = await backend.headObject(internalBucket, backendKey, version);
  const hashes = await digest(file);
  if (hashes.bytes !== expectedSize || head.size !== expectedSize) throw new Error('stored size mismatch');
  process.stdout.write(`${JSON.stringify({ ...hashes, existed: true, mimetype: head.mimetype, cacheControl: head.cacheControl })}\n`,
    () => process.exit(0));
}

main().catch((error) => fail(error instanceof Error ? error.message : String(error)));
