# Reduce authorization evidence and Blueprint repository artifacts

Date: 2026-10-21
Status: Completed locally in isolated `task/artifact-reduction-20261021`; see [result](../generated-evidence-blueprint-reduction-RESULT-2026-10-21.md).
Verification: standard for authorization fixture extraction; low-risk for lossless Blueprint formatting and obsolete archive removal. Repository-required checks still apply.

## Outcome and scope

Remove bulky historical authorization evidence from the current checkout, preserve independent authorization regression inputs, reduce Blueprint fixture storage without losing scenarios, and remove unselected Blueprint distribution archives. Preserve current application behavior and reproducible installation.

Exclude SQL migration consolidation, application refactoring, fonts, MapLibre, unrelated documentation/evidence, production operations and Git history rewriting. No publishing or deployment is part of this plan.

## Fixed point and working-copy safety

Investigated authoritative source: `origin/main` at `a4296c57687294b34826e59c7b232eef582c9748`.
The original `/Users/miakh/source/festapp` checkout is a heavily modified October 7 feature branch. Its contents differ substantially from current main. Do not reset, clean, switch, stage or commit its unrelated work. Implement in an isolated checkout/worktree of freshly fetched canonical main; copy only this plan and its execution prompt if needed. Reconcile any newer upstream changes before using the inventory below.

Read `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` and relevant testing instructions first. Use pnpm 11.24.0 and frozen lockfile installs. Do not change a tenant branch.

## Confirmed evidence and decisions

| Area | Confirmed state at the fixed point | Decision |
|---|---|---|
| `docs/plans/evidence/canonical-authorization-20261020/` | 65 files, 67,454,209 bytes, 1,491,544 added LF-delimited lines in the investigated week | Remove historical bulk after extracting the independent inputs still used by tools/tests. Preserve a concise historical summary and recovery reference. |
| Authorization test inputs | `tools/festapp/test/canonical-authorization-postgres.test.mjs` reads `catalog-before.json` for policy metadata and `catalog-before-pristine.json` for grant comparisons | Preserve every asserted field in focused fixtures; do not delete or weaken either regression test. |
| Policy generation | `automation/generate_authorization_policy_contract.py:render()` reads historical policies, including expressions, from `catalog-before.json` | Retain this immutable policy input outside the evidence tree. Generated policy SQL must remain byte-identical. |
| Evidence tooling | Multiple `automation/authorization/` scripts hardcode the dated evidence folder; `benchmark.mjs` supplies test database connections and fixtures | Redirect retained capture/replay tooling to ignored local output. Preserve test imports and database safety checks. |
| Three large Blueprint JSONs | `canonical-text-scene.json`, `canonical-text-sql-roundtrip.json`, `canonical-text-sql-scenes.json` total 5,775,953 bytes | Use deterministic compact JSON with the same decoded values. Measured compact serialization is approximately 2.15 MB, a 63% byte reduction. |
| Blueprint coverage | Dart fixtures and JS parity tests consume these files; roundtrip has distinct `admin`, `public`, `copy`, `setup` views | Preserve all four views and all exact geometry, glyph and selection assertions. Do not merge distinct resources or reduce coverage. |
| Dart Blueprint distributions | `vendor/blueprint/README.md`, manifest and `automation/blueprint_vendor_artifacts.py` define immutable upstream snapshots | Keep active `venue_layout_core` and `venue_seat_picker` snapshots byte-identical, including licenses, manifest and archive-gate receipt. |
| JS distributions | `web_client/vendor/` contains 14 archives. `package.json` selects `festapp-venue-layout-0.3.5-ae5909c6a879.tgz`; the other 13 total 12,281,693 bytes | Remove archives after proving they are unselected by dependency, validation and publication paths. Do not change the selected version. |

These numbers describe source storage and LF counts, not newly written business logic. Reducing JSON line count alone is not the byte-savings metric.

## Target invariants

1. A fresh checkout runs applicable generators/tests without historical evidence dumps or a sibling package checkout.
2. Historical authorization expectations remain independent of current SQL/runtime results. Never construct expected grants/policies from the system under test.
3. No authorization SQL, grants, RLS, auth configuration or production data changes in this cleanup.
4. The three Blueprint fixtures decode to exactly their pre-change values; generator outputs use the same compact representation consistently.
5. Active Blueprint source snapshots and selected JS archive retain their checksums. Do not prune files inside hashed upstream snapshots or hand-patch a dependency.
6. Removed bulk is recoverable from a full immutable Git revision. New captures go to ignored local artifacts, not the dated tracked tree.

## Wave 1: Remove authorization evidence without losing contracts

**Changes**

- Search the exact dated evidence path and all 65 basenames across tracked code, CI, documentation, tests and generators. Classify each as active input, historical replay input or output. This bounded inventory is the removal gate; the two known tests are not assumed to be the only readers.
- Add `database/fixtures/authorization/pre-cutover-policies.json`, containing all historical policy rows and the fields required by the generator and metadata test. Add `pre-cutover-acl.json`, containing exactly the historical grant/role collections plus function signatures and grants consumed by the ACL comparison. Determine the complete field projection from actual reads before extraction.
- Extract from the immutable fixed-point originals, preserving nulls, ordering where meaningful, and complete row membership. Record original blob SHA-256, source commit/path and projection description in a small fixture README. Compact these data files.
- Point `generate_authorization_policy_contract.py` and the PostgreSQL tests at these fixtures. If another active consumer needs an additional historical field, add its minimal projection; do not retain whole SQL catalogs by default.
- Keep `automation/authorization/benchmark.mjs` exports and its loopback, dedicated database marker, paused-email and cron checks unchanged. Inspect other test imports before moving/removing any script.
- Redirect retained evidence writers and readers to `FESTAPP_AUTHORIZATION_EVIDENCE_DIR`, defaulting to an ignored `.codex-artifacts/authorization/` run folder. Make paired capture/replay inputs explicit. Missing historical capture inputs must fail clearly with recovery instructions, never silently recapture from production or manufacture a baseline from current SQL.
- Recover historical replay inputs with `git show <full-source-sha>:<original-path>` into ignored local output when deliberately reproducing old evidence. Normal tests and generators must not need this recovery or full Git history.
- Preserve material historical conclusions, limitations and unapplied production gates in a concise `docs/archive/canonical-authorization-evidence-2026-10-20.md`. Include source SHA, recovery command and original file hashes for the removed set. Update inbound links, including the canonical authorization plan/result/bank records, to the summary, focused fixture or recovery instructions as appropriate. Do not mark unproven production activation as complete.
- Remove the original 65-file evidence tree once all active inputs have moved. Do not replace it with a tracked compressed copy, another dump directory or LFS dependency.

**Validation and exit**

- Compare extracted projections against the pinned originals before removal; validate every required row and value.
- `python3 automation/generate_authorization_policy_contract.py --check` passes and generated SQL is byte-identical to the pre-change output.
- Run `node --test automation/tests/authorization_read_phase.test.mjs` and the affected PostgreSQL authorization tests through their documented local environment. The latter use `FESTAPP_AUTHORIZATION_DATABASE_URL`; `benchmark.mjs` requires loopback port 61022, marker `festapp-authz-20261020`, paused/fenced emails and disabled cron. Do not reuse the ordinary 55432 database or alter these safeguards to force a pass.
- Exercise at least the RLS metadata and full ACL tests with a real disposable database, and run the existing relevant authorization suite when required by repository gates. An unset variable produces skipped tests, which is not a passing database verification. If the dedicated environment is unavailable, report that exact limitation and keep implementation readiness conditional.
- Check retained capture scripts' path handling and syntax without a production connection. Search for the removed evidence path: remaining occurrences may only explain immutable historical recovery, not active runtime/CI/generator file access.

## Wave 2: Reduce Blueprint fixtures losslessly

**Changes**

- Compact the three named JSONs with deterministic UTF-8 serialization and one trailing newline. Keep existing schemas, decoded numeric values, list order and every scenario.
- Update the producers: `automation/blueprint_capture_text_corpus.ts`, `automation/blueprint_capture_canonical_text_sql.mjs`, and `automation/blueprint_export_sql_scenes.dart`. Remove pretty indentation at the serialization boundary so regeneration cannot restore the bulk.
- Preserve provenance and explain regeneration in a small fixture README. Before editing, store decoded reference values/hashes outside the repository to prove semantic equivalence after serialization.
- Keep JS expected scenes as recorded Dart reference output. Do not compute JS expectations from the JS kernel under test. Do not replace the four readers with one scenario even where some resource dictionaries match.
- Avoid introducing new fixture loaders, compressed binary formats or runtime expansion abstractions in this pass. The measured lossless byte reduction already meets the bounded goal. More aggressive structural deduplication would require a separately justified contract change.

**Validation and exit**

- Deep-compare every decoded fixture before/after; no value changes. Report bytes as well as LF counts. Expected combined size is roughly 2.15 MB instead of 5.78 MB; use actual serializer measurements rather than enforcing the estimate as a semantic requirement.
- Run `pnpm --dir web_client exec node --test tests/components/blueprint_layout_adapter.test.js`, preserving all four readbacks, exact Dart/JS scene comparisons and glyph/selection checks.
- Locate grouped Flutter entrypoints that register `blueprint_layout_assets_cases.dart`, `blueprint_layout_ui_cases.dart` and `blueprint_text_preparation_cases.dart`; run the smallest covering roots, once, with `fvm flutter test --concurrency=1`. Check workstation Flutter occupancy first and wait for the existing task rather than stopping another session's work. Use repository guidance for any required group-order checks.
- Run the Dart scene exporter if its installed dependencies and regeneration inputs are available, and verify deterministic output without semantic drift. Do not run production SQL capture merely to test formatting. Syntax-check changed capture scripts and exercise their serialization using existing data where feasible.

## Wave 3: Remove obsolete Blueprint archives; preserve active snapshots

**Changes**

- Resolve the selected archive from `web_client/package.json`, `pnpm-lock.yaml`, `vendor/blueprint/manifest.json`, archive receipts and packaging/test scripts. Search full tracked paths and basenames, including dynamic version/prefix selection, rather than assuming package.json is the only selector.
- Delete the unselected `.tgz` archives from `web_client/vendor/`. Expected removal: 13 archives, approximately 12.28 MB. If a genuine active test consumes an older version, migrate it to a narrowly scoped fixture without losing its regression, or explicitly retain only that archive with its named consumer and reason.
- Update `automation/blueprint_vendor_artifacts.py` and `vendor/blueprint/README.md` so future updates no longer promise retention of the historical 0.2.3 archive. Retain or add a small deterministic assertion that dependency installation cannot silently select a missing/stale archive; reuse an existing distribution contract if present.
- Keep both active Dart snapshots and the selected npm archive byte-identical. Do not prune upstream `test/`, `example/`, font assets or generated files inside immutable distributions. Their contents are owned by the upstream package and its archive gate, not this cleanup.
- Keep active version and lock resolution unchanged. A frozen lockfile install must succeed. If removing genuinely unreachable archives requires broad lockfile changes, investigate the selector before accepting that churn.

**Validation and exit**

- Compare active snapshot files and selected archive checksums against `vendor/blueprint/manifest.json` and the pre-change source.
- `pnpm install --frozen-lockfile` in `web_client`, then the affected existing JS distribution/parity tests and `pnpm --dir web_client run build`. Reuse the passing parity check from Wave 2 if its covered inputs did not subsequently change.
- Confirm package, lockfile, manifest, installer and CI contain no active dependency on deleted archives. Historical references must identify Git recovery instead of claiming a file is present.
- Do not rerun an upstream package publication/archive-build workflow just for deleting unused host archives. No new package release or sibling-repository changes are needed.

## Final measurement and prevention

Batch coherent edits, then run the final targeted checks once; repeat passing checks only if their covered inputs change. No tests, browser work or builds are needed merely to prepare this plan.

Measure against the implementation base: tracked bytes and LF lines per affected category, file counts, and actual deletion/addition delta. Verify the deletion ledger and inspect the final diff for unrelated changes. Add a narrow repository contract in the existing automation test layer: the historical evidence tree must not return, and only explicitly selected Blueprint archives or documented test inputs may be tracked. Keep large capture output under the existing ignored `.codex-artifacts/` boundary; do not globally ignore JSON, fixtures or vendor dependencies. No application tests just to assert prose or indentation.

Expected dominant savings are roughly 67 MB of raw authorization evidence less small retained fixtures, approximately 3.6 MB from JSON whitespace, and up to 12.3 MB from old archives. These are working-tree bytes, not packfile size. Git history and existing clones retain old blobs; reducing clone history size is outside scope.

## Deletion ledger and completion

| Item | Required end state |
|---|---|
| 65-file authorization evidence tree | Removed from current tree; minimal independent inputs, historical conclusions and immutable recovery references retained elsewhere. |
| Direct test/generator reads of historical dumps | Replaced by focused committed fixtures; no fallback to current SQL or missing historic paths. |
| Tracked dated evidence outputs | Retained tooling writes to ignored explicit output locations; normal checks need no restored dumps. |
| Pretty-printed three Blueprint fixtures | Replaced losslessly; producers agree on compact output; all scenarios and parity assertions remain. |
| Unselected JS archives | Removed or individually justified by an actual current consumer. |
| Active Dart snapshots and selected JS package | Preserved byte-for-byte with valid manifests and reproducible dependency installation. |

Complete when all ledger rows hold, affected validation passes without hidden skips, and a compact measurement report records savings and any specifically retained artifact. Missing disposable authorization infrastructure is a verification limitation, not permission to weaken tests or use production. Updating the plan is required if newer main invalidates a factual premise.

Rollback is a normal source revert with fixtures/tooling/archive selection restored together. No database rollback, production migration, deployment, upload, history rewrite, commit or push is authorized by this planning request.

## Implementation base reconciliation

Freshly fetched main is `f4aa0b6edfa688b03937197d74b0506d2ae81db7`. Its only
change since the investigated fixed point adds seat-blocking confirmation UI.
The 65 capture files, three fixtures and selected distributions match the inventory;
no factual premise or wave scope changed. Original checkout remains untouched.

### Wave 2 exporter premise correction

Executing the existing Dart exporter on the recorded SQL roundtrip revealed that
`canonical-text-sql-scenes.json` has older ancillary `document` fields (for
example admin starts with seat `042e3870-3d71-4c73-bf77-6d6716c7c702`, while
the current roundtrip starts with text `20000000-0000-4000-8000-000000000001`).
The exact scene and selection expectations still match all four current SQL
readbacks, as the existing JS regression proves. Do not replace these historical
fields during a lossless cleanup. Add an optional exporter output path, regenerate
to ignored/temporary output twice, compare deterministic output, and compare all
four scenes/selectionUnits to the recorded references. Retain the original decoded
fixture in full and record this pre-existing provenance limitation. No assertions
or scenarios may be removed to accommodate it.
