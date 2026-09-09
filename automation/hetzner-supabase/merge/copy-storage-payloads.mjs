#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { Readable, Transform } from 'node:stream';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  SOURCES,
  accessToken,
  assertPrivateOutput,
  sourceAliasUsage,
} from './lib.mjs';

const CONCURRENCY = 4;
const RECEIVER = '/tmp/festapp-storage-file-receiver.cjs';
const RECEIVER_SOURCE = fileURLToPath(new URL('../rehearsal/storage-file-receiver.cjs', import.meta.url));
const EXPECTED_TARGET = 'root@46.224.187.4';

function fail(message) { throw new Error(message); }

async function sha256File(file) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { ...options, stdio: options.stdio ?? ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout?.on('data', (chunk) => { stdout += chunk; });
    child.stderr?.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => code === 0 ? resolve(stdout) : reject(new Error(
      `${command} failed (${code}): ${stderr.slice(0, 1200)}`,
    )));
  });
}

async function readSnapshot(artifact, identity, alias, manifest) {
  const decrypt = spawn('age', ['--decrypt', '--identity', identity, artifact], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let decryptError = '';
  decrypt.stderr.on('data', (chunk) => { decryptError += chunk; });
  const decryptCompletion = new Promise((resolve, reject) => {
    decrypt.on('error', reject);
    decrypt.on('close', resolve);
  });
  const objects = [];
  let header;
  let completed = false;
  const lines = readline.createInterface({ input: decrypt.stdout, crlfDelay: Infinity });
  for await (const line of lines) {
    const value = JSON.parse(line);
    if (value.kind === 'festapp-managed-schema-export') header = value;
    if (value.kind === 'row' && value.schema_name === 'storage' && value.table_name === 'objects') {
      objects.push(value.row);
    }
    if (value.kind === 'complete') completed = true;
  }
  const code = await decryptCompletion;
  if (code !== 0) fail(`age decryption failed: ${decryptError.slice(0, 1200)}`);
  if (!completed || header?.source_alias !== alias || header?.project_ref !== SOURCES[alias]) {
    fail('managed snapshot identity or completion mismatch');
  }
  const expected = manifest.tables.find((table) =>
    table.schema_name === 'storage' && table.table_name === 'objects')?.rows;
  if (objects.length !== expected) fail(`Storage object count mismatch: ${objects.length}/${expected}`);
  return objects;
}

function validateObject(row) {
  const metadata = row.metadata ?? {};
  const expectedSize = Number(metadata.size ?? metadata.contentLength);
  if (![row.bucket_id, row.name, row.version].every((value) => typeof value === 'string' && value)) {
    fail('Storage object is missing bucket, name or version');
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/.test(row.bucket_id) ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(row.version) ||
      row.name.includes('\\') || row.name.includes('\0') ||
      row.name.split('/').some((part) => !part || part === '.' || part === '..')) {
    fail('Storage snapshot contains an unsafe object path');
  }
  if (!Number.isSafeInteger(expectedSize) || expectedSize < 0) fail('Storage object has invalid size');
  return {
    bucket: row.bucket_id,
    name: row.name,
    version: row.version,
    mimetype: metadata.mimetype || 'application/octet-stream',
    cacheControl: metadata.cacheControl || 'no-cache',
    expectedSize,
    expectedMd5: /^"?[0-9a-f]{32}"?$/i.test(metadata.eTag ?? '')
      ? metadata.eTag.replaceAll('"', '').toLowerCase() : null,
  };
}

async function installAndVerifyReceiver(target) {
  const expected = await sha256File(RECEIVER_SOURCE);
  const child = spawn('ssh', ['-o', 'BatchMode=yes', target,
    `docker exec -i supabase-storage sh -c 'umask 077; dd of=${RECEIVER} status=none; sha256sum ${RECEIVER}'`],
  { stdio: ['pipe', 'pipe', 'pipe'] });
  child.stdin.end(fs.readFileSync(RECEIVER_SOURCE));
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const code = await new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('close', resolve);
  });
  if (code !== 0 || stdout.trim().split(/\s+/)[0] !== expected) {
    fail(`target Storage receiver installation/hash failed: ${stderr.slice(0, 800)}`);
  }
  return expected;
}

async function serviceRoleKey(projectRef, token) {
  const response = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/api-keys?reveal=true`, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (!response.ok) fail(`service-key lookup failed: HTTP ${response.status}`);
  const keys = await response.json();
  const migrationKeys = keys.filter((entry) => entry.type === 'secret' &&
    entry.name?.startsWith('festapp_cutover_export_'));
  if (migrationKeys.length > 1) fail('multiple cutover Storage export keys are active');
  const key = migrationKeys[0]?.api_key ?? keys.find((entry) => entry.name === 'service_role')?.api_key;
  if (!key) fail('source Storage read key is unavailable');
  return key;
}

async function copyObject({ object, projectRef, serviceKey, target }) {
  const sourcePath = [object.bucket, ...object.name.split('/')].map(encodeURIComponent).join('/');
  const response = await fetch(`https://${projectRef}.supabase.co/storage/v1/object/${sourcePath}`, {
    headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` },
  });
  if (!response.ok || !response.body) fail(`source Storage download failed: HTTP ${response.status}`);

  const descriptor = Buffer.from(JSON.stringify(object)).toString('base64url');
  const receiver = spawn('ssh', ['-o', 'BatchMode=yes', target,
    `docker exec -i -e FESTAPP_STORAGE_DESCRIPTOR=${descriptor} supabase-storage node ${RECEIVER}`], {
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const sha256 = crypto.createHash('sha256');
  const md5 = crypto.createHash('md5');
  let bytes = 0;
  const meter = new Transform({
    transform(chunk, _encoding, callback) {
      bytes += chunk.length;
      sha256.update(chunk);
      md5.update(chunk);
      callback(null, chunk);
    },
  });
  let stdout = '';
  let stderr = '';
  receiver.stdout.on('data', (chunk) => { stdout += chunk; });
  receiver.stderr.on('data', (chunk) => { stderr += chunk; });
  const receiverCompletion = new Promise((resolve, reject) => {
    receiver.on('error', reject);
    receiver.on('close', resolve);
  });
  Readable.fromWeb(response.body).pipe(meter).pipe(receiver.stdin);
  const code = await receiverCompletion;
  if (code !== 0) fail(`target Storage receiver failed: ${stderr.slice(0, 1200)}`);
  const localSha256 = sha256.digest('hex');
  const localMd5 = md5.digest('hex');
  const stored = JSON.parse(stdout.trim());
  if (bytes !== object.expectedSize || stored.bytes !== object.expectedSize || stored.sha256 !== localSha256) {
    fail(`Storage payload verification failed for one object (${bytes}/${stored.bytes}/${object.expectedSize})`);
  }
  if (object.expectedMd5 && (localMd5 !== object.expectedMd5 || stored.md5 !== object.expectedMd5)) {
    fail('Storage payload MD5 differs from snapshot metadata');
  }
  if (stored.mimetype !== object.mimetype || stored.cacheControl !== object.cacheControl) {
    fail('Storage file metadata differs from snapshot metadata');
  }
  return { bytes, sha256: localSha256, resumed: stored.existed === true };
}

async function mapLimit(values, limit, fn) {
  const results = new Array(values.length);
  let next = 0;
  async function worker() {
    while (true) {
      const index = next++;
      if (index >= values.length) return;
      results[index] = await fn(values[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, values.length) }, worker));
  return results;
}

async function main() {
  const [alias, requestedArtifact, identity, target = EXPECTED_TARGET, requestedEvidence] = process.argv.slice(2);
  if (!Object.hasOwn(SOURCES, alias) || !requestedArtifact || !identity || !requestedEvidence) {
    fail(`usage: copy-storage-payloads.mjs ${sourceAliasUsage()} ARTIFACT.age SSH_IDENTITY [${EXPECTED_TARGET}] PRIVATE_EVIDENCE.json`);
  }
  if (target !== EXPECTED_TARGET) fail('target must be the approved rehearsal host');
  const artifact = path.resolve(requestedArtifact);
  const evidence = assertPrivateOutput(requestedEvidence);
  const manifestPath = `${artifact}.manifest.json`;
  if (fs.existsSync(evidence)) fail('refusing to overwrite Storage evidence');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (manifest.source?.alias !== alias || manifest.source?.project_ref !== SOURCES[alias]) {
    fail('Storage artifact manifest identity mismatch');
  }
  const artifactSha256 = await sha256File(artifact);
  const manifestFileSha256 = await sha256File(manifestPath);
  if (artifactSha256 !== manifest.artifact?.sha256) fail('Storage artifact checksum mismatch');
  const receiverSha256 = await installAndVerifyReceiver(target);

  const rows = await readSnapshot(artifact, identity, alias, manifest);
  const objects = rows.map(validateObject);
  const descriptorKeys = new Set(objects.map((object) => `${object.bucket}\0${object.name}\0${object.version}`));
  if (descriptorKeys.size !== objects.length) fail('managed Storage artifact contains duplicate object descriptors');
  const descriptorAggregate = crypto.createHash('sha256');
  for (const object of objects) descriptorAggregate.update(`${JSON.stringify(object)}\n`);
  const token = accessToken();
  const serviceKey = await serviceRoleKey(SOURCES[alias], token);
  const startedAt = new Date().toISOString();
  let completed = 0;
  const results = await mapLimit(objects, CONCURRENCY, async (object) => {
    const result = await copyObject({ object, projectRef: SOURCES[alias], serviceKey, target });
    completed += 1;
    if (completed % 25 === 0 || completed === objects.length) {
      process.stdout.write(`${alias} Storage payloads: ${completed}/${objects.length}\n`);
    }
    return result;
  });
  const aggregate = crypto.createHash('sha256');
  for (const result of results) aggregate.update(`${result.sha256}\n`);
  const output = {
    kind: 'festapp-storage-payload-rehearsal-copy',
    source: { alias, project_ref: SOURCES[alias] },
    target,
    started_at: startedAt,
    completed_at: new Date().toISOString(),
    objects: results.length,
    bytes: results.reduce((sum, item) => sum + item.bytes, 0),
    resumed_objects: results.filter((item) => item.resumed).length,
    ordered_payload_sha256: aggregate.digest('hex'),
    ordered_descriptor_sha256: descriptorAggregate.digest('hex'),
    source_artifact_sha256: artifactSha256,
    source_manifest_file_sha256: manifestFileSha256,
    source_manifest_sha256: manifest.manifest_sha256,
    receiver_sha256: receiverSha256,
    cloud_source_mutated: false,
    cloudflare_in_path: false,
  };
  fs.writeFileSync(evidence, `${JSON.stringify(output, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write(`${alias} Storage copy complete: objects=${output.objects} bytes=${output.bytes}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
