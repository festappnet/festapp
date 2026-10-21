#!/usr/bin/env node
import fs from 'node:fs';
import {
  SOURCES,
  assertNewEvidencePaths,
  assertPrivateOutput,
  sha256,
  stableJson,
} from './lib.mjs';

const applicationSchemas = new Set(['public', 'eshop']);

function key(value) {
  return `${value.schema_name}.${value.table_name}`;
}

function columnShape(value) {
  return {
    data_type: value.data_type,
    udt_schema: value.udt_schema,
    udt_name: value.udt_name,
    is_identity: value.is_identity,
    identity_generation: value.identity_generation,
    is_generated: value.is_generated,
  };
}

function columnsByTable(catalog) {
  const result = new Map();
  for (const column of catalog.columns ?? []) {
    if (!applicationSchemas.has(column.schema_name)) continue;
    const tableKey = key(column);
    if (!result.has(tableKey)) result.set(tableKey, new Map());
    result.get(tableKey).set(column.column_name, column);
  }
  return result;
}

function sourceTables(catalog) {
  return (catalog.relations ?? []).filter((relation) =>
    applicationSchemas.has(relation.schema_name) && ['r', 'p'].includes(relation.relkind));
}

function compareTable({ relation, sourceColumns, targetColumns, rowCount }) {
  if (!targetColumns) {
    return {
      table: key(relation), source_rows: rowCount, status: 'blocked-target-table-missing',
      source_only_columns: [...sourceColumns.keys()].sort(), target_only_columns: [], incompatible_columns: [],
      compatible_definition_drift: [], required_target_values: [],
    };
  }
  const names = [...new Set([...sourceColumns.keys(), ...targetColumns.keys()])].sort();
  const sourceOnly = [];
  const targetOnly = [];
  const incompatible = [];
  const compatibleDefinitionDrift = [];
  const requiredTargetValues = [];
  for (const name of names) {
    const source = sourceColumns.get(name);
    const target = targetColumns.get(name);
    if (!target) {
      sourceOnly.push(name);
      continue;
    }
    if (!source) {
      targetOnly.push(name);
      if (target.is_nullable === 'NO' && target.column_default == null &&
          target.is_identity === 'NO' && target.is_generated === 'NEVER') {
        requiredTargetValues.push(name);
      }
      continue;
    }
    const targetTightensNullability = source.is_nullable === 'YES' && target.is_nullable === 'NO';
    if (stableJson(columnShape(source)) !== stableJson(columnShape(target)) || targetTightensNullability) {
      incompatible.push(name);
    } else if (source.column_default !== target.column_default || source.is_nullable !== target.is_nullable) {
      compatibleDefinitionDrift.push(name);
    }
  }
  const status = requiredTargetValues.length > 0 || incompatible.length > 0
    ? 'blocked-transform-required'
    : sourceOnly.length > 0 ? 'review-source-only-columns' : 'shape-compatible';
  return {
    table: key(relation), source_rows: rowCount, status,
    source_only_columns: sourceOnly,
    target_only_columns: targetOnly,
    incompatible_columns: incompatible,
    compatible_definition_drift: compatibleDefinitionDrift,
    required_target_values: requiredTargetValues,
  };
}

export function buildTableImportReadiness({ inventory, targetCatalog }) {
  const alias = inventory.source?.alias;
  if (SOURCES[alias] !== inventory.source?.project_ref) throw new Error('unapproved source identity');
  const targetRelations = new Set(sourceTables(targetCatalog).map(key));
  const sourceColumnMap = columnsByTable(inventory.catalog);
  const targetColumnMap = columnsByTable(targetCatalog);
  const tables = sourceTables(inventory.catalog).map((relation) => compareTable({
    relation,
    sourceColumns: sourceColumnMap.get(key(relation)) ?? new Map(),
    targetColumns: targetRelations.has(key(relation)) ? targetColumnMap.get(key(relation)) ?? new Map() : null,
    rowCount: inventory.exact_row_counts?.[key(relation)] ?? null,
  })).sort((left, right) => left.table.localeCompare(right.table));
  const statusCounts = Object.fromEntries([...new Set(tables.map((table) => table.status))].sort().map((status) => [
    status,
    tables.filter((table) => table.status === status).length,
  ]));
  const report = {
    report_version: 1,
    generated_at: new Date().toISOString(),
    source: inventory.source,
    target: { kind: 'isolated-self-hosted-canonical-rehearsal', postgres_version: targetCatalog.postgres_version },
    tables,
    summary: {
      source_tables: tables.length,
      source_rows: tables.reduce((sum, table) => sum + (table.source_rows ?? 0), 0),
      status_counts: statusCounts,
      blocked_tables: tables.filter((table) => table.status.startsWith('blocked')).length,
    },
    validation: {
      status: tables.some((table) => table.status !== 'shape-compatible') ? 'blocked' : 'ready',
      production_mutations_performed: false,
    },
  };
  report.report_sha256 = sha256(stableJson(report));
  return report;
}

function main() {
  const [inventoryPath, targetPath, outputPath] = process.argv.slice(2);
  if (!inventoryPath || !targetPath || !outputPath) {
    throw new Error('usage: table-import-readiness.mjs SOURCE-INVENTORY.json TARGET-CATALOG.json OUTPUT.json');
  }
  const output = assertPrivateOutput(outputPath);
  assertNewEvidencePaths([output]);
  const report = buildTableImportReadiness({
    inventory: JSON.parse(fs.readFileSync(inventoryPath, 'utf8')),
    targetCatalog: JSON.parse(fs.readFileSync(targetPath, 'utf8')),
  });
  fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write(`${report.source.alias} table readiness: tables=${report.summary.source_tables} blocked=${report.summary.blocked_tables} report=${report.report_sha256}\n`);
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
