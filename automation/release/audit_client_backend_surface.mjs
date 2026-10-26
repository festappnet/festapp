#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { extractClientRpcContract } from './audit_client_rpc_contract.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EDGE_CALL = /functions\.invoke\s*\(\s*(['"])([a-z][a-z0-9-]*)\1/g;
const TABLE_GETTER = /String\s+get\s+table\s*=>\s*(['"])([a-z][a-z0-9_]*)\1/g;
const LITERAL_TABLE = /\.from\s*\(\s*(['"])([a-z][a-z0-9_]*)\1/g;

function fail(message) {
  throw new Error(message);
}

function walk(directory) {
  if (!fs.existsSync(directory)) return [];
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(absolute));
    else if (/\.(?:dart|js|mjs|ts|tsx)$/.test(entry.name)) files.push(absolute);
  }
  return files;
}

function extract(projectRoot, regex, roots) {
  const values = new Map();
  for (const relativeRoot of roots) {
    for (const file of walk(path.join(projectRoot, relativeRoot))) {
      const source = fs.readFileSync(file, 'utf8');
      for (const match of source.matchAll(regex)) {
        const name = match[2];
        const line = source.slice(0, match.index).split('\n').length;
        const references = values.get(name) ?? [];
        references.push(`${path.relative(projectRoot, file)}:${line}`);
        values.set(name, references);
      }
    }
  }
  return [...values.entries()].map(([name, references]) => ({
    name,
    references: [...new Set(references)].sort(),
  })).sort((left, right) => left.name.localeCompare(right.name));
}

export function extractClientEdgeContract(projectRoot = root) {
  return extract(projectRoot, EDGE_CALL, ['lib', 'web_client/src']);
}

export function extractClientRelationContract(projectRoot = root) {
  const registries = [
    ['lib/database_tables/tb.dart', 'public', 'Tb'],
    ['lib/components/eshop/models/tb_eshop.dart', 'eshop', 'TbEshop'],
  ];
  const relations = new Map();
  const clientSource = ['lib', 'web_client/src'].flatMap((relative) => walk(path.join(projectRoot, relative)))
    .map((file) => fs.readFileSync(file, 'utf8')).join('\n');
  for (const [relative, schema, owner] of registries) {
    const file = path.join(projectRoot, relative);
    if (!fs.existsSync(file)) continue;
    const source = fs.readFileSync(file, 'utf8');
    const classTables = new Map();
    const classHeaders = [...source.matchAll(/\bclass\s+(\w+)\s*\{/g)];
    for (let index = 0; index < classHeaders.length; index += 1) {
      const classMatch = classHeaders[index];
      const body = source.slice(classMatch.index, classHeaders[index + 1]?.index ?? source.length);
      const tableMatch = [...body.matchAll(TABLE_GETTER)][0];
      if (tableMatch) classTables.set(classMatch[1], tableMatch[2]);
    }
    for (const fieldMatch of source.matchAll(/static\s+(\w+)\s+(\w+)\s*=\s*const\s+\w+\s*\(\s*\)/g)) {
      const [, type, field] = fieldMatch;
      const table = classTables.get(type);
      if (!table || !new RegExp(`\\b${owner}\\.${field}\\b`).test(clientSource)) continue;
      const qualified = `${schema}.${table}`;
      const references = relations.get(qualified) ?? [];
      references.push(`${relative}#${owner}.${field}`);
      relations.set(qualified, references);
    }
  }
  for (const entry of extract(projectRoot, LITERAL_TABLE, ['lib', 'web_client/src'])) {
    const qualified = `public.${entry.name}`;
    relations.set(qualified, [...new Set([...(relations.get(qualified) ?? []), ...entry.references])]);
  }
  return [...relations.entries()].map(([name, references]) => ({ name, references: references.sort() }))
    .sort((left, right) => left.name.localeCompare(right.name));
}

function runSsh(host, command, input = undefined) {
  const result = spawnSync('ssh', ['-o', 'BatchMode=yes', host, command], {
    input,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.status !== 0) fail(result.stderr.trim() || `SSH command failed with ${result.status}`);
  return result.stdout;
}

function parseArgs(argv) {
  const args = {
    host: 'root@46.224.187.4',
    database: 'festapp_rehearsal_20260828234500',
    'project-root': root,
  };
  for (let index = 0; index < argv.length; index += 2) {
    if (!argv[index]?.startsWith('--') || argv[index + 1] === undefined) fail('invalid arguments');
    args[argv[index].slice(2)] = argv[index + 1];
  }
  if (!/^root@[a-zA-Z0-9.-]+$/.test(args.host) ||
      !/^festapp_(?:rehearsal|restore)_[0-9]+$/.test(args.database)) {
    fail('canonical target must be an approved host and isolated rehearsal/restore database');
  }
  return args;
}

function canonicalRelations(host, database, required) {
  const tuples = required.map(({ name }) => {
    const [schema, table] = name.split('.');
    return `('${schema}','${table}')`;
  }).join(',');
  const sql = `SELECT schema_name||'.'||table_name FROM (VALUES ${tuples}) AS required(schema_name,table_name)
WHERE to_regclass(format('%I.%I',schema_name,table_name)) IS NOT NULL ORDER BY 1;`;
  return new Set(runSsh(host,
    `docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U postgres -d ${database} -At`, sql)
    .trim().split('\n').filter(Boolean));
}

function canonicalEdgeFunctions(host) {
  return new Set(runSsh(host,
    "find /opt/festapp-supabase/docker/volumes/functions -mindepth 2 -maxdepth 2 -name index.ts -printf '%h\\n' | sed 's#.*/##' | sort -u")
    .trim().split('\n').filter(Boolean));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectRoot = path.resolve(args['project-root']);
  const rpcs = extractClientRpcContract(projectRoot);
  const edge = extractClientEdgeContract(projectRoot);
  const relations = extractClientRelationContract(projectRoot);
  const edgeAvailable = canonicalEdgeFunctions(args.host);
  const relationAvailable = canonicalRelations(args.host, args.database, relations);
  const missingEdge = edge.map(({ name }) => name).filter((name) => !edgeAvailable.has(name));
  const missingRelations = relations.map(({ name }) => name).filter((name) => !relationAvailable.has(name));
  const evidence = {
    version: 1,
    canonical: { host: args.host, database: args.database },
    rpc_names: rpcs.map(({ name }) => name),
    edge_functions: edge,
    relations,
    missing_edge_functions: missingEdge,
    missing_relations: missingRelations,
  };
  if (args.output) {
    const output = path.resolve(args.output);
    fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
    fs.writeFileSync(output, `${JSON.stringify(evidence, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
  }
  console.log(JSON.stringify({
    rpc_names: rpcs.length,
    edge_functions: edge.length,
    missing_edge_functions: missingEdge,
    relations: relations.length,
    missing_relations: missingRelations,
  }));
  if (missingEdge.length || missingRelations.length) process.exitCode = 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(`ERROR: ${error.message}`);
    process.exitCode = 1;
  });
}
