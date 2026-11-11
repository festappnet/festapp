# Local test performance, 2026-11-06

## Plan

1. Measure the existing complete client command and `pnpm --dir web_client test` without resolving dependencies, rebuilding the backend or changing test selection. Retain JSON events and failures.
2. Run independent web test files with four isolated Node processes. Keep database files sequential in a separate batch, execute both batches even after failure, and preserve the generated-artifact checks. Verify discovery and failure propagation.
3. Consolidate a small set of compatible eshop Flutter suites into explicit feature entrypoints, separated by locale/environment. Keep Supabase singletons, font installation and incompatible environments isolated. Preserve all cases and document source/group moves in the semantic inventory.
4. Compare the same selected Flutter cases before/after with one worker and warm caches, then run the complete client suite and the changed groups in reverse order. Compare complete web counts, failures and wall time. Record measured improvements and limitations here.

## Initial observations

- Web: 49.50 s wall time; 1034 tests, 1001 passed, 30 skipped, 3 failed. The three pre-existing failures require `DATABASE_URL` (Barion concurrency and the two payment upgrade proofs).
- An exploratory four-process web run: 15.03 s; identical counts and failures. Database fixtures must retain sequential scheduling in the implementation.
- Flutter: 134 discovered roots. New compatible suites have accumulated since the earlier session consolidation. Worker concurrency remains 1 under workstation policy.
- No test is designated useless merely because it is slow. Changes retain behavioral coverage and expose existing failures.

## Evidence

Raw baseline logs and client events: `/tmp/festapp-tests-20261106-before-*`.
Exploratory web logs: `/tmp/festapp-tests-20261106-parallel-web.*`.

## Results

- Web scheduling implemented in `web_client/scripts/run_tests.mjs`: four isolated processes for independent files, one for database fixtures, both batches always executed. Existing artifact freshness checks and nonzero failure propagation remain.
- Three executable runner regressions verify recursive discovery, sequential database scheduling, failure propagation/continuation and empty-discovery rejection. All pass in each complete web measurement.
- Web wall time: **49.50 s before**, **16.45 s median after** (15.996 / 16.450 / 16.757 s), approximately **67% less time**. Original 1034 cases retained, plus 3 runner tests. All original reporter case/suite names match after normalizing absolute/relative paths. After: 1004 passed, 30 skipped, the same 3 pre-existing database failures. This is not an all-green web result.
- Ten eshop Flutter files now register through three explicit entrypoints, separated into default, English and Czech environments. All ten moved case files are byte-identical to their originals. Root Supabase clients and font installation remain isolated. The existing CI contract references the renamed cases explicitly.
- Selected Flutter wall time, three runs: **15.36 s median before** (15.362 / 18.076 / 14.607 s), **7.36 s median after** (7.811 / 7.361 / 7.148 s), approximately **52% less time**. All **55 semantic cases** match exactly in all runs. Reverse registration also passes (7.055 s).
- The six local/GitHub CI contract tests pass using the existing `~/Library/Caches/festapp-ci/python/bin/python` environment. System Python lacks PyYAML; no repository dependency change was needed.
- Final complete client run: **272.29 s after**, **311.89 s before**. All **2811 semantic cases** match exactly (266 core, 95 adapters, 2450 Flutter), with the same four established skips and zero failures. Architecture and semantic inventory checks pass. Flutter roots executing on the VM decreased from 133 to 126; the browser-only root remains outside this VM command. Full-run timing is a single observation, with the cache/contention limits below.

Machine-readable evidence: [`local-test-performance-2026-11-06.json`](local-test-performance-2026-11-06.json). Raw events remain at the recorded `/tmp` paths; the repository JSON retains timings and conclusions.

## Reproduce

The normal commands stay unchanged:

```sh
pnpm --dir web_client test
./automation/test_client.sh
```

For the affected feature only (partial client coverage):

```sh
fvm flutter test --no-pub --concurrency=1 test/components/eshop/eshop_unit_test.dart test/components/eshop/eshop_english_widget_test.dart test/components/eshop/eshop_czech_widget_test.dart
FESTAPP_FIXTURE_ORDER=reverse fvm flutter test --no-pub --concurrency=1 test/components/eshop/eshop_unit_test.dart test/components/eshop/eshop_english_widget_test.dart test/components/eshop/eshop_czech_widget_test.dart
```

## Measurement limits and remaining cost

Existing SDK/build caches were retained, with no dependency installation during timing. Selected Flutter measurements followed the full baseline and used one worker. Full client runs have only one sample before/after; the baseline overlapped web measurements. Do not treat their difference as a controlled median or claim a cold-cache improvement. The web baseline has one sample; the implementation has three.

The entire client suite still takes minutes. This change removes seven engine starts; it does not turn all 2450 Flutter cases into the 7.36 s feature subset. Further consolidation requires compatible global state and reverse-order checks, or extracting genuinely portable production rules into the core package. No individual test was proven unnecessary in this audit, so none was deleted or newly skipped.

Backend SQL, Deno, browser, image-worker integration and the automation manifest were inspected through the broad wrapper but were not benchmarked or changed. These lanes require separate fixtures/tools; no whole-`test_all.sh` performance or production/database result is claimed.


## Follow-up target: complete client command at most 100 seconds

Acceptance: warm median of the complete `automation/test_client.sh` command at most 100 s, unchanged semantic cases/skips, one Flutter worker, architecture/inventory checks and both registration orders passing. The earlier 272 s result does not meet this target.

Plan:
1. Reduce the remaining independent engines through explicit compatible environment sessions. Keep root Supabase clients, font failure injection and incompatible font families isolated. Match font families within font sessions and preserve every original lifecycle hook.
2. Profile the resulting complete run. Investigate remaining engine/JIT/fixture costs; consider disabling optional widget-inspector creation tracking only if the same cases pass and measurements show a benefit. Retain assertions and real widgets/rendering.
3. Run normal and reverse-order contracts, compare normalized semantic identities with the original full receipt, and measure the complete command repeatedly after final inputs are fixed.

Progress: 84 additional roots grouped into nine environment sessions, reducing the full classification to 52 roots (51 VM roots and one browser-only root). All 2811 semantic cases still match the original full receipt, including skips. 83 moved source files are byte-identical; the remaining file only adds teardown for a leaked `fluttertoast` method-channel mock.

The working-directory trial took 197.97 s; its source included concurrent cash/payment work and is not a green acceptance receipt. An isolated checkout at the original baseline SHA, with these test-only changes and experimental inspector tracking disabled, took 212.25 s including a fresh checkout/compiler cache. It exposed two failures from the leaked toast mock, subsequently fixed. This is not evidence that disabling inspector tracking improves performance, so that flag is not being adopted.

The 100 s target is **not met**. The one-worker trial spent 129.75 s in test bodies and 52.21 s in suite loading. The user has been asked whether the explicit workstation `--concurrency=1` rule may be relaxed to two test workers within one Flutter command; no such run has been performed without approval. Final normal/reverse validation of the broader groups and a repeated performance receipt remain pending.

The isolated checkout is `/tmp/festapp-tests-100s-worktree`. It excludes the concurrent cash implementation; do not copy its application source back. Further Flutter runs must also coordinate with cash task `01a1b1cc-a9ce-7c51-8fde-1cf062fb353e`, which requested the workstation slot for targeted checks. The profiling run has released the slot; the message tool could not deliver the acknowledgement because its localhost transport was unavailable.
