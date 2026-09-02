#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  SOURCE_ALIASES,
  SOURCES,
  assertNewEvidencePaths,
  assertPrivateOutput,
  sha256,
  stableJson,
} from './lib.mjs';

export const REQUIRED_FREEZE_LANES = Object.freeze([
  'application',
  'auth-refresh',
  'cron',
  'edge-functions',
  'manual',
  'storage',
  'webhooks',
]);

const MAX_EVIDENCE_AGE_MS = 15 * 60 * 1000;
const MAX_CLOCK_SKEW_MS = 60 * 1000;
const MAX_PROMOTION_WINDOW_MS = 4 * 60 * 60 * 1000;

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function timestamp(value, name) {
  const parsed = Date.parse(value ?? '');
  invariant(Number.isFinite(parsed), `${name} must be an ISO timestamp`);
  return parsed;
}

function exactSources(evidence) {
  invariant(Object.keys(evidence.source_projects ?? {}).sort().join('|') ===
    [...SOURCE_ALIASES].sort().join('|'), 'cutover evidence source set mismatch');
  for (const alias of SOURCE_ALIASES) {
    invariant(evidence.source_projects[alias] === SOURCES[alias],
      `${alias} source project mismatch`);
  }
}

function commonGate(evidence, now) {
  invariant(evidence.version === 1, 'unsupported cutover evidence version');
  exactSources(evidence);
  const observedAt = timestamp(evidence.observed_at, 'observed_at');
  invariant(observedAt <= now + MAX_CLOCK_SKEW_MS, 'cutover evidence is from the future');
  invariant(now - observedAt <= MAX_EVIDENCE_AGE_MS, 'cutover evidence is stale');
  invariant(evidence.writer_inventory?.status === 'complete',
    'writer inventory is not complete');
  invariant(evidence.writer_inventory?.unknown_writers === 0,
    'unknown writers remain');
  invariant(evidence.writer_inventory?.direct_dml_bypasses === 0,
    'direct DML bypasses remain');
  invariant(evidence.target?.writes === 'closed', 'target writes must remain closed');
  invariant(evidence.target?.database &&
    /^festapp_rehearsal_[0-9]{14}$/.test(evidence.target.database),
  'target database must be the exact timestamped promotion candidate');
  invariant(evidence.target?.write_barrier === 'database-default-read-only' &&
    evidence.target?.default_transaction_read_only === true,
  'target database write barrier is not proven closed');
  invariant(evidence.target?.external_side_effects === 'disabled',
    'target external side effects must remain disabled');
  return observedAt;
}

function fullFreezeGate({ evidence, phase, now }) {
  const observedAt = commonGate(evidence, now);
  invariant(evidence.mode === 'full-freeze', 'evidence mode must be full-freeze');
  invariant(evidence.freeze?.status === 'active', 'full write freeze is not active');
  const activatedAt = timestamp(evidence.freeze?.activated_at, 'freeze.activated_at');
  const authActivatedAt = timestamp(
    evidence.freeze?.auth_refresh_activated_at,
    'freeze.auth_refresh_activated_at',
  );
  invariant(activatedAt <= observedAt && authActivatedAt <= observedAt,
    'freeze activation must precede observation');
  invariant(
    JSON.stringify([...(evidence.freeze?.blocked_lanes ?? [])].sort()) ===
      JSON.stringify([...REQUIRED_FREEZE_LANES]),
    'full freeze does not cover every required writer lane',
  );
  for (const alias of SOURCE_ALIASES) {
    invariant(evidence.sources?.[alias]?.active_mutating_sessions === 0,
      `${alias} still has active mutating sessions`);
  }

  if (phase === 'pre-snapshot') {
    invariant(evidence.snapshot?.started_at == null,
      'pre-snapshot gate must run before snapshot acquisition starts');
  } else if (phase === 'final-marker') {
    const snapshotStartedAt = timestamp(evidence.snapshot?.started_at, 'snapshot.started_at');
    invariant(snapshotStartedAt >= activatedAt && snapshotStartedAt >= authActivatedAt,
      'snapshot started before write/Auth refresh freeze');
    for (const alias of SOURCE_ALIASES) {
      invariant(typeof evidence.sources?.[alias]?.final_marker === 'string' &&
        evidence.sources[alias].final_marker.length > 0,
      `${alias} final marker is missing`);
      const imported = evidence.sources[alias].import;
      invariant(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(imported?.run_id ?? ''), `${alias} import run ID is invalid`);
      invariant(/^[0-9a-f]{64}$/.test(imported?.source_schema_fingerprint ?? ''),
        `${alias} source schema fingerprint is invalid`);
      invariant(typeof imported?.transformation_version === 'string' &&
        imported.transformation_version.length > 0,
      `${alias} transformation version is missing`);
      const importedAt = timestamp(imported?.snapshot_at, `${alias}.import.snapshot_at`);
      invariant(importedAt >= activatedAt && importedAt >= authActivatedAt &&
        importedAt <= observedAt,
      `${alias} imported snapshot is outside the frozen evidence window`);
    }
    invariant(evidence.validation?.status === 'pass', 'final data validation is not passing');
    invariant(evidence.validation?.unresolved_conflicts === 0,
      'unresolved conflicts remain');
    invariant(evidence.validation?.orphan_foreign_keys === 0,
      'orphan foreign keys remain');
  } else {
    throw new Error(`unsupported cutover phase: ${phase}`);
  }

  return {
    mode: 'full-freeze',
    phase,
    authorized: true,
    journal_required: false,
    write_freeze_required_until_activation_or_rollback: true,
  };
}

function hybridGate({ evidence, phase, now }) {
  commonGate(evidence, now);
  invariant(evidence.mode === 'journal-hybrid', 'evidence mode must be journal-hybrid');
  const readiness = evidence.hybrid_readiness;
  invariant(readiness?.scope === 'global-write-authority',
    'Flutter-only readiness cannot authorize hybrid cutover');
  invariant(readiness?.validation?.status === 'pass' &&
    readiness.validation.hybrid_activation_authorized === true,
  'hybrid readiness is not authorized');
  invariant((readiness.validation.blockers ?? []).length === 0,
    'hybrid readiness still has blockers');
  invariant(readiness.coverage?.writer_matrix_percent === 100,
    'journal does not cover 100% of the writer matrix');
  invariant(readiness.coverage?.direct_dml_bypasses === 0,
    'hybrid direct DML bypasses remain');
  if (phase === 'final-marker') {
    invariant(evidence.journal?.source_head === evidence.journal?.applied_head,
      'journal source and applied heads differ');
    invariant(evidence.journal?.lag === 0, 'journal lag is non-zero');
    invariant(evidence.journal?.dead_letters === 0, 'journal dead letters remain');
    invariant(evidence.journal?.divergence === 0, 'journal divergence remains');
    invariant(evidence.journal?.external_side_effects_replayed === 0,
      'journal replay triggered external side effects');
  } else if (phase !== 'pre-snapshot') {
    throw new Error(`unsupported cutover phase: ${phase}`);
  }
  return {
    mode: 'journal-hybrid',
    phase,
    authorized: true,
    journal_required: true,
    write_freeze_required_until_activation_or_rollback: phase === 'final-marker',
  };
}

export function evaluateCutoverMode({ mode, phase, evidence, now = Date.now() }) {
  invariant(mode === 'full-freeze' || mode === 'journal-hybrid',
    'mode must be full-freeze or journal-hybrid');
  const decision = mode === 'full-freeze'
    ? fullFreezeGate({ evidence, phase, now })
    : hybridGate({ evidence, phase, now });
  const result = {
    decision_version: 1,
    ...decision,
    source_projects: evidence.source_projects,
    evidence_observed_at: evidence.observed_at,
    gate_mutations_performed: false,
    target_database: evidence.target.database,
  };
  if (phase === 'final-marker' && mode === 'full-freeze') {
    result.authorized_until = new Date(now + MAX_PROMOTION_WINDOW_MS).toISOString();
    result.source_imports = Object.fromEntries(SOURCE_ALIASES.map((alias) => [alias, {
      final_marker: evidence.sources[alias].final_marker,
      ...evidence.sources[alias].import,
    }]));
  }
  return result;
}

function argument(name) {
  const prefix = `--${name}=`;
  return process.argv.find((value) => value.startsWith(prefix))?.slice(prefix.length);
}

async function main() {
  const mode = argument('mode');
  const phase = argument('phase');
  const evidencePath = argument('evidence');
  const outputValue = argument('output');
  invariant(evidencePath && outputValue,
    'usage: cutover-mode-gate.mjs --mode=... --phase=... --evidence=/private/input.json --output=/private/decision.json');
  const output = assertPrivateOutput(outputValue);
  assertNewEvidencePaths([output]);
  const evidence = JSON.parse(fs.readFileSync(path.resolve(evidencePath), 'utf8'));
  const decision = evaluateCutoverMode({ mode, phase, evidence });
  decision.evidence_sha256 = sha256(stableJson(evidence));
  decision.generated_at = new Date().toISOString();
  fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
  fs.writeFileSync(output, `${JSON.stringify(decision, null, 2)}\n`, {
    mode: 0o600,
    flag: 'wx',
  });
  process.stdout.write(`cutover mode gate: mode=${mode}, phase=${phase}, authorized=true\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
