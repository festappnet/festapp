import fs from 'node:fs';
import path from 'node:path';
import { REPOSITORY_ROOT } from './lib.mjs';

const POLICY_PATH = path.join(
  REPOSITORY_ROOT,
  'automation/hetzner-supabase/merge/runtime-writer-policy.json',
);

export function loadRuntimeWriterPolicy(policyPath = POLICY_PATH) {
  return JSON.parse(fs.readFileSync(policyPath, 'utf8'));
}

function discoverEdgeFunctions(root) {
  const functionsRoot = path.join(root, 'supabase/functions');
  if (!fs.existsSync(functionsRoot)) return [];
  return fs.readdirSync(functionsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith('_'))
    .filter((entry) => fs.existsSync(path.join(functionsRoot, entry.name, 'index.ts')))
    .map((entry) => entry.name)
    .sort();
}

function discoverWorkerEntrypoints(root) {
  const workersRoot = path.join(root, 'workers');
  if (!fs.existsSync(workersRoot)) return [];
  const entries = [];
  for (const worker of fs.readdirSync(workersRoot, { withFileTypes: true })) {
    if (!worker.isDirectory()) continue;
    for (const filename of ['index.ts', 'worker.ts']) {
      const relative = `workers/${worker.name}/src/${filename}`;
      if (fs.existsSync(path.join(root, relative))) entries.push(relative);
    }
  }
  return entries.sort();
}

export function evaluateRuntimeWriterPolicy(
  policy = loadRuntimeWriterPolicy(),
  root = REPOSITORY_ROOT,
) {
  const discoveredFunctions = discoverEdgeFunctions(root);
  const declaredFunctions = Object.keys(policy.edge_functions ?? {}).sort();
  const discoveredWorkers = discoverWorkerEntrypoints(root);
  const declaredWorkers = Object.values(policy.workers ?? {})
    .map((entry) => entry.entrypoint)
    .sort();
  const blockers = [];

  if (policy.version !== 1) blockers.push('runtime writer policy version must be 1');
  if (policy.canonical_origin !== 'https://api.festapp.net') {
    blockers.push('runtime writer policy canonical origin is not api.festapp.net');
  }
  for (const name of [
    'mutating_edge_function',
    'read_only_edge_function',
    'mutating_worker',
    'read_only_worker',
  ]) {
    if (!policy.controls?.[name]) blockers.push(`runtime writer control is missing: ${name}`);
  }

  for (const name of discoveredFunctions.filter((name) => !declaredFunctions.includes(name))) {
    blockers.push(`unclassified edge function: ${name}`);
  }
  for (const name of declaredFunctions.filter((name) => !discoveredFunctions.includes(name))) {
    blockers.push(`declared edge function is missing: ${name}`);
  }
  for (const entrypoint of discoveredWorkers.filter((name) => !declaredWorkers.includes(name))) {
    blockers.push(`unclassified worker entrypoint: ${entrypoint}`);
  }
  for (const entrypoint of declaredWorkers.filter((name) => !discoveredWorkers.includes(name))) {
    blockers.push(`declared worker entrypoint is missing: ${entrypoint}`);
  }

  for (const [kind, entries] of [['edge function', policy.edge_functions], ['worker', policy.workers]]) {
    for (const [name, entry] of Object.entries(entries ?? {})) {
      if (!entry.trigger || !Array.isArray(entry.effects) || entry.effects.length === 0 ||
          typeof entry.mutates_authority !== 'boolean') {
        blockers.push(`${kind} policy is incomplete: ${name}`);
      }
      if (kind === 'worker' &&
          (!entry.deployment_contract || !fs.existsSync(path.join(root, entry.deployment_contract)))) {
        blockers.push(`worker deployment contract is missing: ${name}`);
      }
    }
  }

  const security = policy.canonical_function_security ?? {};
  for (const [name, reason] of Object.entries(security.blocked ?? {})) {
    if (!declaredFunctions.includes(name)) blockers.push(`security blocker names unknown function: ${name}`);
    if (!reason) blockers.push(`security blocker has no reason: ${name}`);
  }
  for (const [name, reason] of Object.entries(security.excluded ?? {})) {
    if (!declaredFunctions.includes(name)) blockers.push(`production exclusion names unknown function: ${name}`);
    if (!reason) blockers.push(`production exclusion has no reason: ${name}`);
  }
  for (const [name, evidence] of Object.entries(security.resolved ?? {})) {
    if (!declaredFunctions.includes(name)) blockers.push(`resolved security entry names unknown function: ${name}`);
    if (!evidence) blockers.push(`resolved security entry has no evidence: ${name}`);
  }
  if (!Array.isArray(policy.activation_requirements) || policy.activation_requirements.length === 0 ||
      policy.activation_requirements.some((requirement) => typeof requirement !== 'string' || !requirement)) {
    blockers.push('runtime activation requirements are missing or invalid');
  }

  return {
    status: blockers.length === 0 ? 'pass' : 'blocked',
    blockers,
    edge_functions: discoveredFunctions.length,
    worker_entrypoints: discoveredWorkers.length,
    mutating_surfaces: [
      ...Object.values(policy.edge_functions ?? {}),
      ...Object.values(policy.workers ?? {}),
    ].filter((entry) => entry.mutates_authority).length,
    canonical_security_blockers: Object.entries(security.blocked ?? {})
      .map(([name, reason]) => `${name}: ${reason}`),
    canonical_exclusions: Object.entries(security.excluded ?? {})
      .map(([name, reason]) => `${name}: ${reason}`),
    activation_requirements: policy.activation_requirements ?? [],
  };
}
