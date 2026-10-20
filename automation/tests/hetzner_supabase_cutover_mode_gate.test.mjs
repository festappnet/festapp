#!/usr/bin/env node
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  REQUIRED_FREEZE_LANES,
  evaluateCutoverMode,
} from '../hetzner-supabase/merge/cutover-mode-gate.mjs';
import {
  SOURCE_ALIASES,
  SOURCES,
} from '../hetzner-supabase/merge/lib.mjs';

const now = Date.parse('2026-08-28T12:00:00Z');

function fullFreezeEvidence() {
  return {
    version: 1,
    mode: 'full-freeze',
    observed_at: '2026-08-28T11:59:00Z',
    source_projects: { ...SOURCES },
    writer_inventory: { status: 'complete', unknown_writers: 0, direct_dml_bypasses: 0 },
    freeze: {
      status: 'active',
      activated_at: '2026-08-28T11:55:00Z',
      auth_refresh_activated_at: '2026-08-28T11:54:00Z',
      blocked_lanes: [...REQUIRED_FREEZE_LANES],
    },
    sources: Object.fromEntries(SOURCE_ALIASES.map((alias) => [alias, {
      active_mutating_sessions: 0,
      final_marker: `${alias}-final-marker`,
      import: {
        run_id: `${alias === 'default' ? '10000000' : alias === 'a' ? '20000000' : '30000000'}-0000-4000-8000-000000000000`,
        snapshot_at: '2026-08-28T11:57:00Z',
        source_schema_fingerprint: 'a'.repeat(64),
        transformation_version: `${alias}-import-v1`,
      },
    }])),
    target: {
      database: 'festapp_rehearsal_20260828115700',
      writes: 'closed',
      write_barrier: 'database-default-read-only',
      default_transaction_read_only: true,
      external_side_effects: 'disabled',
    },
    snapshot: { started_at: null },
    validation: { status: 'pass', unresolved_conflicts: 0, orphan_foreign_keys: 0 },
  };
}

test('full-freeze pre-snapshot gate requires every writer lane and no snapshot start', () => {
  const decision = evaluateCutoverMode({
    mode: 'full-freeze', phase: 'pre-snapshot', evidence: fullFreezeEvidence(), now,
  });
  assert.equal(decision.authorized, true);
  assert.equal(decision.journal_required, false);
  assert.equal(decision.write_freeze_required_until_activation_or_rollback, true);
});

test('full-freeze final-marker gate proves freeze-before-snapshot and validated markers', () => {
  const evidence = fullFreezeEvidence();
  evidence.snapshot.started_at = '2026-08-28T11:56:00Z';
  const decision = evaluateCutoverMode({
    mode: 'full-freeze', phase: 'final-marker', evidence, now,
  });
  assert.equal(decision.authorized, true);
  assert.equal(decision.target_database, evidence.target.database);
  assert.equal(decision.source_imports.a.final_marker, 'a-final-marker');
  assert.equal(decision.authorized_until, '2026-08-28T16:00:00.000Z');
});

test('full-freeze rejects missing lanes, active writers, stale evidence and early snapshot', () => {
  for (const mutate of [
    (value) => value.freeze.blocked_lanes.pop(),
    (value) => { value.sources.a.active_mutating_sessions = 1; },
    (value) => { value.observed_at = '2026-08-28T11:00:00Z'; },
    (value) => { value.snapshot.started_at = '2026-08-28T11:53:00Z'; },
    (value) => { value.target.default_transaction_read_only = false; },
    (value) => { value.sources.a.import.run_id = 'not-a-uuid'; },
    (value) => { value.sources.a.import.snapshot_at = '2026-08-28T11:53:00Z'; },
  ]) {
    const evidence = fullFreezeEvidence();
    evidence.snapshot.started_at = '2026-08-28T11:56:00Z';
    mutate(evidence);
    assert.throws(() => evaluateCutoverMode({
      mode: 'full-freeze', phase: 'final-marker', evidence, now,
    }));
  }
});

test('Flutter-only hybrid readiness can never authorize hybrid cutover', () => {
  const evidence = fullFreezeEvidence();
  evidence.mode = 'journal-hybrid';
  evidence.hybrid_readiness = {
    scope: 'flutter-direct-dml-rpc-seam-only',
    validation: { status: 'pass', hybrid_activation_authorized: true, blockers: [] },
    coverage: { writer_matrix_percent: 100, direct_dml_bypasses: 0 },
  };
  assert.throws(() => evaluateCutoverMode({
    mode: 'journal-hybrid', phase: 'pre-snapshot', evidence, now,
  }), /Flutter-only readiness/);
});

test('global hybrid final marker requires exact head, zero lag and no replayed effects', () => {
  const evidence = fullFreezeEvidence();
  evidence.mode = 'journal-hybrid';
  evidence.hybrid_readiness = {
    scope: 'global-write-authority',
    validation: { status: 'pass', hybrid_activation_authorized: true, blockers: [] },
    coverage: { writer_matrix_percent: 100, direct_dml_bypasses: 0 },
  };
  evidence.journal = {
    source_head: '42', applied_head: '42', lag: 0, dead_letters: 0,
    divergence: 0, external_side_effects_replayed: 0,
  };
  assert.equal(evaluateCutoverMode({
    mode: 'journal-hybrid', phase: 'final-marker', evidence, now,
  }).authorized, true);
  evidence.journal.applied_head = '41';
  assert.throws(() => evaluateCutoverMode({
    mode: 'journal-hybrid', phase: 'final-marker', evidence, now,
  }), /heads differ/);
});
