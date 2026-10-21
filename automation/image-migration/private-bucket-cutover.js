#!/usr/bin/env node

import { appendFile, readFile } from 'node:fs/promises';
import { config } from 'dotenv';
import {
  CopyObjectCommand,
  DeleteObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
} from '@aws-sdk/client-s3';
import { createR2Client } from './lib/r2-client.js';

config();

const args = new Set(process.argv.slice(2));
const mode = ['--inventory', '--copy', '--verify', '--delete'].find((flag) => args.has(flag));
const source = process.env.R2_PUBLIC_BUCKET_NAME;
const destination = process.env.R2_PRIVATE_BUCKET_NAME;
const ledgerPath = process.env.PRIVATE_CUTOVER_LEDGER || '.private-cutover-ledger.jsonl';
const batchSize = Math.min(Number(process.env.PRIVATE_CUTOVER_BATCH_SIZE || 100), 500);

if (!mode || !source || !destination || source === destination) {
  throw new Error('Choose one mode and distinct R2_PUBLIC_BUCKET_NAME/R2_PRIVATE_BUCKET_NAME values');
}
if (mode === '--delete' && !args.has('--confirm-source-delete')) {
  throw new Error('Source deletion requires --confirm-source-delete after a clean --verify run');
}

const r2 = createR2Client(process.env);

async function listPrivateKeys() {
  const keys = [];
  let token;
  do {
    const page = await r2.send(new ListObjectsV2Command({
      Bucket: source, Prefix: 'private/', ContinuationToken: token, MaxKeys: batchSize,
    }));
    for (const object of page.Contents || []) {
      keys.push({ key: object.Key, size: object.Size, etag: object.ETag });
    }
    token = page.NextContinuationToken;
  } while (token);
  return keys;
}

async function ledger() {
  try {
    return new Set((await readFile(ledgerPath, 'utf8')).trim().split('\n').filter(Boolean)
      .map((line) => JSON.parse(line)).filter((item) => item.status === 'verified').map((item) => item.key));
  } catch (error) {
    if (error.code === 'ENOENT') return new Set();
    throw error;
  }
}

async function verify(key, expectedSize) {
  const head = await r2.send(new HeadObjectCommand({ Bucket: destination, Key: key }));
  return head.ContentLength === expectedSize;
}

const objects = await listPrivateKeys();
if (mode === '--inventory') {
  console.log(JSON.stringify({ source, destination, count: objects.length,
    bytes: objects.reduce((sum, item) => sum + (item.size || 0), 0) }));
  process.exit(0);
}

const completed = await ledger();
let verified = 0;
for (const object of objects) {
  if (!object.key) continue;
  if (mode === '--copy' && !completed.has(object.key)) {
    await r2.send(new CopyObjectCommand({
      Bucket: destination,
      Key: object.key,
      CopySource: `${source}/${encodeURIComponent(object.key).replaceAll('%2F', '/')}`,
    }));
  }
  if (!await verify(object.key, object.size)) {
    throw new Error(`Parity failed for a private object; source retained`);
  }
  verified++;
  if (!completed.has(object.key)) {
    await appendFile(ledgerPath, `${JSON.stringify({ key: object.key, size: object.size, etag: object.etag, status: 'verified' })}\n`);
  }
  if (mode === '--delete') {
    await r2.send(new DeleteObjectCommand({ Bucket: source, Key: object.key }));
  }
}

console.log(JSON.stringify({ mode, source, destination, verified, sourceDeleted: mode === '--delete' }));
