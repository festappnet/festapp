#!/usr/bin/env node

import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  REPOSITORY_ROOT,
  SOURCES,
  sha256,
  stableJson,
} from './lib.mjs';
import {
  buildTenantConfigInventory,
  discoverProductionTenantConfigs,
  loadTenantCutoverPolicy,
} from './tenant-config-inventory.mjs';
import { buildWriteInventory } from './write-authority-inventory.mjs';
import {
  evaluateRuntimeWriterPolicy,
  loadRuntimeWriterPolicy,
} from './runtime-writer-policy.mjs';

const RUNTIME_DIR = path.join(REPOSITORY_ROOT, 'automation/hetzner-supabase/runtime');
const CORE_OPERATIONAL_REQUIREMENTS = Object.freeze([
  'all active web/iOS/Android lanes are adopted, technically read-only, or retired with fresh evidence',
  'the private operational readiness gate passes with independent backup, monitoring, alert, DNS/TLS, capacity, integration and rollback evidence',
  'installed host tooling and runtime inputs match the approved repository and private runtime contract',
  'a named maintenance window and all seven rehearsed freeze-lane owners are active',
  'fresh pre-snapshot and final-marker decisions bind the exact frozen source snapshots to the promotion target',
  'an encrypted off-host promotion backup and isolated restore reproduce the exact final import inventory',
  'the target database write barrier remains closed until a separate final activation go/no-go',
]);

function git(args, options = {}) {
  return spawnSync('git', args, {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options,
  });
}

function currentGitState(tenantEntries) {
  const head = execFileSync('git', ['rev-parse', 'HEAD'], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
  }).trim();
  const originMain = execFileSync('git', ['rev-parse', 'origin/main'], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
  }).trim();
  const branch = execFileSync('git', ['branch', '--show-current'], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
  }).trim();
  const dirtyPaths = execFileSync('git', ['status', '--porcelain'], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
  }).trim().split(/\r?\n/).filter(Boolean).map((line) => line.slice(3));
  const activeBranchesBehindMain = tenantEntries
    .filter((entry) => entry.status === 'discovered')
    .map((entry) => entry.branch)
    .filter((ref) => git(['merge-base', '--is-ancestor', 'origin/main', ref]).status !== 0);
  return { branch, head, origin_main: originMain, dirty_paths: dirtyPaths, active_branches_behind_main: activeBranchesBehindMain };
}

function runtimePinState() {
  const pins = JSON.parse(fs.readFileSync(path.join(RUNTIME_DIR, 'pins.json'), 'utf8'));
  const compose = fs.readFileSync(path.join(RUNTIME_DIR, 'docker-compose.festapp.yml'), 'utf8');
  const missingImages = Object.entries(pins.supabase.images)
    .filter(([, image]) => !compose.includes(`image: ${image}`))
    .map(([name]) => name);
  const verifier = spawnSync('node', [path.join(RUNTIME_DIR, 'verify-pins.mjs')], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
  });
  return {
    release: pins.supabase.release,
    architecture: pins.architecture,
    checked_at: pins.checkedAt,
    offline_verifier_passed: verifier.status === 0,
    missing_compose_images: missingImages,
  };
}

function tenantPolicyState(policy) {
  const blockers = [];
  for (const [ref, disposition] of Object.entries(policy.legacy_refs)) {
    if (git(['show-ref', '--verify', '--quiet', `refs/remotes/${ref}`]).status !== 0) {
      blockers.push(`tenant policy ref does not exist: ${ref}`);
    }
    if (git(['show-ref', '--verify', '--quiet', `refs/remotes/${disposition.replacement}`]).status !== 0) {
      blockers.push(`${ref} replacement ref does not exist: ${disposition.replacement}`);
    }
    const evidenceDoc = path.resolve(REPOSITORY_ROOT, disposition.evidence_doc ?? '');
    if (!disposition.evidence_doc || !evidenceDoc.startsWith(`${REPOSITORY_ROOT}${path.sep}`) ||
        !fs.existsSync(evidenceDoc)) {
      blockers.push(`${ref} evidence document is missing or outside the repository`);
    }
    if (disposition.closure === 'closed') {
      if (!/^[0-9a-f]{40}$/.test(disposition.evidence_commit ?? '') ||
          git(['merge-base', '--is-ancestor', disposition.evidence_commit, ref]).status !== 0) {
        blockers.push(`${ref} closed disposition is not backed by an ancestor evidence commit`);
      }
    }
  }
  for (const ref of Object.keys(policy.broad_source_refs)) {
    if (git(['show-ref', '--verify', '--quiet', `refs/remotes/${ref}`]).status !== 0) {
      blockers.push(`broad-source policy ref does not exist: ${ref}`);
    }
  }
  return { valid: blockers.length === 0, blockers };
}

export function evaluateRepositoryCutoverReadiness({
  gitState,
  tenantInventory,
  writerInventory,
  runtimePins,
  tenantPolicy,
  runtimeWriterPolicy,
}) {
  const blockers = [];
  if (gitState.branch !== 'main') blockers.push(`repository branch is ${gitState.branch || 'detached'}, expected main`);
  if (gitState.head !== gitState.origin_main) blockers.push('HEAD does not equal origin/main');
  if (gitState.dirty_paths.length > 0) blockers.push(`working tree has ${gitState.dirty_paths.length} changed paths`);
  for (const ref of gitState.active_branches_behind_main) blockers.push(`${ref} does not contain origin/main`);
  if (writerInventory.validation.status !== 'pass' || writerInventory.validation.unknown_writers !== 0) {
    blockers.push('repository writer inventory is incomplete');
  }
  if (tenantInventory.counts.unknown !== 0 || tenantInventory.validation.status === 'fail') {
    blockers.push('production tenant inventory has an unknown or unclassified ref');
  }
  if (!runtimePins.offline_verifier_passed || runtimePins.missing_compose_images.length > 0) {
    blockers.push('runtime pins and compose file are incoherent');
  }
  if (!tenantPolicy.valid) blockers.push(...tenantPolicy.blockers);
  if (runtimeWriterPolicy.status !== 'pass') blockers.push(...runtimeWriterPolicy.blockers);
  for (const blocker of runtimeWriterPolicy.canonical_security_blockers) {
    blockers.push(`canonical Function security is unresolved: ${blocker}`);
  }

  return {
    contract_version: 1,
    canonical_origin: 'https://api.festapp.net',
    source_projects: SOURCES,
    selected_cutover_mode: 'full-freeze',
    repository_ready: blockers.length === 0,
    production_cutover_authorized: false,
    blockers,
    operational_blockers: [
      ...CORE_OPERATIONAL_REQUIREMENTS,
      ...tenantInventory.validation.blockers,
      ...runtimeWriterPolicy.activation_requirements,
    ],
    summaries: {
      writer_candidates: writerInventory.entries.length,
      unknown_writers: writerInventory.validation.unknown_writers,
      direct_dml_candidates: writerInventory.validation.direct_dml_candidates,
      production_refs: tenantInventory.counts.production_configs,
      unknown_tenants: tenantInventory.counts.unknown,
      pending_legacy_retirements: tenantInventory.counts.pending_legacy_retirements,
      live_freeze_required: tenantInventory.counts.live_freeze_required,
      runtime_release: runtimePins.release,
      edge_functions: runtimeWriterPolicy.edge_functions,
      worker_entrypoints: runtimeWriterPolicy.worker_entrypoints,
      mutating_runtime_surfaces: runtimeWriterPolicy.mutating_surfaces,
      canonical_function_security_blockers:
        runtimeWriterPolicy.canonical_security_blockers.length,
      canonical_function_exclusions: runtimeWriterPolicy.canonical_exclusions.length,
      runtime_activation_requirements: runtimeWriterPolicy.activation_requirements.length,
    },
  };
}

async function main() {
  const tenantEntries = discoverProductionTenantConfigs();
  const policy = loadTenantCutoverPolicy();
  const tenantInventory = buildTenantConfigInventory(tenantEntries, policy);
  const result = evaluateRepositoryCutoverReadiness({
    gitState: currentGitState(tenantEntries),
    tenantInventory,
    writerInventory: buildWriteInventory(),
    runtimePins: runtimePinState(),
    tenantPolicy: tenantPolicyState(policy),
    runtimeWriterPolicy: evaluateRuntimeWriterPolicy(loadRuntimeWriterPolicy()),
  });
  result.generated_at = new Date().toISOString();
  result.report_sha256 = sha256(stableJson(result));
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.repository_ready) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
