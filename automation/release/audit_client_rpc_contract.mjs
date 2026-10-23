#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  managementQuery,
  parseKeyValueFile,
} from '../lib/supabase_management.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const RPC_CALL = /(?:\.rpc|_transport\.invoke|\b_invoke|(?<![.\w])invoke|_configurationCommand|_adminCommand|_readRpc)\s*\(\s*(['"])([a-z][a-z0-9_]*)\1/g;

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const result = {
    host: 'root@46.224.187.4',
    database: 'festapp_rehearsal_20260828234500',
    'project-root': root,
  };
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      fail('usage: audit_client_rpc_contract.mjs [--project-root /repo] [--host root@host] [--database festapp_rehearsal_YYYYMMDDHHMMSS] [--output /private/path.json]');
    }
    result[key.slice(2)] = value;
  }
  if (!/^root@[a-zA-Z0-9.-]+$/.test(result.host) ||
      !/^festapp_(?:rehearsal|restore)_[0-9]+$/.test(result.database)) {
    fail('canonical target must be an approved host and isolated rehearsal/restore database');
  }
  return result;
}

function walk(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(absolute));
    else if (/\.(?:dart|js|mjs|ts|tsx)$/.test(entry.name)) files.push(absolute);
  }
  return files;
}

export function extractClientRpcContract(projectRoot = root) {
  const calls = new Map();
  const sourceRoots = ['lib', 'web_client/src'];
  for (const relativeRoot of sourceRoots) {
    const directory = path.join(projectRoot, relativeRoot);
    if (!fs.existsSync(directory)) continue;
    for (const file of walk(directory)) {
      const source = fs.readFileSync(file, 'utf8');
      for (const match of source.matchAll(RPC_CALL)) {
        const before = source.slice(0, match.index);
        const line = before.split('\n').length;
        const name = match[2];
        const references = calls.get(name) ?? [];
        references.push(`${path.relative(projectRoot, file)}:${line}`);
        calls.set(name, references);
      }
    }
  }
  return [...calls.entries()]
    .map(([name, references]) => ({ name, references: [...new Set(references)].sort() }))
    .sort((left, right) => left.name.localeCompare(right.name));
}

const catalogSql = `SELECT COALESCE(json_agg(json_build_object(
  'name',p.proname,
  'arguments',pg_get_function_identity_arguments(p.oid),
  'result',pg_get_function_result(p.oid),
  'security_definer',p.prosecdef
) ORDER BY p.proname,pg_get_function_identity_arguments(p.oid)),'[]'::json)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind='f'`;

function normalizeCatalog(value) {
  const parsed = typeof value === 'string' ? JSON.parse(value) : value;
  if (!Array.isArray(parsed)) fail('RPC catalog response is not an array');
  return parsed.map((entry) => ({
    name: entry.name,
    arguments: entry.arguments ?? '',
    result: entry.result ?? '',
    security_definer: entry.security_definer === true,
  }));
}

async function legacyCatalog(projectRef, accessToken) {
  const rows = await managementQuery({ projectRef, accessToken, query: catalogSql });
  return normalizeCatalog(rows[0]?.coalesce ?? rows[0]?.json_agg ?? []);
}

function canonicalCatalog(host, database) {
  const result = spawnSync('ssh', ['-o', 'BatchMode=yes', host,
    'docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
    '-U', 'postgres', '-d', database, '-At'], {
    input: catalogSql,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.status !== 0) fail(`canonical RPC catalog failed: ${result.stderr.trim()}`);
  return normalizeCatalog(result.stdout.trim());
}

function names(catalog) {
  return new Set(catalog.map((entry) => entry.name));
}

function signaturesFor(catalog, requiredNames) {
  return catalog.filter((entry) => requiredNames.has(entry.name));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectRoot = path.resolve(args['project-root']);
  const config = parseKeyValueFile(path.join(projectRoot, 'automation/project.conf'));
  const local = parseKeyValueFile(path.join(projectRoot, '.env.local'));
  const projectRef = config.get('SUPABASE_URL')
    ?.match(/^https:\/\/([a-z0-9]+)\.supabase\.co$/)?.[1];
  const accessToken = process.env.SUPABASE_ACCESS_TOKEN || local.get('SUPABASE_ACCESS_TOKEN');
  if (!projectRef || !accessToken) fail('legacy project ref and SUPABASE_ACCESS_TOKEN are required');
  const calls = extractClientRpcContract(projectRoot);
  const requiredNames = new Set(calls.map((call) => call.name));
  const [legacy, canonical] = await Promise.all([
    legacyCatalog(projectRef, accessToken),
    Promise.resolve(canonicalCatalog(args.host, args.database)),
  ]);
  const legacyNames = names(legacy);
  const canonicalNames = names(canonical);
  const missingLegacy = [...requiredNames].filter((name) => !legacyNames.has(name)).sort();
  const missingCanonical = [...requiredNames].filter((name) => !canonicalNames.has(name)).sort();
  const evidence = {
    version: 1,
    client_rpc_count: calls.length,
    legacy: {
      project_ref: projectRef,
      public_function_count: legacy.length,
      present_client_rpcs: calls.length - missingLegacy.length,
      missing_client_rpcs: missingLegacy,
      required_signatures: signaturesFor(legacy, requiredNames),
    },
    canonical: {
      host: args.host,
      database: args.database,
      public_function_count: canonical.length,
      present_client_rpcs: calls.length - missingCanonical.length,
      missing_client_rpcs: missingCanonical,
      required_signatures: signaturesFor(canonical, requiredNames),
    },
    calls,
  };
  if (args.output) {
    const output = path.resolve(args.output);
    const parent = path.dirname(output);
    fs.mkdirSync(parent, { recursive: true, mode: 0o700 });
    fs.writeFileSync(output, `${JSON.stringify(evidence, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  }
  console.log(JSON.stringify({
    client_rpc_count: evidence.client_rpc_count,
    legacy_public_functions: evidence.legacy.public_function_count,
    legacy_present: evidence.legacy.present_client_rpcs,
    legacy_missing: missingLegacy,
    canonical_public_functions: evidence.canonical.public_function_count,
    canonical_present: evidence.canonical.present_client_rpcs,
    canonical_missing: missingCanonical,
  }));
  if (missingCanonical.length > 0) process.exitCode = 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(`ERROR: ${error.message}`);
    process.exitCode = 1;
  });
}
