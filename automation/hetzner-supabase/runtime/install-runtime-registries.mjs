#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function keyed(values, key, name) {
  invariant(Array.isArray(values), `${name} must be an array`);
  const result = new Map();
  for (const value of values) {
    const id = key(value);
    invariant(typeof id === 'string' && id.length > 0 && !result.has(id),
      `${name} contains an invalid or duplicate key`);
    result.set(id, value);
  }
  return result;
}

export function validateAdditiveRegistryUpgrade({
  candidateSource,
  installedSource,
  candidateReference,
  installedReference,
}) {
  invariant(candidateSource.version === 1, 'unsupported candidate source registry');
  invariant(installedSource.version === 1, 'unsupported installed source registry');
  const candidateSources = keyed(candidateSource.sources, (value) => value.alias, 'candidate sources');
  const installedSources = keyed(installedSource.sources, (value) => value.alias, 'installed sources');
  for (const [alias, installed] of installedSources) {
    invariant(candidateSources.has(alias), `source registry would remove ${alias}`);
    invariant(stableJson(candidateSources.get(alias)) === stableJson(installed),
      `source registry would mutate ${alias}`);
  }

  invariant(typeof candidateReference.version === 'string' &&
    typeof installedReference.version === 'string', 'unsupported reference registry');
  const referenceKey = (value) => `${value.table}\u0000${value.path}`;
  const candidateRules = keyed(candidateReference.rules, referenceKey, 'candidate reference rules');
  const installedRules = keyed(installedReference.rules, referenceKey, 'installed reference rules');
  for (const [key, installed] of installedRules) {
    invariant(candidateRules.has(key), `reference registry would remove ${key.replace('\u0000', '.')}`);
    invariant(stableJson(candidateRules.get(key)) === stableJson(installed),
      `reference registry would mutate ${key.replace('\u0000', '.')}`);
  }
  invariant(candidateSource.sources.length >= installedSource.sources.length,
    'source registry upgrade is not additive');
  invariant(candidateReference.rules.length >= installedReference.rules.length,
    'reference registry upgrade is not additive');
  for (const field of ['requiredInventoryFamilies', 'cutoverGates']) {
    const candidateValues = new Set(exactStringArray(candidateReference[field], `candidate ${field}`));
    const installedValues = exactStringArray(installedReference[field], `installed ${field}`);
    invariant(installedValues.every((value) => candidateValues.has(value)),
      `reference registry would remove ${field} entries`);
  }
  return {
    source_changed: stableJson(candidateSource) !== stableJson(installedSource),
    reference_changed: stableJson(candidateReference) !== stableJson(installedReference),
    added_sources: [...candidateSources.keys()].filter((key) => !installedSources.has(key)).sort(),
    added_reference_rules: [...candidateRules.keys()].filter((key) => !installedRules.has(key)).length,
  };
}

function exactStringArray(values, name) {
  invariant(Array.isArray(values) && values.every((value) =>
    typeof value === 'string' && value.length > 0), `${name} must contain strings`);
  invariant(new Set(values).size === values.length, `${name} contains duplicates`);
  return values;
}

function stageJson(sourcePath, targetPath) {
  const parsed = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
  const rendered = `${JSON.stringify(parsed, null, 2)}\n`;
  const staged = `${targetPath}.new-${process.pid}`;
  fs.writeFileSync(staged, rendered, { mode: 0o444, flag: 'wx' });
  fs.chmodSync(staged, 0o444);
  return staged;
}

function atomicInstallJson(sourcePath, targetPath) {
  fs.renameSync(stageJson(sourcePath, targetPath), targetPath);
}

function argument(name) {
  const prefix = `--${name}=`;
  return process.argv.find((value) => value.startsWith(prefix))?.slice(prefix.length);
}

async function main() {
  const candidateSourcePath = argument('candidate-source');
  const candidateReferencePath = argument('candidate-reference');
  const installedSourcePath = argument('installed-source');
  const installedReferencePath = argument('installed-reference');
  for (const [name, value] of Object.entries({
    candidateSourcePath, candidateReferencePath, installedSourcePath, installedReferencePath,
  })) invariant(value && path.isAbsolute(value), `${name} must be an absolute path`);
  const sourceExists = fs.existsSync(installedSourcePath);
  const referenceExists = fs.existsSync(installedReferencePath);
  invariant(sourceExists === referenceExists,
    'installed registries are in a forbidden partial state');
  const candidateSource = JSON.parse(fs.readFileSync(candidateSourcePath, 'utf8'));
  const candidateReference = JSON.parse(fs.readFileSync(candidateReferencePath, 'utf8'));
  if (!sourceExists) {
    invariant(process.argv.includes('--allow-bootstrap'),
      'both installed registries are absent; explicit bootstrap is required');
    const bootstrapPlan = validateAdditiveRegistryUpgrade({
      candidateSource,
      installedSource: { version: candidateSource.version, sources: [] },
      candidateReference,
      installedReference: {
        version: candidateReference.version,
        rules: [],
        requiredInventoryFamilies: [],
        cutoverGates: [],
      },
    });
    // Stage and validate both complete files before either canonical pathname
    // becomes visible. Both renames are same-filesystem atomic operations.
    const stagedSource = stageJson(candidateSourcePath, installedSourcePath);
    const stagedReference = stageJson(candidateReferencePath, installedReferencePath);
    try {
      fs.renameSync(stagedSource, installedSourcePath);
      fs.renameSync(stagedReference, installedReferencePath);
    } catch (error) {
      // Restore the all-absent state if the second atomic rename cannot finish.
      if (fs.existsSync(installedSourcePath) && !fs.existsSync(installedReferencePath)) {
        fs.renameSync(installedSourcePath, stagedSource);
      }
      throw error;
    }
    process.stdout.write(`${JSON.stringify({
      bootstrap: true,
      ...bootstrapPlan,
      deleted_entries: 0,
    })}\n`);
    return;
  }
  const installedSource = JSON.parse(fs.readFileSync(installedSourcePath, 'utf8'));
  const installedReference = JSON.parse(fs.readFileSync(installedReferencePath, 'utf8'));
  const result = validateAdditiveRegistryUpgrade({
    candidateSource, installedSource, candidateReference, installedReference,
  });
  if (result.source_changed) atomicInstallJson(candidateSourcePath, installedSourcePath);
  if (result.reference_changed) atomicInstallJson(candidateReferencePath, installedReferencePath);
  process.stdout.write(`${JSON.stringify({ bootstrap: false, ...result, deleted_entries: 0 })}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  });
}
