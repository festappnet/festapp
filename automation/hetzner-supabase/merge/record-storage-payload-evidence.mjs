#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { SOURCE_REGISTRY, SOURCES, accessToken, assertPrivateOutput, sourceAliasUsage } from './lib.mjs';

const EXPECTED_TARGET = 'root@46.224.187.4';
const RECEIVER = '/tmp/festapp-storage-file-receiver.cjs';
const RECEIVER_SOURCE = fileURLToPath(new URL('../rehearsal/storage-file-receiver.cjs', import.meta.url));
const VERIFIER = '/tmp/festapp-storage-file-verifier.cjs';
const VERIFIER_SOURCE = fileURLToPath(new URL('../rehearsal/storage-file-verifier.cjs', import.meta.url));
const TARGET_VERIFY_CONCURRENCY = 8;

function fail(message) { throw new Error(message); }

async function sha256File(file) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

function storageDescriptor(row) {
  const metadata = row.metadata ?? {};
  const expectedSize = Number(metadata.size ?? metadata.contentLength);
  if (![row.bucket_id, row.name, row.version].every((value) => typeof value === 'string' && value) ||
      !/^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/.test(row.bucket_id) ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(row.version) ||
      row.name.includes('\\') || row.name.includes('\0') ||
      row.name.split('/').some((part) => !part || part === '.' || part === '..') ||
      !Number.isSafeInteger(expectedSize) || expectedSize < 0) {
    fail('managed Storage descriptor is invalid');
  }
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

async function readManagedDescriptors(alias, artifact, identity, manifest) {
  const decrypt = spawn('age', ['--decrypt', '--identity', identity, artifact], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stderr = '';
  decrypt.stderr.on('data', (chunk) => { stderr += chunk; });
  const completion = once(decrypt, 'close');
  const aggregate = crypto.createHash('sha256');
  let objects = 0;
  let bytes = 0;
  let complete = false;
  let sourceMatched = false;
  const descriptors = [];
  const lines = readline.createInterface({ input: decrypt.stdout, crlfDelay: Infinity });
  for await (const line of lines) {
    const value = JSON.parse(line);
    if (value.kind === 'festapp-managed-schema-export') {
      sourceMatched = value.source_alias === alias && value.project_ref === SOURCES[alias];
    } else if (value.kind === 'row' && value.schema_name === 'storage' && value.table_name === 'objects') {
      const descriptor = storageDescriptor(value.row);
      descriptors.push(descriptor);
      aggregate.update(`${JSON.stringify(descriptor)}\n`);
      objects += 1;
      bytes += descriptor.expectedSize;
    } else if (value.kind === 'complete') {
      complete = true;
    }
  }
  const [code] = await completion;
  if (code !== 0 || !complete || !sourceMatched) fail(`managed artifact verification failed: ${stderr.slice(0, 800)}`);
  const expectedObjects = manifest.tables.find((table) =>
    table.schema_name === 'storage' && table.table_name === 'objects')?.rows;
  if (objects !== expectedObjects) fail('managed Storage descriptor count differs from manifest');
  if (new Set(descriptors.map((descriptor) =>
    `${descriptor.bucket}\0${descriptor.name}\0${descriptor.version}`)).size !== descriptors.length) {
    fail('managed Storage artifact contains duplicate object descriptors');
  }
  return { objects, bytes, descriptors, orderedDescriptorSha256: aggregate.digest('hex') };
}

async function mapLimit(values, limit, fn) {
  const results = new Array(values.length);
  let next = 0;
  async function worker() {
    while (true) {
      const index = next++;
      if (index >= values.length) return;
      results[index] = await fn(values[index]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, values.length) }, worker));
  return results;
}

async function verifyTargetPayloads(descriptors, target) {
  const results = await mapLimit(descriptors, TARGET_VERIFY_CONCURRENCY, async (descriptor) => {
    const encoded = Buffer.from(JSON.stringify(descriptor)).toString('base64url');
    const child = spawn('ssh', ['-o', 'BatchMode=yes', target,
      `docker exec -i -e FESTAPP_STORAGE_DESCRIPTOR=${encoded} supabase-storage node ${VERIFIER}`], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    child.stdin.end();
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    const [code] = await once(child, 'close');
    if (code !== 0) fail(`target Storage verification failed: ${stderr.slice(0, 800)}`);
    const observed = JSON.parse(stdout.trim());
    if (observed.existed !== true || observed.bytes !== descriptor.expectedSize ||
        (descriptor.expectedMd5 && observed.md5 !== descriptor.expectedMd5) ||
        observed.mimetype !== descriptor.mimetype || observed.cacheControl !== descriptor.cacheControl ||
        !/^[0-9a-f]{64}$/.test(observed.sha256 ?? '')) {
      fail('target Storage payload or metadata differs from the managed descriptor');
    }
    return observed.sha256;
  });
  const aggregate = crypto.createHash('sha256');
  for (const sha256 of results) aggregate.update(`${sha256}\n`);
  return aggregate.digest('hex');
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
  if (!key) fail('legacy service_role key is unavailable');
  return key;
}

async function verifySourcePayloads(descriptors, projectRef, serviceKey) {
  const results = await mapLimit(descriptors, TARGET_VERIFY_CONCURRENCY, async (descriptor) => {
    const sourcePath = [descriptor.bucket, ...descriptor.name.split('/')]
      .map(encodeURIComponent).join('/');
    let response;
    for (let attempt = 0; attempt < 4; attempt += 1) {
      response = await fetch(`https://${projectRef}.supabase.co/storage/v1/object/${sourcePath}`, {
        headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` },
      });
      if (response.ok || response.status < 500) break;
      await response.body?.cancel();
      await new Promise((resolve) => setTimeout(resolve, 250 * (2 ** attempt)));
    }
    if (!response.ok || !response.body) fail(`source Storage verification failed: HTTP ${response.status}`);
    const sha256 = crypto.createHash('sha256');
    const md5 = crypto.createHash('md5');
    let bytes = 0;
    for await (const chunk of response.body) {
      bytes += chunk.length;
      sha256.update(chunk);
      md5.update(chunk);
    }
    const observedMd5 = md5.digest('hex');
    if (bytes !== descriptor.expectedSize ||
        (descriptor.expectedMd5 && observedMd5 !== descriptor.expectedMd5)) {
      fail('source Storage payload differs from the managed descriptor');
    }
    return sha256.digest('hex');
  });
  const aggregate = crypto.createHash('sha256');
  for (const sha256 of results) aggregate.update(`${sha256}\n`);
  return aggregate.digest('hex');
}

async function readEvidence(alias, requestedPath, requestedArtifact, identity, target, token) {
  const file = assertPrivateOutput(requestedPath);
  const artifact = assertPrivateOutput(requestedArtifact);
  const manifestPath = `${artifact}.manifest.json`;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const value = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (value.kind !== 'festapp-storage-payload-rehearsal-copy' ||
      value.source?.alias !== alias || value.source?.project_ref !== SOURCES[alias] ||
      value.target !== EXPECTED_TARGET || value.cloud_source_mutated !== false ||
      value.cloudflare_in_path !== false) {
    fail(`${alias} Storage evidence identity or guarantees mismatch`);
  }
  if (!Number.isSafeInteger(value.objects) || value.objects <= 0 ||
      !Number.isSafeInteger(value.bytes) || value.bytes < 0 ||
      !Number.isSafeInteger(value.resumed_objects) || value.resumed_objects < 0 ||
      value.resumed_objects > value.objects ||
      !/^[0-9a-f]{64}$/.test(value.ordered_payload_sha256 ?? '') ||
      !/^[0-9a-f]{64}$/.test(value.ordered_descriptor_sha256 ?? '') ||
      !/^[0-9a-f]{64}$/.test(value.receiver_sha256 ?? '')) {
    fail(`${alias} Storage evidence cardinality or digest is invalid`);
  }
  if (manifest.source?.alias !== alias || manifest.source?.project_ref !== SOURCES[alias] ||
      await sha256File(artifact) !== manifest.artifact?.sha256 ||
      value.source_artifact_sha256 !== manifest.artifact.sha256 ||
      value.source_manifest_file_sha256 !== await sha256File(manifestPath) ||
      value.source_manifest_sha256 !== manifest.manifest_sha256) {
    fail(`${alias} Storage evidence is not bound to the supplied managed artifact`);
  }
  const descriptors = await readManagedDescriptors(alias, artifact, identity, manifest);
  if (descriptors.objects !== value.objects || descriptors.bytes !== value.bytes ||
      descriptors.orderedDescriptorSha256 !== value.ordered_descriptor_sha256) {
    fail(`${alias} Storage evidence descriptors differ from the encrypted managed artifact`);
  }
  const serviceKey = await serviceRoleKey(SOURCES[alias], token);
  const [sourcePayloadSha256, targetPayloadSha256] = await Promise.all([
    verifySourcePayloads(descriptors.descriptors, SOURCES[alias], serviceKey),
    verifyTargetPayloads(descriptors.descriptors, target),
  ]);
  if (sourcePayloadSha256 !== targetPayloadSha256 ||
      sourcePayloadSha256 !== value.ordered_payload_sha256) {
    fail(`${alias} Storage evidence differs from independently hashed source/target payloads`);
  }
  return { ...value, evidence_sha256: await sha256File(file), artifact: path.resolve(artifact) };
}

async function verifyReceiver(target, expectedSha256) {
  const localSha256 = await sha256File(RECEIVER_SOURCE);
  if (localSha256 !== expectedSha256) fail('copy evidence receiver hash differs from repository receiver');
  const child = spawn('ssh', ['-o', 'BatchMode=yes', target,
    `docker exec supabase-storage sha256sum ${RECEIVER}`], { stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const [code] = await once(child, 'close');
  if (code !== 0 || stdout.trim().split(/\s+/)[0] !== expectedSha256) {
    fail(`target Storage receiver hash mismatch: ${stderr.slice(0, 800)}`);
  }
}

async function installVerifier(target) {
  const expected = await sha256File(VERIFIER_SOURCE);
  const child = spawn('ssh', ['-o', 'BatchMode=yes', target,
    `docker exec -i supabase-storage sh -c 'umask 077; dd of=${VERIFIER} status=none; sha256sum ${VERIFIER}'`],
  { stdio: ['pipe', 'pipe', 'pipe'] });
  child.stdin.end(fs.readFileSync(VERIFIER_SOURCE));
  let stdout = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  const [code] = await once(child, 'close');
  if (code !== 0 || stdout.trim().split(/\s+/)[0] !== expected) fail('target Storage verifier install failed');
  return expected;
}

function sqlString(value) {
  if (!/^[0-9a-f]{64}$/.test(value)) fail('unsafe SQL digest value');
  return `'${value}'`;
}

async function main() {
  const [alias, evidencePath, artifact, identity, database, target = EXPECTED_TARGET] = process.argv.slice(2);
  const sourceIndex = SOURCE_REGISTRY.findIndex((source) => source.alias === alias);
  if (sourceIndex < 0 || !evidencePath || !artifact || !identity || !database) {
    fail(`usage: record-storage-payload-evidence.mjs ${sourceAliasUsage()} EVIDENCE.json MANAGED.age IDENTITY TARGET_DATABASE [${EXPECTED_TARGET}]`);
  }
  if (target !== EXPECTED_TARGET || !/^festapp_rehearsal_[0-9]{14}$/.test(database)) {
    fail('target must be the approved host and a timestamped isolated rehearsal database');
  }
  const token = accessToken();
  const verifierSha256 = await installVerifier(target);
  const evidence = await readEvidence(alias, evidencePath, artifact, identity, target, token);
  await verifyReceiver(target, evidence.receiver_sha256);
  if (alias === 'default') {
    const sql = `BEGIN;
DO $validate$
DECLARE import_run uuid; precondition text; changed bigint;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs
    WHERE source_alias='default' AND source_project_ref='${SOURCES.default}' AND status='blocked';
  SELECT concat_ws('|',
    (SELECT status FROM festapp_merge.validation_results WHERE run_id=import_run AND check_name='default-storage-object-payloads'),
    (SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='storage' AND source_table='objects'),
    (SELECT coalesce(sum((row_data->'metadata'->>'size')::bigint),0) FROM festapp_stage_default_managed.rows WHERE source_schema='storage' AND source_table='objects'),
    (SELECT count(*) FROM festapp_stage_default_managed.rows s JOIN storage.objects t ON t.id=(s.row_data->>'id')::uuid WHERE s.source_schema='storage' AND s.source_table='objects'),
    (SELECT managed_artifact_sha256 FROM festapp_stage_default_managed.provenance WHERE source_alias='default' AND source_project_ref='${SOURCES.default}')
  ) INTO precondition;
  IF precondition <> 'blocked|${evidence.objects}|${evidence.bytes}|${evidence.objects}|${evidence.source_artifact_sha256}' THEN
    RAISE EXCEPTION 'default Storage payload evidence does not match staged/canonical metadata: %',precondition;
  END IF;
  UPDATE festapp_merge.validation_results SET status='pass',observed=jsonb_build_object(
    'metadata_rows',${evidence.objects},'copied_payloads',${evidence.objects},
    'payload_bytes',${evidence.bytes},'resumed_verified_payloads',${evidence.resumed_objects},
    'ordered_payload_sha256',${sqlString(evidence.ordered_payload_sha256)},
    'ordered_descriptor_sha256',${sqlString(evidence.ordered_descriptor_sha256)},
    'source_artifact_sha256',${sqlString(evidence.source_artifact_sha256)},
    'receiver_sha256',${sqlString(evidence.receiver_sha256)},'verifier_sha256',${sqlString(verifierSha256)},
    'evidence_sha256',${sqlString(evidence.evidence_sha256)},
    'source_and_target_rehashed_at_recorder_time',true,'cloud_source_mutated',false,
    'cloudflare_in_path',false,'deleted_payloads',0)
  WHERE run_id=import_run AND check_name='default-storage-object-payloads' AND status='blocked';
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>1 THEN RAISE EXCEPTION 'default Storage payload gate update count was %',changed; END IF;
END
$validate$;
COMMIT;`;
    const child = spawn('ssh', ['-o', 'BatchMode=yes', target,
      `docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U postgres -d ${database}`],
    { stdio: ['pipe', 'pipe', 'pipe'] });
    child.stdin.end(sql);
    let stderr = '';
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    const [code] = await once(child, 'close');
    if (code !== 0) fail(`default Storage payload evidence recording failed: ${stderr.slice(0, 1600)}`);
    process.stdout.write('Default Storage payload evidence recorded.\n');
    return;
  }
  if (sourceIndex < 1 || SOURCE_REGISTRY[sourceIndex].role !== 'merge-source') {
    fail('non-default Storage evidence requires a registered merge source');
  }
  const predecessors = SOURCE_REGISTRY.slice(0, sourceIndex).map((source) => source.alias);
  const predecessorSql = predecessors.map((source) => `'${source}'`).join(',');
  const stageManaged = `festapp_stage_${alias}_managed`;

  const sql = `BEGIN;
DO $validate$
DECLARE import_run uuid; precondition text; changed bigint;
BEGIN
  IF (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias IN (${predecessorSql}) AND status='validated')<>${predecessors.length}
    OR EXISTS (SELECT 1 FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias IN (${predecessorSql}) AND v.status<>'pass') THEN
    RAISE EXCEPTION 'a predecessor source is not fully validated';
  END IF;
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs WHERE source_alias='${alias}' AND source_project_ref='${SOURCES[alias]}' AND status='blocked';
  SELECT concat_ws('|',
    (SELECT status FROM festapp_merge.validation_results WHERE run_id=import_run AND check_name='${alias}-storage-metadata-import'),
    (SELECT status FROM festapp_merge.validation_results WHERE run_id=import_run AND check_name='${alias}-storage-object-payloads'),
    (SELECT status FROM festapp_merge.validation_results WHERE run_id=import_run AND check_name='${alias}-auth-and-storage-import'),
    (SELECT count(*) FROM ${stageManaged}.rows WHERE source_schema='storage' AND source_table='objects'),
    (SELECT coalesce(sum((row_data->'metadata'->>'size')::bigint),0) FROM ${stageManaged}.rows WHERE source_schema='storage' AND source_table='objects'),
    (SELECT count(*) FROM ${stageManaged}.rows s JOIN storage.objects t ON t.id=(s.row_data->>'id')::uuid WHERE s.source_schema='storage' AND s.source_table='objects'),
    (SELECT managed_artifact_sha256 FROM ${stageManaged}.provenance WHERE source_alias='${alias}' AND source_project_ref='${SOURCES[alias]}')
  ) INTO precondition;
  IF precondition <> 'pass|blocked|blocked|${evidence.objects}|${evidence.bytes}|${evidence.objects}|${evidence.source_artifact_sha256}' THEN
    RAISE EXCEPTION 'Storage payload evidence does not match staged/canonical metadata: %',precondition;
  END IF;

  UPDATE festapp_merge.validation_results SET status='pass',observed=jsonb_build_object(
    'metadata_rows',${evidence.objects},'copied_payloads',${evidence.objects},
    'payload_bytes',${evidence.bytes},'resumed_verified_payloads',${evidence.resumed_objects},
    'ordered_payload_sha256',${sqlString(evidence.ordered_payload_sha256)},
    'ordered_descriptor_sha256',${sqlString(evidence.ordered_descriptor_sha256)},
    'source_artifact_sha256',${sqlString(evidence.source_artifact_sha256)},
    'receiver_sha256',${sqlString(evidence.receiver_sha256)},'verifier_sha256',${sqlString(verifierSha256)},
    'evidence_sha256',${sqlString(evidence.evidence_sha256)},
    'source_and_target_rehashed_at_recorder_time',true,
    'snapshot_time_content_proof_requires_final_source_freeze',true,
    'cloud_source_mutated',false,'cloudflare_in_path',false,'deleted_payloads',0)
  WHERE run_id=import_run AND check_name='${alias}-storage-object-payloads' AND status='blocked';
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>1 THEN RAISE EXCEPTION 'merge-source Storage payload gate update count was %',changed; END IF;
  UPDATE festapp_merge.validation_results SET status='pass',observed=observed||jsonb_build_object('storage_payloads_imported',true)
  WHERE run_id=import_run AND check_name='${alias}-auth-and-storage-import' AND status='blocked';
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>1 THEN RAISE EXCEPTION 'merge-source aggregate Storage gate update count was %',changed; END IF;
END
$validate$;
COMMIT;
SELECT jsonb_build_object(
  'storage_objects',(SELECT count(*) FROM storage.objects),
  'source_alias','${alias}',
  'payload_gate',(SELECT status FROM festapp_merge.validation_results WHERE run_id=(SELECT run_id FROM festapp_merge.import_runs WHERE source_alias='${alias}') AND check_name='${alias}-storage-object-payloads')
);
`;
  const child = spawn('ssh', ['-o', 'BatchMode=yes', target,
    `docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U postgres -d ${database}`],
  { stdio: ['pipe', 'pipe', 'pipe'] });
  child.stdin.end(sql);
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const [code] = await once(child, 'close');
  if (code !== 0) fail(`Storage payload evidence recording failed: ${stderr.slice(0, 1600)}`);
  process.stdout.write(stdout);
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
