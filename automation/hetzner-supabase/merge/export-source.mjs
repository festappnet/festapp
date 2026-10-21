#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import {
  SOURCES,
  sourceAliasUsage,
  assertNewEvidencePaths,
  assertPrivateOutput,
  stableJson,
} from './lib.mjs';

export function parseApprovedConnection(alias, rawUrl) {
  const expectedRef = SOURCES[alias];
  if (!expectedRef) throw new Error(`source alias must be ${sourceAliasUsage()}`);
  const url = new URL(rawUrl);
  if (!['postgres:', 'postgresql:'].includes(url.protocol)) {
    throw new Error('source database URL must use PostgreSQL');
  }
  if (!url.password) throw new Error('source database URL must contain a password');
  if ((url.pathname || '/postgres') !== '/postgres') {
    throw new Error('source database must be postgres');
  }
  const decodedUsername = decodeURIComponent(url.username);
  const approvedRole = decodedUsername === 'postgres' || /^festapp_export_[0-9]{13}$/.test(decodedUsername);
  const direct = url.hostname === `db.${expectedRef}.supabase.co` && approvedRole;
  const pooled = url.hostname.endsWith('.pooler.supabase.com') &&
    (decodedUsername === `postgres.${expectedRef}` ||
      new RegExp(`^festapp_export_[0-9]{13}\\.${expectedRef}$`).test(decodedUsername));
  if (!direct && !pooled) throw new Error('database URL does not identify the approved source ref');
  return {
    host: url.hostname,
    port: url.port || '5432',
    username: decodedUsername,
    password: decodeURIComponent(url.password),
    database: 'postgres',
    projectRef: expectedRef,
    connectionKind: direct ? 'direct' : 'session-pooler',
  };
}

export function pgDumpArgs(connection) {
  return [
    '--format=custom',
    '--no-owner',
    '--no-privileges',
    '--serializable-deferrable',
    '--schema', 'public',
    '--schema', 'eshop',
    '--host', connection.host,
    '--port', connection.port,
    '--username', connection.username,
    '--dbname', connection.database,
  ];
}

export function validateRecipient(recipient) {
  const nativeAge = /^age1[0-9a-z]{20,}$/.test(recipient);
  const sshEd25519 = /^ssh-ed25519 [A-Za-z0-9+/]+={0,2}(?: [^\r\n]+)?$/.test(recipient);
  if (!nativeAge && !sshEd25519) {
    throw new Error('FESTAPP_EXPORT_AGE_RECIPIENT must be a native age or SSH Ed25519 recipient');
  }
  return recipient;
}

function runEncryptedDump({ connection, recipient, output }) {
  return new Promise((resolve, reject) => {
    const sshTarget = process.env.FESTAPP_EXPORT_SSH_TARGET;
    if (sshTarget && sshTarget !== 'root@46.224.187.4') {
      reject(new Error('FESTAPP_EXPORT_SSH_TARGET is not the approved rehearsal host'));
      return;
    }
    let dump;
    if (sshTarget) {
      if (connection.connectionKind !== 'direct') {
        reject(new Error('remote rehearsal export requires an approved direct source connection'));
        return;
      }
      const shellQuote = (value) => `'${value.replaceAll("'", "'\\''")}'`;
      const containerName = `festapp-export-${connection.username}-${connection.projectRef.slice(0, 8)}`;
      const remoteArgs = [
        'docker', 'run', '-i', '--name', containerName, '--network', 'host',
        '--entrypoint', 'sh',
        'supabase/postgres:17.6.1.136@sha256:a9946f08d31e8eb1149229c94e5c26603a9233116807cbbd93d75179cbac516a',
        '-c',
        'read -r PGPASSWORD; export PGPASSWORD; export PGSSLMODE=require; exec pg_dump "$@"',
        'sh', ...pgDumpArgs(connection),
      ];
      dump = spawn('ssh', [
        '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', sshTarget,
        remoteArgs.map(shellQuote).join(' '),
      ], { stdio: ['pipe', 'pipe', 'pipe'] });
      dump.stdin.end(`${connection.password}\n`);
    } else {
      dump = spawn('pg_dump', pgDumpArgs(connection), {
        env: { ...process.env, PGPASSWORD: connection.password, PGSSLMODE: 'require' },
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    }
    const encrypt = spawn('age', ['--recipient', recipient, '--output', output], {
      stdio: ['pipe', 'ignore', 'pipe'],
    });
    let dumpError = '';
    let encryptError = '';
    dump.stderr.on('data', (chunk) => { dumpError += chunk; });
    encrypt.stderr.on('data', (chunk) => { encryptError += chunk; });
    dump.stdout.pipe(encrypt.stdin);
    let dumpCode;
    let encryptCode;
    const finish = () => {
      if (dumpCode === undefined || encryptCode === undefined) return;
      if (dumpCode === 0 && encryptCode === 0) resolve();
      else reject(new Error(
        `encrypted dump failed (pg_dump=${dumpCode}, age=${encryptCode}): ${dumpError || encryptError}`.trim(),
      ));
    };
    dump.on('error', reject);
    encrypt.on('error', reject);
    dump.on('close', (code) => { dumpCode = code; finish(); });
    encrypt.on('close', (code) => { encryptCode = code; finish(); });
  });
}

async function fileSha256(filePath) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

async function main() {
  const [alias, requestedOutput] = process.argv.slice(2);
  if (!alias || !requestedOutput) {
    throw new Error('usage: export-source.mjs default|a /private/path/source.dump.age');
  }
  const output = assertPrivateOutput(requestedOutput);
  if (!output.endsWith('.dump.age')) throw new Error('encrypted output must end in .dump.age');
  const manifestPath = `${output}.manifest.json`;
  assertNewEvidencePaths([output, manifestPath]);
  const parent = path.dirname(output);
  const parentMode = fs.statSync(parent).mode & 0o777;
  if ((parentMode & 0o077) !== 0) throw new Error('output directory must not be accessible to group or others');

  const connection = parseApprovedConnection(alias, process.env.FESTAPP_SOURCE_DATABASE_URL ?? '');
  const recipient = validateRecipient(process.env.FESTAPP_EXPORT_AGE_RECIPIENT ?? '');
  await runEncryptedDump({ connection, recipient, output });
  fs.chmodSync(output, 0o600);

  const manifest = {
    manifest_version: 1,
    kind: 'encrypted-logical-source-snapshot',
    generated_at: new Date().toISOString(),
    source: {
      alias,
      project_ref: connection.projectRef,
      connection_kind: connection.connectionKind,
      execution_host: process.env.FESTAPP_EXPORT_SSH_TARGET ? 'approved-rehearsal-host' : 'local',
    },
    artifact: {
      format: 'pg_dump-custom+age',
      schemas: ['public', 'eshop'],
      path_basename: path.basename(output),
      bytes: fs.statSync(output).size,
      sha256: await fileSha256(output),
    },
    guarantees: {
      cloud_source_mutated: false,
      plaintext_dump_written: false,
      overwrite_permitted: false,
    },
  };
  manifest.manifest_sha256 = crypto.createHash('sha256').update(stableJson(manifest)).digest('hex');
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write(`${alias} encrypted snapshot: bytes=${manifest.artifact.bytes} sha256=${manifest.artifact.sha256}\n`);
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
