#!/usr/bin/env node
import fs from 'node:fs';
import { SOURCE_ALIASES, SOURCES, sha256, stableJson } from './lib.mjs';

function readInventory(filePath) {
  const value = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (SOURCES[value.source?.alias] !== value.source?.project_ref) {
    throw new Error(`${filePath}: unapproved source identity`);
  }
  return value;
}

function keyed(values, keys) {
  return new Map(values.map((value) => [keys.map((key) => value[key]).join('|'), value]));
}

function differences(leftValues, rightValues, keys) {
  const left = keyed(leftValues, keys);
  const right = keyed(rightValues, keys);
  const names = [...new Set([...left.keys(), ...right.keys()])].sort();
  return names.flatMap((name) => {
    const base = left.get(name);
    const source = right.get(name);
    if (base && source && stableJson(base) === stableJson(source)) return [];
    return [{ key: name, base: base ?? null, source: source ?? null }];
  });
}

function structuralRelations(values) {
  return values.map(({ total_bytes, estimated_rows, ...relation }) => relation);
}

function compare(baseInventory, sourceInventory) {
  const result = {
    relations: differences(structuralRelations(baseInventory.catalog.relations), structuralRelations(sourceInventory.catalog.relations), ['schema_name', 'table_name']),
    columns: differences(baseInventory.catalog.columns, sourceInventory.catalog.columns, ['schema_name', 'table_name', 'column_name']),
    constraints: differences(baseInventory.catalog.constraints, sourceInventory.catalog.constraints, ['schema_name', 'table_name', 'constraint_name']),
    routines: differences(baseInventory.catalog.routines, sourceInventory.catalog.routines, ['schema_name', 'routine_name', 'identity_arguments']),
    policies: differences(baseInventory.catalog.policies, sourceInventory.catalog.policies, ['schema_name', 'table_name', 'policy_name']),
    grants: differences(baseInventory.catalog.grants ?? [], sourceInventory.catalog.grants ?? [], ['schema_name', 'table_name', 'grantee', 'privilege_type']),
    extensions: differences(baseInventory.catalog.extensions, sourceInventory.catalog.extensions, ['name']),
    publications: differences(baseInventory.catalog.publications ?? [], sourceInventory.catalog.publications ?? [], ['name']),
    roles: differences(baseInventory.catalog.roles ?? [], sourceInventory.catalog.roles ?? [], ['name']),
    collations: differences(baseInventory.catalog.collations ?? [], sourceInventory.catalog.collations ?? [], ['schema_name', 'name']),
  };
  return {
    source_fingerprint: sourceInventory.schema_fingerprint_sha256,
    postgres_version: sourceInventory.catalog.postgres_version,
    same_postgres_major: String(baseInventory.catalog.postgres_version_num).slice(0, 2) ===
      String(sourceInventory.catalog.postgres_version_num).slice(0, 2),
    differences: result,
    unresolved_schema_drift: Object.values(result).reduce((sum, values) => sum + values.length, 0),
  };
}

export function buildSchemaFingerprintReport(inventories) {
  const baseInventory = inventories.default;
  if (!baseInventory || baseInventory.source?.alias !== 'default') {
    throw new Error('default inventory must be the canonical comparison base');
  }
  const missing = SOURCE_ALIASES.filter((alias) => !inventories[alias]);
  if (missing.length > 0) throw new Error(`inventories are missing approved sources: ${missing.join(', ')}`);
  const comparisons = Object.fromEntries(SOURCE_ALIASES.filter((alias) => alias !== 'default').map((alias) => [
    alias,
    compare(baseInventory, inventories[alias]),
  ]));
  const report = {
    report_version: 2,
    generated_at: new Date().toISOString(),
    base_source: 'default',
    source_fingerprints: Object.fromEntries(SOURCE_ALIASES.map((alias) => [
      alias,
      inventories[alias].schema_fingerprint_sha256,
    ])),
    postgres: Object.fromEntries(SOURCE_ALIASES.map((alias) => [
      alias,
      inventories[alias].catalog.postgres_version,
    ])),
    comparisons,
  };
  report.unresolved_schema_drift = Object.values(comparisons)
    .reduce((sum, comparison) => sum + comparison.unresolved_schema_drift, 0);
  report.report_sha256 = sha256(stableJson(report));
  return report;
}

const paths = process.argv.slice(2);
if (paths.length !== SOURCE_ALIASES.length) {
  throw new Error(`usage: schema-fingerprint.mjs ${SOURCE_ALIASES.map((alias) => `${alias.toUpperCase()}_INVENTORY`).join(' ')}`);
}
const inventories = Object.fromEntries(paths.map((filePath) => {
  const inventory = readInventory(filePath);
  return [inventory.source.alias, inventory];
}));
const report = buildSchemaFingerprintReport(inventories);
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
