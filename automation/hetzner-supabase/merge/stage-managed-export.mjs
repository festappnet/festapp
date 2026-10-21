#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { SOURCES, assertPrivateOutput, sourceAliasUsage, stableJson } from './lib.mjs';

function targetDatabase(alias) {
  const suffix = process.env.FESTAPP_STAGE_DATABASE_SUFFIX ?? '';
  if (suffix && !/^[0-9]{14}$/.test(suffix)) throw new Error('invalid staging database suffix');
  return `festapp_stage_${alias}${suffix ? `_${suffix}` : ''}`;
}
const EXPECTED_HOST = 'festapp-supabase-rehearsal-01';
const COMPOSE_DIR = '/opt/festapp-supabase/docker';

async function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

export function csvField(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const { input, ...spawnOptions } = options;
    const child = spawn(command, args, {
      ...spawnOptions,
      stdio: options.stdio ?? [input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout?.on('data', (chunk) => { stdout += chunk; });
    child.stderr?.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => code === 0 ? resolve(stdout) : reject(new Error(`${command} failed (${code}): ${stderr}`)));
    if (input !== undefined) child.stdin.end(input);
  });
}

async function main() {
  const [alias, requestedArtifact, identityPath, requestedRawArtifact,
    sshTarget = 'root@46.224.187.4'] = process.argv.slice(2);
  if (!SOURCES[alias] || !requestedArtifact || !identityPath || !requestedRawArtifact) {
    throw new Error(`usage: stage-managed-export.mjs ${sourceAliasUsage()} MANAGED.age SSH-IDENTITY RAW.dump.age [root@host]`);
  }
  const artifact = assertPrivateOutput(requestedArtifact);
  const rawArtifact = assertPrivateOutput(requestedRawArtifact);
  if (path.dirname(artifact) !== path.dirname(rawArtifact)) {
    throw new Error('raw and managed artifacts must come from the same private snapshot directory');
  }
  const manifestPath = `${artifact}.manifest.json`;
  const rawManifestPath = `${rawArtifact}.manifest.json`;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const rawManifest = JSON.parse(fs.readFileSync(rawManifestPath, 'utf8'));
  if (manifest.source?.alias !== alias || manifest.source?.project_ref !== SOURCES[alias]) {
    throw new Error('managed manifest source identity mismatch');
  }
  if (manifest.artifact?.path_basename !== path.basename(artifact) ||
      rawManifest.artifact?.path_basename !== path.basename(rawArtifact)) {
    throw new Error('source artifact basename does not match its manifest');
  }
  if (rawManifest.source?.alias !== alias || rawManifest.source?.project_ref !== SOURCES[alias]) {
    throw new Error('raw manifest source identity mismatch');
  }
  const isoInstant = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$/;
  const digest = /^[0-9a-f]{64}$/;
  if (!isoInstant.test(manifest.generated_at ?? '') || !isoInstant.test(rawManifest.generated_at ?? '') ||
      !digest.test(manifest.manifest_sha256 ?? '') || !digest.test(rawManifest.manifest_sha256 ?? '') ||
      !digest.test(manifest.artifact?.sha256 ?? '') || !digest.test(rawManifest.artifact?.sha256 ?? '')) {
    throw new Error('source manifest timestamp or digest format is invalid');
  }
  const manifestContent = { ...manifest };
  delete manifestContent.manifest_sha256;
  const rawManifestContent = { ...rawManifest };
  delete rawManifestContent.manifest_sha256;
  if (crypto.createHash('sha256').update(stableJson(manifestContent)).digest('hex') !== manifest.manifest_sha256 ||
      crypto.createHash('sha256').update(stableJson(rawManifestContent)).digest('hex') !== rawManifest.manifest_sha256) {
    throw new Error('source manifest content checksum mismatch');
  }
  if (await sha256File(artifact) !== manifest.artifact?.sha256 ||
      await sha256File(rawArtifact) !== rawManifest.artifact?.sha256) {
    throw new Error('source artifact checksum mismatch');
  }
  const snapshotDeltaSeconds = (Date.parse(manifest.generated_at) - Date.parse(rawManifest.generated_at)) / 1000;
  if (!Number.isFinite(snapshotDeltaSeconds) || snapshotDeltaSeconds < 0 || snapshotDeltaSeconds > 900) {
    throw new Error('raw and managed snapshots are not from the approved bounded export window');
  }
  const expectedRows = manifest.tables.reduce((sum, table) => sum + table.rows, 0);
  const database = targetDatabase(alias);
  const resumeAfterCopy = process.env.FESTAPP_MANAGED_STAGE_ACK ===
    'resume-after-complete-copy-before-provenance';

  const state = (await run('ssh', ['-o', 'BatchMode=yes', sshTarget,
    `cd ${COMPOSE_DIR} && printf '%s|' "$(hostname -s)" && docker compose exec -T db psql -X -Atq -F '|' -U postgres -d ${database} -c "SELECT split_part(current_setting('server_version'),'.',1), to_regnamespace('festapp_managed_source') IS NULL"`,
  ])).trim();
  if (!resumeAfterCopy && state !== `${EXPECTED_HOST}|17|t`) {
    throw new Error(`unapproved managed staging target state: ${state}`);
  }
  if (resumeAfterCopy) {
    if (state !== `${EXPECTED_HOST}|17|f`) {
      throw new Error(`unapproved managed staging resume target state: ${state}`);
    }
    const resumeState = (await run('ssh', ['-o', 'BatchMode=yes', sshTarget,
      `cd ${COMPOSE_DIR} && docker compose exec -T db psql -X -Atq -F '|' -U postgres -d ${database} -c "SELECT count(*),to_regclass('festapp_managed_source.provenance') IS NULL,to_regclass('festapp_managed_source_relation_idx') IS NULL FROM festapp_managed_source.rows"`,
    ])).trim();
    if (resumeState !== `${expectedRows}|t|t`) {
      throw new Error(`managed staging resume requires an exact completed-copy state: ${resumeState}`);
    }
  }

  const foundationSql = `BEGIN;
CREATE SCHEMA festapp_managed_source AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA festapp_managed_source FROM PUBLIC, anon, authenticated, service_role;
CREATE TABLE festapp_managed_source.rows (
  row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_schema text NOT NULL CHECK (source_schema IN ('auth','storage')),
  source_table text NOT NULL,
  row_data jsonb NOT NULL
);
REVOKE ALL ON ALL TABLES IN SCHEMA festapp_managed_source FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA festapp_managed_source FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
`;
  let rows = expectedRows;
  if (!resumeAfterCopy) {
    const foundation = spawn('ssh', ['-o', 'BatchMode=yes', sshTarget,
      `cd ${COMPOSE_DIR} && docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d ${database}`,
    ], { stdio: ['pipe', 'pipe', 'pipe'] });
    foundation.stdin.end(foundationSql);
    let foundationError = '';
    foundation.stderr.on('data', (chunk) => { foundationError += chunk; });
    const [foundationCode] = await once(foundation, 'close');
    if (foundationCode !== 0) throw new Error(`managed staging foundation failed: ${foundationError}`);

    const decrypt = spawn('age', ['--decrypt', '--identity', identityPath, artifact], {
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const copy = spawn('ssh', ['-o', 'BatchMode=yes', sshTarget,
      `cd ${COMPOSE_DIR} && docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d ${database} -c "COPY festapp_managed_source.rows(source_schema,source_table,row_data) FROM STDIN WITH (FORMAT csv, DELIMITER E'\\t')"`,
    ], { stdio: ['pipe', 'pipe', 'pipe'] });
    let decryptError = '';
    let copyError = '';
    decrypt.stderr.on('data', (chunk) => { decryptError += chunk; });
    copy.stderr.on('data', (chunk) => { copyError += chunk; });
    rows = 0;
    let completed = false;
    const lines = readline.createInterface({ input: decrypt.stdout, crlfDelay: Infinity });
    for await (const line of lines) {
      const value = JSON.parse(line);
      if (value.kind === 'row') {
        const csv = `${csvField(value.schema_name)}\t${csvField(value.table_name)}\t${csvField(JSON.stringify(value.row))}\n`;
        if (!copy.stdin.write(csv)) await once(copy.stdin, 'drain');
        rows += 1;
      } else if (value.kind === 'complete') {
        completed = true;
      }
    }
    copy.stdin.end();
    const [[decryptCode], [copyCode]] = await Promise.all([once(decrypt, 'close'), once(copy, 'close')]);
    if (decryptCode !== 0 || copyCode !== 0) {
      throw new Error(`managed staging stream failed (age=${decryptCode}, copy=${copyCode}): ${decryptError || copyError}`);
    }
    if (!completed || rows !== expectedRows) throw new Error(`managed staging row mismatch: ${rows}/${expectedRows}`);
  }
  const restoredSchemaSql = await run('ssh', ['-o', 'BatchMode=yes', sshTarget,
    `cd ${COMPOSE_DIR} && docker compose exec -T db pg_dump -U postgres -d ${database} --schema-only --no-owner --no-privileges --schema public --schema eshop`,
  ]);
  const rawSchemaSha256 = crypto.createHash('sha256').update(restoredSchemaSql).digest('hex');
  const provenanceSql = `BEGIN;
CREATE TABLE festapp_managed_source.provenance (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  source_alias text NOT NULL,
  source_project_ref text NOT NULL,
  raw_artifact_sha256 text NOT NULL CHECK (raw_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  raw_manifest_sha256 text NOT NULL CHECK (raw_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  raw_schema_sha256 text NOT NULL CHECK (raw_schema_sha256 ~ '^[0-9a-f]{64}$'),
  raw_snapshot_at timestamptz NOT NULL,
  managed_artifact_sha256 text NOT NULL CHECK (managed_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  managed_manifest_sha256 text NOT NULL CHECK (managed_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  managed_snapshot_at timestamptz NOT NULL,
  raw_managed_delta_seconds integer NOT NULL CHECK (raw_managed_delta_seconds BETWEEN 0 AND 900),
  managed_rows bigint NOT NULL CHECK (managed_rows > 0)
);
INSERT INTO festapp_managed_source.provenance(
  source_alias,source_project_ref,raw_artifact_sha256,raw_manifest_sha256,raw_schema_sha256,raw_snapshot_at,
  managed_artifact_sha256,managed_manifest_sha256,managed_snapshot_at,raw_managed_delta_seconds,managed_rows
) VALUES (
  '${alias}','${SOURCES[alias]}','${rawManifest.artifact.sha256}','${rawManifest.manifest_sha256}','${rawSchemaSha256}',
  '${rawManifest.generated_at}','${manifest.artifact.sha256}','${manifest.manifest_sha256}',
  '${manifest.generated_at}',${Math.floor(snapshotDeltaSeconds)},${expectedRows}
);
REVOKE ALL ON festapp_managed_source.provenance FROM PUBLIC, anon, authenticated, service_role;
COMMIT;`;
  await run('ssh', ['-o', 'BatchMode=yes', sshTarget,
    `cd ${COMPOSE_DIR} && docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d ${database}`,
  ], { input: provenanceSql });
  await run('ssh', ['-o', 'BatchMode=yes', sshTarget,
    `cd ${COMPOSE_DIR} && docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d ${database} -c "CREATE INDEX festapp_managed_source_relation_idx ON festapp_managed_source.rows(source_schema,source_table); ANALYZE festapp_managed_source.rows"`,
  ]);
  const observed = (await run('ssh', ['-o', 'BatchMode=yes', sshTarget,
    `cd ${COMPOSE_DIR} && docker compose exec -T db psql -X -Atq -U postgres -d ${database} -c "SELECT count(*) FROM festapp_managed_source.rows"`,
  ])).trim();
  if (Number(observed) !== expectedRows) throw new Error(`remote managed staging count mismatch: ${observed}/${expectedRows}`);
  process.stdout.write(`${alias} managed staging complete: rows=${rows}\n`);
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
