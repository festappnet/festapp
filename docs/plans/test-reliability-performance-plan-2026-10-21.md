# Reliable, faster Festapp tests - reconciled with canonical main

Date: 2026-10-21
Status: Ready for local implementation after canonical-main preflight
Verification: standard for auth, image validation, shared fixtures and runner behavior.

## Outcome and corrected starting point

Restore any remaining test failures and reduce measured Flutter feedback time
without weakening coverage. Work from current canonical main, preserving recent
fixes, rather than implementing the original repair list against an old checkout.
No implementation, merge, commit, push or production operation is part of planning.

**This revision supersedes the initial plan.** The audit ran in
`/Users/miakh/source/festapp`, branch `feat/occasion-setup-wizard-20261007`,
HEAD `eb2304724`. Its test-input fingerprint remains exactly
`91a12b75029f8fdafe7f058e5bcabf14cf1480fe44bd82eba3c60b6c4a0327ac`.
It describes that heavily modified worktree, not current main.

Canonical main inspected read-only in
`/Users/miakh/source/festapp-wizard-release-main-20261019` is `1c8b5a219`.
Other worktrees contain newer in-progress/release work too. No changes were
merged between worktrees and no tests were rerun for this reconciliation.
Recheck the main SHA and affected files once at implementation start.

Historical evidence: [audit](../development/test-performance-audit-2026-10-21.md)
and [receipt](../development/test-performance-audit-2026-10-21.json).
The 71.83 s client / 65.79 s Flutter / 15 failures / 18 roots observations are
**not current-main measurements**. Current main has 68 Flutter roots; this proves
source drift, not a runtime regression. Its present timing and failure count
remain unknown. Historical 29.87 s used two workers on different source.

## Changes already present - reuse, do not redo

| Area | Confirmed current-main evidence | Plan correction |
| --- | --- | --- |
| PNG pixel-cap fixture | `html_media_service_cases.dart` now uses 7000 x 7000 instead of 5000 x 5000, exceeding the actual 40 MP cap | Do not recreate this repair; include it in current baseline |
| PNG/GIF upload expectations | `html_media_upload_contract_cases.dart` now asserts `profile=standard` and absence of `maxBytes` | Preserve the current Worker profile contract |
| Sign-in-code login | `AuthService.login` exchanges six-digit input through `exchange-sign-in-code`, accepts refresh token, otherwise falls back to tenant-prefixed password Auth | Preserve exchange tests and behavior. The original plan to replace them with password-only assertions is withdrawn |
| Payment-default fixtures | `form_payment_defaults_cases.dart` supplies editor rights and an owned bank-change notifier | Do not assume a toast cleanup patch is still needed |
| Blueprint-capacity fixture | `form_blueprint_capacity_cases.dart` now exercises `FormCapacitySettings` with explicit edit permission | Preserve the current component scenario; investigate only if it still fails |
| Price wave tests | `product_price_scheduling_cases.dart` follows the changed dialogs and uses `OrdersStrings.waveHidden` | Do not reapply old finder corrections |
| Ticket palette tests | `ticket_layout_cases.dart` now follows expandable controls and uses stable color keys/current palette actions | Preserve current UI tests; no assertion that all three pass without running them |
| Font catalog fixture | `_Fonts` implements `previewStyle` | Changed interface is handled; runtime retry scenario still needs baseline confirmation |
| Wrapper status | `test_all.sh` has `failed_suites`, counts web/integration/client failures, exits nonzero, and restores root between scopes | Reuse existing aggregation instead of replacing it as if missing |
| Classification/inventory | Classification includes newer roots; inventory has explicit `canonical_main_retirements` for four obsolete ticket-background cases | Do not restore obsolete image helper or invent another retirement mechanism; establish only current discrepancies |

Representative commits: `e8b0b495a` integrates portable architecture and fixture/
image expectation corrections; `b67cb0c66` reconciles auth contracts;
`a84943066` updates price dialogs; `334717125` updates ticket UI contracts;
`5b82540b6` improves wrapper failure reporting. These identify existing owners,
not instructions to cherry-pick entire overlapping commits.

## Scope and invariants

In scope: current-main failures, semantic discovery, runner concurrency/timing/
timeout lifecycle, and small evidence-backed Flutter loading/body improvements.
Out of scope: restoring old contracts, unrelated UI redesign, SQL scheduler
rewrites, new authentication schemes, production/deployment, dependency upgrades
and broad architecture projects. SQL and worker duration remain unmeasured.

- One Flutter task across the workstation, always `--concurrency=1`. Check the
  slot before launching; wait for other work, never terminate another session.
- `automation/test_client.sh` remains canonical for architecture, core, adapters,
  Flutter and semantic inventory. No alternate partial gate presented as complete.
- Preserve coverage and intentional retirements. No blanket baseline regeneration,
  new skips, weakened assertions, hidden failures, retries or timeout increases.
- Keep singleton/auth/custom-binding process isolation. Shared fixture changes
  require normal and reversed registration-order checks.
- No remote credentials or `.env.local` for client/unit verification. Any necessary
  SQL check uses an explicitly selected disposable local database.
- Preserve authentication exchange, tenant identity, atomic commands, image
  limits, failed-save draft retention and actual UI interaction behavior.

## Wave 0 - Establish current failures once

Use canonical main at its current SHA in an isolated task worktree if the main
worktree is owned by another active session. Read applicable instructions there.
Do not merge the old dirty checkout wholesale, change any tenant branch, or
cherry-pick fixes already present. Save main SHA and task diff provenance.

Resolve FVM dependencies beforehand only if missing. Run one complete
`FESTAPP_CLIENT_CONCURRENCY=1 ./automation/test_client.sh`, recording JSONL,
summary, source/lock/SDK fingerprint, host load and sampled owned-process RSS.
Use existing `automation/benchmark_client.py` helpers for measurement, not a
new benchmark framework or its four-run loop at this stage.

This run is both current failure inventory and initial timing observation. If
passing, it becomes the passing pre-optimization baseline: skip wave 1 entirely.
If failing, its elapsed time is not a valid passing optimization baseline.
Do not assume the old 15 failures or eight missing inventory cases persist.

Exit: exact current failures, architecture/discovery differences and costs are
known on a recorded main-derived revision. Supersede the old audit applicability
explicitly in a new receipt; keep the old numbers as historical evidence.

## Wave 1 - Repair only remaining failures

Group actual failures by owner, edit a coherent batch, then validate affected
entrypoints once. Use the saved audit only to explain overlapping symptoms.

- Toast timers: check edit permissions and service fixture setup first. Four old
  failures may have been consequences of missing rights. If a timer still leaks,
  clean up at the actual owning fixture or advance fake time after the action;
  never sleep real time, suppress timer checks or remove save assertions.
- HTML media: keep corrected >40 MP input and profile assertions. If rejection
  still fails, verify metadata validation precedes decode/allocation and cleanup
  works. No client quality/budget fields should return.
- Auth: keep code exchange + refresh-session tests and ordinary tenant-prefixed
  password coverage. Trace current issuer, consumer and response contract if
  still failing. Never restore password-only behavior just to match the old
  checkout. No source-policy evidence is a claim of live deployment support.
- Price/font/palette widgets: follow current controls and loading/retry states.
  Use semantic targets/small stable keys when needed, retain save rejection,
  draft retention, mobile scrolling, themes, retry and color round-trip coverage.
  Distinguish actual inaccessible controls from obsolete test finders.
- Architecture/inventory: fix only current discrepancies using existing explicit
  move/revision/retirement mechanisms. For every remaining mismatch record original
  behavior and replacement/retirement evidence. Preserve the existing ticket-image
  retirement instead of restoring obsolete local resize helpers. Verify atomic
  RPC-only/no-direct-DML behavior still has coverage after cohort removal.

Validation: affected `fvm flutter test --no-pub --concurrency=1 <actual roots or
cases>` in one batched invocation where fixture isolation allows it. Targeted
`fvm dart analyze <changed Dart files>` for production Dart changes. Add a
behavioral regression case only at a meaningful caller seam; existing failed
cases supply initial red evidence. No exploratory browser unless widget evidence
cannot resolve a real interaction issue.

Exit: current failures resolved with preserved intended behavior; no unexplained
inventory loss. If wave 0 failed, run one complete passing client command as the
pre-optimization baseline, combining this with full correctness verification.

## Wave 2 - Finish runner safeguards without duplicating merged fixes

1. `test_client.py:client_concurrency` still defaults to two. Align the canonical
   policy with one worker, reject overrides above one under the current workstation
   rule, retain invalid-value checks. The rollout helper already imports it.
   Update runner contracts and CONTRIBUTING examples that recommend two or more.
2. Keep `test_all.sh`'s existing failure counter, final nonzero status and root
   restoration. Confirm every selected lane contributes accurately. Add explicit
   PASS/FAIL/SKIP and monotonic lane timings plus one structured summary artifact.
   Selected missing required prerequisites must produce incomplete/nonzero status,
   distinct from established optional skips inside tests. Required automation
   files must use their interpreter or fail explicitly, not silently disappear.
3. Replace the remaining `eval`/one-second polling/immediate-child-only timeout
   code with argument-list execution and owned process-group cleanup. Reuse the
   existing Python runner lifecycle pattern where practical; no duplicate general
   orchestration framework. Retain 60 s web timeout until evidence warrants change.
4. Remove credential-bearing database URL logging. Align actual package manager,
   comments and docs with current main policy; do not impose the old checkout's
   pnpm usage blindly. Keep the explicit automation list as current scope.

Validation: reuse/extend `automation/tests/test_client_contract_test.py` and add
isolated wrapper contracts for each real gap: failure aggregation, later-lane
execution, missing prerequisites, timing summary, timeout/interrupt reaping an
owned grandchild, and secret-free output. Fake tools and fixture repos only:
no real `.env.local`, backend, deployment or nested real Flutter launches.
Run the affected Python unittest contract files once after the coherent batch.
Do not rewrite already passing merged behavior simply to add tests for it.

Exit: one-worker policy/docs agree, current aggregation is preserved and tested,
remaining lifecycle/status gaps are closed, and lane times are inspectable.

## Wave 3 - Optimize demonstrated Flutter costs

Choose the largest actual costs from the passing baseline, not the stale
18-root inventory. Rank current roots by loading and real-case duration, using
`is_semantic_case` for case counts and separating framework setup/teardown.
The first root's startup can include shared compiler cost; root count is not
proof of avoidable startup or runtime regression.

- Consolidate only compatible small environments through `registerClientSuites`.
  Inspect current imports and global setup before choosing candidates. The newer
  68-root set includes real added coverage, not automatically 50 redundant engines.
- Move a pure suite to existing VM/core lanes only when its real production
  closure is engine-free. No copied test-only business logic.
- For slow widget bodies, reduce repeated setup, redundant render cycles or
  real waits using scoped fixtures and fake time. `pump(Duration(...))` advances
  virtual time; do not count it as a real multi-second delay without evidence.
- Cut an unnecessary production import only when current closure/timing proves
  a local opportunity. Do not repeat completed AppConfig/router extractions.
- Retain architecture/core/adapter overlap followed by Flutter. No concurrent
  Flutter tasks, more workers, retries or selective tests replacing full gates.

Registration deletion ledger: move cases to the surviving entrypoint, update
origin mapping/classification, remove obsolete `_test.dart` roots and imports,
prove exactly-once discovery. Keep intentionally isolated roots classified with
reasons. No forwarding roots or duplicate registrations. For any consolidation,
run affected groups in normal and `FESTAPP_FIXTURE_ORDER=reverse` order once.

Exit: demonstrated cost falls with equivalent coverage, or a bounded finding
explains why no safe small improvement exists. Do not force a large refactor to
reach an arbitrary time target.

## Wave 4 - Comparable verification and handoff

Run one complete final client check with the same worker policy/cache preparation
as the passing baseline. Reuse unchanged passing contract checks. Run web tests
only when their covered source/assets or runner behavior changed; test wrapper
failure semantics with isolated contracts rather than a credentialed full wrapper.
Record source/SDK/host, counts/skips/failures, roots, loading/body/wall times and RSS.

A one-run difference is an observation, not a stable speedup. Only if uncertainty
changes the optimization decision, use the existing warmup + three-run benchmark
on the relevant unchanged revisions. Never repeat full suites per edit or chase
a number through benchmark loops. Aim for roughly 15-20% improvement from the
passing current-main one-worker baseline; withdraw the old provisional 50 s target
until that baseline exists. Report unmet targets and the actual remaining cost.

## Completion and remaining assumptions

- [ ] Current-main baseline and task source recorded; existing repairs preserved.
- [ ] Complete client suite/architecture/inventory pass with one worker and only
      established optional skips; every current coverage discrepancy accounted for.
- [ ] Runner gaps closed with targeted contracts and truthful summaries.
- [ ] Any root moves preserve behavior and pass both registration orders.
- [ ] Comparable before/after evidence states gain or residual uncertainty honestly.
- [ ] Docs, policy, deletion ledger and final evidence agree; no tenant/production
      operations or unrelated worktree edits.

No blocker to local implementation. Main can advance during other work: inspect
only affected intervening changes before editing or final comparison. Source
inspection proves fixes exist, not that current tests pass. This plan deliberately
requires one current-main baseline before further diagnosis or optimization.
No live deployment/auth verification, SQL speedup or worker speedup is claimed.
Rollback only task-owned changes; never reset the existing dirty checkout.
