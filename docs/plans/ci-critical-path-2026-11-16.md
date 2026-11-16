# CI critical path: plan and execution

Scope: `festappnet/festapp`, canonical main CI only. No product release,
production database access, paid runner upgrade or unrelated repository changes.
Starting source: `748e575bd19b5d81f750d7f5bf65f2b7bfd425fc`.

## Evidence and objective

The full hosted baseline `3c837dc327672b7ed703f54800fb437d2171fe5f`
took 380 seconds from first workflow creation to the last required job completion.
Verified reuse on the following documentation change took 37 seconds.
The goal is to avoid unrelated executions and shorten genuinely affected/full
executions. A tenfold improvement is a target for narrow changes, not an
established claim about the complete cold suite.

Observed bottlenecks (overlapping phases must not be summed):

| Area | Measured time | Source |
| --- | ---: | --- |
| CMS unit | 283 s | Wix baseline artifact |
| WordPress startup | 165 s | `cms.wordpress.start` |
| CMS browser installation | 48 s | `cms.browsers.install` |
| CMS cleanup | 30 s | `cms.cleanup.wordpress` |
| Ticket Flutter tests | 184 s | `ticket-client` |
| MCP contracts | 131 s | `seat-mcp-contracts` |
| MCP authorization truth table | 57 s | all 2,048 combinations |

## Implementation order

1. **Correct unit dependencies.** Audit actual commands and their imports before
   removing broad MCP inputs from unrelated SQL units. Give Dart-core and Deno
   ticket units their actual inputs instead of inheriting the whole application.
   Add positive and negative selection cases: consumer changes rerun consumers,
   shared SQL/runtime/fixture changes retain all required consumers, unknown
   inputs continue to select full scope. Do not infer independence from a name.
2. **Reuse Flutter engines across compatible tests.** Consolidate CI entrypoints
   with the existing grouped registration helper. Keep separate compile-time
   defines and incompatible environments. Preserve the exact semantic inventory
   (657 ticket cases, 228 navigation registrations, including skip states), map every
   moved group explicitly, and verify both normal and reverse registration order.
   Retain consolidation only when it passes isolation and improves elapsed time.
3. **Reduce CMS preparation and waiting.** Start browser preparation immediately
   alongside independent services. Cache only immutable downloaded runtime inputs,
   never CMS databases, accounts, volumes, consent state or credentials. Key
   caches by platform and their pinned tool/configuration inputs; validate loaded
   identities and fail closed. Preserve the complete nine-case real CMS matrix,
   including WordPress versions, three engines, Joomla versions, iframe renewal,
   withdrawal, revocation and COOP fallback. Record restore/export overhead.
4. **Batch the authorization truth table.** Keep all 2,048 combinations, real
   canonical predicates under `authenticated`, complete capability assertions and
   historical-envelope comparison. Reduce client/server round trips without
   replacing the database owner with a simulation or testing as an administrator.
   Compare the original and batched executors on the same disposable database;
   retain the change only if it measurably improves the test.
5. **Publish and measure.** Run canonical affected local lanes once on the coherent
   change, plus inventory and semantic isolation checks. Fetch and integrate
   current main before publication. Require all eight exact-source GitHub jobs
   to pass. Compare total time, preparation, executed cases, reuse and runner
   work with the baseline; distinguish cold provisioning from affected executions.

## Acceptance and boundaries

- No required test/scenario removed, weakened, silently skipped or moved outside
  its canonical entrypoint. Preserve release-gate names, provenance, age limits
  and resource ceilings (one local Flutter task, concurrency one, two DB slots).
- Target a material reduction (at least 30%) in affected Flutter execution and
  targeted preparation; measure actual outcomes rather than promising them.
- Unknown dependency syntax, missing inputs or invalid cache evidence must run
  the conservative path. Every optimization has negative coverage for this.
- A failed experiment may be rejected with its measured reason. Do not retain
  speculative complexity or claim an unverified tenfold full-suite improvement.
- Finish publication checks and retain evidence before retiring the task worktree.

## Execution record

- Dependency audit removed blanket MCP inputs from seven SQL units and the
  public checkout browser unit. The explicit MCP disposable-database guard still
  invalidates its actual `seat-services` consumer. Ticket Deno/core and Flutter
  dependency installation now have separate platform inputs.
- A transitive Dart graph experiment was rejected before publication: the real
  router imports a large application graph, while source-inspection tests read
  files dynamically. Retain conservative application inputs instead of adding a
  mostly-fallback graph/parser and pretending it narrows coverage safely.
- Broad engine consolidation was rejected after actual forward/reverse runs
  exposed singleton SDK, cached fonts and fallback/localization boundaries.
  Those original scopes stay separate. Six compatible ticket roots share one
  engine (22 -> 17 roots); four compatible navigation roots share one (13 -> 10,
  plus the separate define=false engine). Only the new outer groups use
  `FESTAPP_CI_GROUP_ORDER=reverse`; existing nested fixture registration profiles
  retain their established order. Exact semantic baselines remain unchanged.
- Original/batched authorization truth-table comparison on the same local
  disposable database, pinned Node 22.23.4: 16.884 s versus 13.391 s (-20.7%).
  Both executed all 2,048 combinations; all JavaScript rights/capability/envelope
  assertions are unchanged. The first complete MCP run passed all 24 + 256 cases
  with zero skips. Hosted timing remains to be measured.
- CMS uses four preparation workers and the supported wp-env `cleanup` command,
  which removes owned containers/volumes/networks without discarding runtime
  images. The GitHub cache transfers only upstream content-addressed base images;
  its key binds runtime configuration, lockfile, helper, workflow and platform.
  Archive and loaded image IDs are checked; a warm hit avoids another export.
- The first multi-lane experiment is retained as failed evidence; the Flutter
  isolation failures were not hidden or reclassified as successful tests.
  Final semantic checks, reverse-order isolation and hosted measurements follow.

The 31-unit forward mirror at the intermediate isolation boundary passed with
`complete=true`, `inputsUnchanged=true` in 403.08 s on this workstation; CMS
159.4 s, MCP contracts 64.4 s, authorization 17.6 s. Reverse-order failures
rejected that larger grouping; these are not final performance claims.
The renewal case now advances the real browser clock through its actual 20s
interval and still requires the real cross-frame renewal message. Negative
revocation waits and all nine CMS scenarios remain unchanged. WordPress bases
are explicitly prefetched during its preparation worker so BuildKit layers
can enter the upstream-image cache; mutable tags are still resolved each run.

Final safe grouping validation before integrating the next main advance:
canonical mirror `image-contract navigation-interactions
 ticket-preview-and-delivery wix-checkout-compatibility` PASS, 14/14 units,
`complete=true`, `inputsUnchanged=true`, 208.39 s. Receipt:
`20261116T174507-a9de83c4362d`. Navigation 34.35 s; ticket 56.60 s; CMS 97.09 s,
including every one of the nine real CMS cases and timer-driven iframe renewal.
These native samples have warm downloads and different selected lanes; their
aggregate times are not a hosted speedup comparison. The optional GitHub image
transfer cache was disabled in this native run, as designed.

Both canonical Flutter commands also passed with
`FESTAPP_CI_GROUP_ORDER=reverse`: the exact same 228 navigation and 657 ticket
registrations, including skips. Existing standalone SDK/font/locale processes
and compile-time defines are preserved. A broad reverse of pre-existing nested
fixtures is not substituted for the isolation check of the newly combined roots.

Main `9a8e156ab9c825c9514b27230e2517603a875a5b` was inventoried and integrated
before publication. Its information SQL migration and added tests are preserved.
The measurement SQL unit duplicated five files already auto-discovered by the
complete MCP group. Their duplicate invocation and redundant install are removed;
a contract now enforces the grouped owners. The new information assembler stays
with its actual `mcp-auth-contract` owner. Latest-main validation follows.

Final-main native mirror after duplicate removal: all 31 units PASS,
`complete=true`, `inputsUnchanged=true`, 321.58 s, receipt
`20261116T175301-b43213742746`. Source HEAD `4370fc42d` is the rebased
implementation commit whose parent is canonical main `9a8e156ab`; dirty=true
records the reviewed follow-up changes, not a different backend target.
All 283 MCP tests passed (24 authorization + 259 contracts), zero skips/failures;
all 657/228 Flutter registrations and nine CMS cases passed. Measurement dropped
to 4.4 s after removing the five duplicate MCP file executions. Consumed-input
review also retained external email examples, Wallet brand assets, and Deno's
real database/layout/font fixtures in the relevant fingerprints.

A bounded scheduler experiment follows the measured bottleneck: authorization,
contracts and service units peaked at 404/670/541 MiB of sampled process RSS.
Compare the same seat lane with two versus three admitted database units, keeping
3500 MiB admission RAM, one local Flutter task and all cluster-wide/exclusive
claims intact. This is a proposed extension to the initial two-slot constraint,
not an unmeasured relaxation: reject it on case failures, excessive memory or no
material wall-time benefit. No production/runtime capacity changes are in scope.

Controlled two-slot baseline: canonical seat lane PASS, 17/17 units, same 283
MCP cases with zero skips, 126.72 s total, receipt
`20261116T180111-07028b8ee899`. Database-container peak sampled 464.4 MiB;
per-unit peaks below their admission reservations. The candidate raises only
DB admission to three within the existing three workers and 3500 MiB budget;
all five prior full-cluster claims rise from two to three, preserving exclusion.

The first three-slot exploratory run passed all cases but its global receipt
reported changed inputs because the new test-contract guard was edited during
startup. Its 107.58 s is not accepted as a valid comparison. The source is now
frozen for one clean repeat; require at least 15% improvement over 126.72 s,
all cases/pass states unchanged, no increased RAM budget and preserved exclusive
claims. Reject the three-slot change if this bounded repeat misses the threshold.

A further consumed-input audit found an existing but unused distinction:
`requires` is runtime preparation, while `after` also orders independent checks.
Partial plans previously replayed upgrade/runtime-contract tests through `after`
even when their direct execution evidence remained valid. The full DAG order
is unchanged; SQL behavior units require their actual dependency install (MCP
also its one API preparation), because canonical Runtime.acquire() calls prepare()
before cloning a marked workspace. Ticket Deno/core units are independently
self-preparing; Flutter client requires the root Flutter installation. All
unchanged checks still require verified, unexpired exact-input execution proof.
Missing proof executes the check. Provision Flutter, SQL and browser tools only
when selected commands/resources need them; unknown/missing flags retain full
preparation. Verify dependency omission is rejected and exercise a real standalone
checkout browser workspace without the independent upgrade-test units.

The frozen repeat passed on clean source `dcfb7ba74`: image-contract PASS
(106 CI tests plus its existing storage/retention checks); seat-checkout PASS,
all 17 units, same 283 MCP cases with zero skips, 96.36 s versus 126.72 s
(-24.0%) in the paired native sample. Receipt `20261116T182532-f256c91fdccb`
reports complete/input-unchanged true and dirty=false. Container peak 476.1 MiB
versus 464.4 MiB. Three DB admissions are retained at the existing 3500 MiB and
three-worker budget; all five whole-cluster claims consume all three slots.
This native paired sample is not a promise about GitHub CPU/cache variability.

A real public checkout/offline-recovery check then acquired a completely new,
uniquely marked canonical Runtime/database, without the independent upgrade-test
units. Both browser scenarios passed; 14.99 s including bootstrap and cleanup.
The task-owned container, volume, lease/cache were verified and removed.
Partial execution also explicitly retains `requires` as scheduler edges after
already-verified ordering checks are removed, so consumers cannot race installs.
A scheduler regression test exercises exactly that race.
