#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import {
  SOURCES,
  accessToken,
  assertNewEvidencePaths,
  assertPrivateOutput,
  managementQuery,
  quoteIdentifier,
  stableJson,
} from './lib.mjs';
import { validateRecipient } from './export-source.mjs';

const PAGE_SIZE = 10_000;
const TABLES_QUERY = `SELECT n.nspname AS schema_name, c.relname AS table_name,
  to_jsonb(coalesce(array_agg(a.attname ORDER BY key_columns.ordinality)
    FILTER (WHERE a.attname IS NOT NULL), ARRAY[]::name[])) AS primary_key
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_index i ON i.indrelid = c.oid AND i.indisprimary
LEFT JOIN LATERAL unnest(i.indkey) WITH ORDINALITY key_columns(attnum, ordinality) ON true
LEFT JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = key_columns.attnum
WHERE n.nspname IN ('auth', 'storage') AND c.relkind IN ('r', 'p')
GROUP BY n.nspname, c.relname
ORDER BY n.nspname, c.relname`;

export function buildPageQuery(table, offset, limit = PAGE_SIZE) {
  if (!['auth', 'storage'].includes(table.schema_name)) throw new Error('unapproved managed schema');
  if (!Array.isArray(table.primary_key) || table.primary_key.length === 0) {
    throw new Error(`managed table has no primary key: ${table.schema_name}.${table.table_name}`);
  }
  if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > PAGE_SIZE) {
    throw new Error('invalid managed export page');
  }
  const relation = `${quoteIdentifier(table.schema_name)}.${quoteIdentifier(table.table_name)}`;
  const order = table.primary_key.map((column) => `source_row.${quoteIdentifier(column)}`).join(', ');
  return `SELECT to_jsonb(source_row) AS row FROM ${relation} AS source_row ORDER BY ${order} LIMIT ${limit} OFFSET ${offset}`;
}

async function writeLine(stream, value) {
  if (!stream.write(`${JSON.stringify(value)}\n`)) await once(stream, 'drain');
}

async function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

async function exportSource({ alias, projectRef, token, recipient, output }) {
  const manifestPath = `${output}.manifest.json`;
  assertNewEvidencePaths([output, manifestPath]);
  const encrypt = spawn('age', ['--recipient', recipient, '--output', output], {
    stdio: ['pipe', 'ignore', 'pipe'],
  });
  let encryptError = '';
  encrypt.stderr.on('data', (chunk) => { encryptError += chunk; });
  const completion = new Promise((resolve, reject) => {
    encrypt.on('error', reject);
    encrypt.on('close', (code) => code === 0 ? resolve() : reject(new Error(`age failed: ${encryptError}`)));
  });

  const startedAt = new Date().toISOString();
  const tables = await managementQuery({ projectRef, token, query: TABLES_QUERY });
  if (tables.length === 0 || tables.some((table) => table.primary_key.length === 0)) {
    encrypt.stdin.destroy();
    throw new Error(`${alias} managed catalog is empty or has a table without primary key`);
  }
  const counts = [];
  try {
    await writeLine(encrypt.stdin, {
      kind: 'festapp-managed-schema-export', version: 1, source_alias: alias,
      project_ref: projectRef, started_at: startedAt, schemas: ['auth', 'storage'],
    });
    for (const table of tables) {
      await writeLine(encrypt.stdin, { kind: 'table', ...table });
      let offset = 0;
      while (true) {
        const page = await managementQuery({
          projectRef,
          token,
          query: buildPageQuery(table, offset),
        });
        for (const value of page) {
          await writeLine(encrypt.stdin, {
            kind: 'row', schema_name: table.schema_name, table_name: table.table_name, row: value.row,
          });
        }
        offset += page.length;
        if (page.length < PAGE_SIZE) break;
      }
      counts.push({ schema_name: table.schema_name, table_name: table.table_name, rows: offset });
    }
    await writeLine(encrypt.stdin, { kind: 'complete', completed_at: new Date().toISOString(), counts });
    encrypt.stdin.end();
    await completion;
  } catch (error) {
    encrypt.stdin.destroy();
    throw error;
  }
  fs.chmodSync(output, 0o600);
  const manifest = {
    manifest_version: 1,
    kind: 'encrypted-managed-schema-rehearsal-export',
    generated_at: new Date().toISOString(),
    source: { alias, project_ref: projectRef },
    snapshot_consistency: 'rehearsal-page-window-not-final-cutover',
    tables: counts,
    artifact: {
      format: 'jsonl+age', path_basename: path.basename(output),
      bytes: fs.statSync(output).size, sha256: await sha256File(output),
    },
    guarantees: { cloud_source_mutated: false, plaintext_export_written: false, overwrite_permitted: false },
  };
  manifest.manifest_sha256 = crypto.createHash('sha256').update(stableJson(manifest)).digest('hex');
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write(`${alias} managed snapshot: rows=${counts.reduce((sum, item) => sum + item.rows, 0)} sha256=${manifest.artifact.sha256}\n`);
}

async function main() {
  const [requestedRunDir, publicKeyPath = path.join(process.env.HOME ?? '', '.ssh/id_ed25519.pub')] =
    process.argv.slice(2);
  if (!requestedRunDir) throw new Error('usage: export-managed-schemas.mjs /private/existing-run-dir [ssh-public-key]');
  const runDir = assertPrivateOutput(requestedRunDir);
  if (!fs.statSync(runDir).isDirectory() || (fs.statSync(runDir).mode & 0o077) !== 0) {
    throw new Error('managed export run directory must exist and be private');
  }
  const recipient = validateRecipient(fs.readFileSync(publicKeyPath, 'utf8').trim());
  const token = accessToken();
  const requestedAliases = (process.env.FESTAPP_EXPORT_SOURCES ?? Object.keys(SOURCES).join(','))
    .split(',').filter(Boolean);
  if (requestedAliases.length === 0 || new Set(requestedAliases).size !== requestedAliases.length ||
      requestedAliases.some((alias) => !SOURCES[alias])) {
    throw new Error('FESTAPP_EXPORT_SOURCES must be a unique comma-separated subset of approved aliases');
  }
  for (const alias of requestedAliases) {
    const projectRef = SOURCES[alias];
    await exportSource({
      alias, projectRef, token, recipient,
      output: path.join(runDir, `${alias}.managed.jsonl.age`),
    });
  }
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
