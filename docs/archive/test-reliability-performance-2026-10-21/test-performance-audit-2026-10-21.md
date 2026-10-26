# Festapp test performance audit - 2026-10-21

Scope correction after worktree reconciliation: these measurements describe the
dirty `feat/occasion-setup-wizard-20261007` worktree at HEAD `eb2304724`, not
current canonical main. Main `1c8b5a219` already contains several of the fixes
discussed below and has 68 Flutter roots rather than 18. The original input
fingerprint remains unchanged locally. See the
[reconciled plan](test-reliability-performance-plan-2026-10-21.md)
before acting on this historical failure list. Current-main timing and pass
status were not measured by this audit.

The current bottleneck is the Flutter lane. One local client invocation took
71.83 seconds and failed; the web suite took 5.22 seconds with no failures.
Fix correctness and discovery before treating this as an optimization baseline.
No application, runner or test changes were made during this audit.

## Measured result

| Lane | Wall seconds | Semantic cases | Result |
| --- | ---: | ---: | --- |
| Core Dart | 5.76 | 158 | Passed |
| Native Dart adapters | 5.98 | 79 | Passed, one skipped |
| Flutter | 65.79 | 1,133 | 15 failed |
| Complete client command | 71.83 | 1,370 | Failed, including architecture and inventory |
| Web client | 5.22 | 404 | 382 passed, 22 skipped |

Core and adapters overlap; their times must not be added to each other.
Sampled summed owned-process RSS peaked at 2.20 GB for client and 1.49 GB for web.
These are sampled RSS totals, not unique physical memory measurements.

Ran `FESTAPP_CLIENT_CONCURRENCY=1 ./automation/test_client.sh`, followed by
`pnpm test` in `web_client`. One Flutter task and one Flutter worker respected
the workstation limit. Source fingerprint stayed unchanged during measurement.
Existing caches were retained. This is one first invocation, not a warm median
or a controlled cold benchmark. Host load at the end was 5.69 / 4.73 / 4.30.
Database/Supabase/optional fixture environment variables were removed; the broad
wrapper and its `.env.local` loading were avoided. `web_client/.env.local` was
absent. SQL, Deno, worker, browser and production operations were not measured.

The last complete receipt on October 15 recorded 29.87 seconds, 1,314 cases and
10 Flutter roots with **two workers**. Today there are 18 roots and one worker.
Different source, concurrency, cache and host conditions prevent attributing
the elapsed-time difference to a code regression or claiming a speedup target.

## Findings

1. Flutter loading events sum to 28.48 seconds; non-loading reporter intervals
   sum to 35.63 seconds, including framework setup/teardown. The first loaded
   root, `organization_identity_test.dart`, accounts for 9.72 seconds loading
   and 0.66 seconds of subsequent intervals. This can include shared initial
   compiler startup and must not all be attributed to that file's imports.
   Several later roots spend about one second loading for under 0.4 seconds
   of execution. Review compatible fixture environments before adding engines;
   do not merge singleton/custom-binding tests blindly.
2. The largest existing session is `shared_czech_test.dart`: 1.53 seconds loading
   and 10.17 seconds of subsequent intervals, with ten failing cases. Next are
   `shared_default_2_test.dart` (1.78 + 6.17 seconds),
   `shared_default_3_test.dart` (1.88 + 5.77 seconds), and
   `shared_default_1_test.dart` (1.50 + 5.24 seconds). Failure diagnostics can
   contribute overhead, so profile these again only after they pass.
3. Architecture validation reports six unclassified roots and a missing
   `ticket_background_image_cases.dart` source. Semantic inventory reports
   eight missing baseline cases, no duplicates. Reconcile original behavior
   and current registrations; do not regenerate the baseline to hide losses.
   Fifteen Flutter failures span HTML media, price scheduling, form editor,
   font loading, ticket palette and sign-in code contracts. Examples include
   an image exception mismatch, missing `maxBytes` upload field and password
   login where the test expects code exchange. Causes were not fixed or
   exhaustively diagnosed as part of this audit.
4. `test_client.py` still defaults to two workers and CONTRIBUTING recommends
   two. This conflicts with the current personal single-worker Flutter rule;
   the explicit override made this measurement compliant. Align the runner,
   rollout helper and documentation in a follow-up, preserving the serial
   workstation task limit. Raising concurrency is not an authorized shortcut.
5. `test_all.sh` runs its lanes sequentially and provides no per-lane timing
   receipt. Web failures/timeouts and image integration failures can leave
   exit status zero. Its timeout loop polls every second and kills only its
   immediate child. Reliable status and owned-descendant cleanup should precede
   optimizing this wrapper's scheduling. Its automation list is selective.
6. SQL runner code uses fixed batches of five and sequential retries after
   failures. A slow file holds the next batch, and retries can mask contention.
   This is a code-level candidate only: no SQL duration or safe scheduling
   improvement was established by this audit.

## Recommended order

1. Restore a passing client suite and semantic inventory, and align the default
   Flutter concurrency with the standing workstation rule.
2. Add trustworthy lane timings and failure propagation to the broad wrapper.
3. With passing tests, measure one-worker Flutter loading versus test bodies,
   then consolidate only compatible small roots or cut demonstrated imports.
4. Keep ordinary feedback scoped to affected lanes; reserve the broad command
   for changes that need its coverage. Measure SQL/worker lanes on disposable
   fixtures before prioritizing them. The measured web suite is not currently
   the main bottleneck.

Detailed numbers, failed test names, fingerprint and raw log location are in
[the audit receipt](test-performance-audit-2026-10-21.json). Historical baseline:
[dependency-cut receipt](../../development/flutter-test-dependency-cuts-results-2026-10-15.json).
