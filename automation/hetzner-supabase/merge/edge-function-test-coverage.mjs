#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const FUNCTIONS_ROOT = path.join(ROOT, 'supabase/functions');
const POLICY_PATH = path.join(ROOT, 'automation/hetzner-supabase/merge/runtime-writer-policy.json');
const MANIFEST_PATH = path.join(FUNCTIONS_ROOT, 'test-coverage.json');

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(absolute) : [absolute];
  });
}

export function discoverDenoTests() {
  return walk(FUNCTIONS_ROOT)
    .filter((file) => /(?:^test_.+|.+_test)\.ts$/.test(path.basename(file)))
    .map((file) => path.relative(ROOT, file))
    .sort();
}

export function evaluateEdgeFunctionTestCoverage() {
  const policy = JSON.parse(fs.readFileSync(POLICY_PATH, 'utf8'));
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
  const discoveredTests = new Set(discoverDenoTests());
  const policyFunctions = new Set(Object.keys(policy.edge_functions));
  const excluded = new Set(Object.keys(policy.canonical_function_security.excluded));
  const production = new Set([...policyFunctions].filter((name) => !excluded.has(name)));
  const mapped = new Set(Object.keys(manifest.production));
  const mappedExcluded = new Set(Object.keys(manifest.excluded));
  const blockers = [];

  const unknownFunctions = [...mapped].filter((name) => !production.has(name));
  const uncoveredFunctions = [...production].filter((name) => !mapped.has(name));
  if (unknownFunctions.length) blockers.push(`unknown production mappings: ${unknownFunctions.join(', ')}`);
  if (uncoveredFunctions.length) blockers.push(`uncovered production Functions: ${uncoveredFunctions.join(', ')}`);

  for (const name of production) {
    const entry = manifest.production[name];
    if (!entry) continue;
    for (const kind of ['smokeTests', 'behaviorTests']) {
      if (!Array.isArray(entry[kind]) || entry[kind].length === 0) {
        blockers.push(`${name} has no ${kind}`);
        continue;
      }
      for (const testFile of entry[kind]) {
        if (!discoveredTests.has(testFile)) blockers.push(`${name} references undiscovered test: ${testFile}`);
      }
    }
  }
  for (const name of excluded) {
    const entry = manifest.excluded[name];
    if (!entry?.reason || !Array.isArray(entry.evidenceTests) || entry.evidenceTests.length === 0) {
      blockers.push(`${name} exclusion lacks reason or evidence tests`);
    }
  }
  for (const name of mappedExcluded) {
    if (!excluded.has(name)) blockers.push(`unknown exclusion mapping: ${name}`);
  }

  return {
    status: blockers.length === 0 ? 'pass' : 'fail',
    productionFunctions: production.size,
    excludedFunctions: excluded.size,
    discoveredTests: discoveredTests.size,
    unknownFunctions,
    uncoveredFunctions,
    blockers,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = evaluateEdgeFunctionTestCoverage();
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (result.status !== 'pass') process.exitCode = 1;
}
