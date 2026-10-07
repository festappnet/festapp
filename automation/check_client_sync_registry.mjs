#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import {checkCanonicalInventory} from './client-sync/check_canonical_inventory.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const migrationPath = path.join(
  root,
  'supabase/migrations/20260802234000_client_sync_v1_expansion.sql',
);
const migration = fs.readFileSync(migrationPath, 'utf8');

const registryStart = migration.indexOf(
  'INSERT INTO public.client_sync_component_sources',
);
const registryEnd = migration.indexOf(
  'INSERT INTO public.client_projection_dirty_keys',
  registryStart,
);
if (registryStart < 0 || registryEnd < 0) {
  throw new Error('client sync component registry block is missing');
}

const registry = migration.slice(registryStart, registryEnd);
const rowPattern =
  /\(1,'([^']+)','([^']+)','[^']*',ARRAY\[[^\]]*\],ARRAY\[([^\]]+)\],ARRAY\[[^\]]*\](?:::\w+\[\])?,'(migrate|boundary|delete)','[^']+'\)/g;
const rows = [...registry.matchAll(rowPattern)].map((match) => ({
  component: match[1],
  relation: match[2],
  writers: [...match[3].matchAll(/'([a-zA-Z0-9_]+)'/g)].map(
    (writer) => writer[1],
  ),
  disposition: match[4],
}));
if (rows.length === 0) throw new Error('component registry rows were not parsed');

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(absolute) : [absolute];
  });
}

const sqlSources = [
  migration,
  ...walk(path.join(root, 'database/functions'))
    .filter((file) => file.endsWith('.sql'))
    .map((file) => fs.readFileSync(file, 'utf8')),
].join('\n');
const declaredFunctions = new Set(
  [...sqlSources.matchAll(/FUNCTION\s+(?:public\.)?([a-zA-Z0-9_]+)\s*\(/gi)].map(
    (match) => match[1],
  ),
);
const inventoryPath = path.join(root,'automation/client-sync/canonical-mutation-inventory.json');
const current = JSON.parse(fs.readFileSync(inventoryPath,'utf8'));
for (const entry of current.registry) {
  const existing = rows.find(row => row.component===entry.component && row.relation===entry.relation);
  if(existing) existing.writers=entry.writers;
  else rows.push({component:entry.component,relation:entry.relation,writers:entry.writers,disposition:'migrate'});
}
const missingWriters = [...new Set(rows.flatMap((row) => row.writers))]
  .filter((writer) => !declaredFunctions.has(writer))
  .sort();
const genericWriters = rows
  .flatMap((row) => row.writers)
  .filter((writer) => /(^|_)(mutate|dispatch|execute)(_|$)/.test(writer));

const publicMaterializerCalls = [
  ...migration.matchAll(/public\.get_public_client_sync_component_v1\s*\(/g),
].length;
// Declaration, shared-finalizer call, REVOKE signature and GRANT signature.
const expectedMaterializerCalls = 4;

const dartFiles = walk(path.join(root, 'lib')).filter((file) =>
  file.endsWith('.dart'),
);
const misplacedCommandStrings = [];
for (const file of dartFiles) {
  const source = fs.readFileSync(file, 'utf8');
  if (!/['"][a-z0-9_]+_client_sync_v1['"]/.test(source)) continue;
  const relative = path.relative(root, file);
  if (
    !relative.endsWith('_commands.dart') &&
    relative !== 'lib/data_services/client_sync/client_sync_remote.dart'
  ) {
    misplacedCommandStrings.push(relative);
  }
}

const ticketOrderHandler = fs.readFileSync(
  path.join(root, 'supabase/functions/send-ticket-order/index.ts'),
  'utf8',
);
const requestHandlerExternalEffects = [
  'deliverEmail',
  'useFakturoid',
  'generateQrCode',
].filter((name) => ticketOrderHandler.includes(name));

const canonical = checkCanonicalInventory(root,dartFiles);
const failures = {
  canonicalInventory: canonical.errors,
  missingWriters,
  genericWriters: [...new Set(genericWriters)].sort(),
  misplacedCommandStrings: misplacedCommandStrings.sort(),
  materializerCallCount:
    publicMaterializerCalls === expectedMaterializerCalls
      ? null
      : publicMaterializerCalls,
  remainingBoundaries: rows
    .filter((row) => row.disposition === 'boundary')
    .map((row) => `${row.component}:${row.relation}`),
  requestHandlerExternalEffects,
};
const failed = Object.values(failures).some((value) =>
  Array.isArray(value) ? value.length > 0 : value !== null,
);
if (failed) {
  console.error(JSON.stringify(failures, null, 2));
  process.exit(1);
}

const boundaries = rows.filter((row) => row.disposition === 'boundary');
console.log(
  `client sync registry: ${rows.length} sources, ${current.legacyFunctions.length} gated legacy contracts, local checks OK`,
);
