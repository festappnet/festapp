# Repository artifact reduction - local completion

Base: freshly fetched canonical main `f4aa0b6edfa688b03937197d74b0506d2ae81db7`.
Branch: `task/artifact-reduction-20261021`, isolated checkout
`/Users/miakh/source/festapp-artifact-reduction-20261021`.
Original working copy was preserved. No commit, push, publication, production
connection, SQL migration or deployment was performed.

All three waves and deletion-ledger rows are complete. The
[executed plan](plans/generated-evidence-blueprint-reduction-plan-2026-10-21.md)
records the one corrected exporter premise.

## Source storage measurement

Bytes are current-tree storage, not Git packfile or clone-history savings.
LF counts are literal byte `0a` separators; binary archives are not source lines.

| Category | Before files / bytes / LF | After files / bytes / LF | Bytes saved |
|---|---|---|---:|
| Historical authorization captures | 65 / 67,454,209 / 1,491,544 | 0 / 0 / 0 | 67,454,209 |
| Independent authorization fixture JSON | 0 / 0 / 0 | 2 / 3,547,558 / 2 | -3,547,558 |
| Three Blueprint JSON fixtures | 3 / 5,775,953 / 254,177 | 3 / 2,139,030 / 3 | 3,636,923 |
| Host npm archives | 14 / 13,419,562 / 51,405 | 1 / 1,137,869 / 4,486 | 12,281,693 |

The JSON fixtures shrink 62.96% without any decoded value change. Raw capture
removal plus compact fixtures and unused archive removal save 79,825,267 bytes
before small documentation/tooling additions. The exact complete unstaged delta,
including this report and copied/archived plan/prompt, is recorded below.

Complete delta: **14 added, 29 modified, 78 deleted files**;
changed files 85,740,901 -> 5,968,342 bytes, net **79,772,559 bytes saved**.
Text LF delta: 1,748,508 -> 3,415 (**1,745,093 fewer LF separators**).

## Completed deletion ledger

- Removed all 65 authorization dumps. All eight fields of all 408 original
  policy rows and all required historical ACL collections/1,013 function grants
  were extracted from immutable `a4296c57687294b34826e59c7b232eef582c9748`.
  Full projections were compared against `git show` originals. Tests and the
  policy generator now consume only these focused committed fixtures.
- Retained capture/replay scripts use the explicit environment output folder
  and ignored default, with named missing-input failures and no recapture fallback.
  Benchmark exports and every connection/email/cron safeguard are unchanged.
  [Reader inventory and historical recovery](canonical-authorization-evidence-2026-10-20.md)
  preserve all 65 hashes, material conclusions, limits and unapplied gates.
  Full basename search found the active generator/test reads, historical replay
  scripts and dated document links; generic `validation.json` hits in unrelated
  BankSync/mutation/Blueprint records refer to their own evidence and were retained.
- Compacted all three Blueprint fixtures and updated all producers. Complete
  Python and JS decoded references were preserved outside the checkout. All
  four admin/public/copy/setup views, geometry, glyph and selection assertions remain.
  The corpus producer uses the selected repository Dart core rather than its
  former workstation-specific sibling checkout.
- Removed all 13 unselected npm archives listed below. Dependency version,
  lock resolution, selected archive, archive-gate receipt, manifest and all
  manifest-listed Dart snapshot files remain byte-identical. Upstream tests,
  examples, fonts and licenses remain intact. Historical records point to Git
  recovery rather than claiming old archives remain installed.
- Added an automation-lane contract preventing the old evidence tree and
  unselected archives from returning, checking lock/package/manifest consistency,
  immutable snapshot checksums and fail-closed replay path handling.

## Actual verification

- Policy generator `--check` passed; authored policy SQL, migrations, dependency
  locks, manifest and archive receipt remain unchanged.
- `FESTAPP_AUTHORIZATION_DATABASE_URL=<dedicated-local-supabase_admin-url>
  node --test tools/festapp/test/canonical-authorization-postgres.test.mjs`:
  **24 passed, 0 failed, 0 skipped**, including RLS metadata, full ACL,
  2048-role truth table and live database writer/revocation contracts.
- `FESTAPP_AUTHORIZATION_POLICY_DATABASE_URL=<same-dedicated-url>
  node --test automation/tests/authorization_read_phase.test.mjs`:
  **4 passed, 0 failed, 0 skipped**. The completed run used the same dedicated
  database with local `postgres` role, which is sufficient for these policy checks.
- New repository artifact contracts: **3 passed, 0 skipped**; registered in
  `automation/test_all_commands.json`. Python/JS capture syntax and TypeScript
  syntax after type erasure passed without provider/database capture.
- `pnpm --dir web_client install --frozen-lockfile`: passed with pnpm 11.24.0;
  locks unchanged. JS adapter/distributed-kernel parity: **19 passed, 0 skipped**.
  `pnpm --dir web_client run build`: passed.
- `fvm flutter test --no-pub --concurrency=1 test/sessions/shared_czech_test.dart
  --name 'blueprint_layout_assets|blueprint_layout_ui|blueprint_text_preparation'`:
  **50 passed**. These are the actual grouped entrypoints, not merely imported
  cases. No shared registration/fixture lifecycle changed, so reverse group order
  was not required. The user explicitly authorized a second workstation Flutter
  task; this task completed and no owned Flutter task/server remains running.
- Dart exporter executed twice to separate temporary outputs: byte-identical;
  all four scene and selectionUnits values exactly match historical expectations.
  All three final fixtures deep-compare equal to their complete original values.

Initial local verification used the non-superuser `postgres` connection for the
full catalog test, hiding historical `supabase_admin` grants in information_schema;
the prescribed setup uses `supabase_admin` and the complete 24-test rerun passed.
An initial overlap of read-phase DDL and the SQL suite deadlocked; serial read-phase
rerun passed. Initial unset-variable skips are not counted as database verification.
No grants, baselines, assertions or database safeguards were changed to pass tests.
Local command logs are `/tmp/festapp-artifact-{postgres-final,read-phase,flutter,
parity-final,build,contract-final,export-1,export-2,pnpm}.log`; they are local evidence,
not tracked bulk captures or production receipts.

## Retained exceptions and verification boundary

The scenes fixture has historical ancillary `document` fields predating the current
SQL roundtrip. Existing JS tests compare its exact Dart `scene` and selection units,
which still match all four readbacks. Lossless cleanup preserves the historical
fields, and an optional exporter output path enables deterministic checks without
overwriting them. See [fixture provenance](../../test/fixtures/blueprint/README.md).
The historical receipt recipes also retain their explicitly documented original
local log requirements; full logs were never in Git, while their recorded receipts
and hash-linked artifacts remain recoverable.

Production was not contacted, historical benchmarks/providers were not rerun,
and no package publication/archive-build workflow was invoked. No product runtime
behavior or authorization contract was changed. Git history still retains old blobs.

## Removed archive recovery

Use `git show a4296c57687294b34826e59c7b232eef582c9748:<path>` and verify SHA-256.
The sole selected host archive is `festapp-venue-layout-0.3.5-ae5909c6a879.tgz`.

| Removed path under `web_client/vendor/` | Bytes | SHA-256 |
|---|---:|---|
| `festapp-venue-layout-0.2.0.tgz` | 418454 | `838918f49b1bf396523838973d60ab7917c582965700cebef4796e941589d064` |
| `festapp-venue-layout-0.2.2.tgz` | 419961 | `4df965ffa537b04625cde68fa2d55133b9a911c9f8a7012e1b7af93c0c176b59` |
| `festapp-venue-layout-0.2.3.tgz` | 419952 | `4c5c7daf3fdf4d7195e4f5b750193babff571e9a44a6ff2161e8d18583c3552f` |
| `festapp-venue-layout-0.3.0-2179ed4858ec.tgz` | 1021628 | `2179ed4858ec326cee95da175cac383a0e0fae20c4afd92036130fd49780dbc6` |
| `festapp-venue-layout-0.3.0-closure-062c9d302de0.tgz` | 1136085 | `062c9d302de0787d122160f38de7d6e37441382e005e8ffcedd916140312b4cc` |
| `festapp-venue-layout-0.3.0-integrity-c11e8a62eee3.tgz` | 1021338 | `c11e8a62eee39cab0e920179a119acee3f56c74cb5520b070ddf73197f474e57` |
| `festapp-venue-layout-0.3.0-label-center-e0ee6f60.tgz` | 1022274 | `ddc29e9051ce4cdd4e0f20102f1b7feff42abfb79be280706ffe2eb54acdcb0b` |
| `festapp-venue-layout-0.3.0.tgz` | 1136085 | `062c9d302de0787d122160f38de7d6e37441382e005e8ffcedd916140312b4cc` |
| `festapp-venue-layout-0.3.1-2e103008a485.tgz` | 1137215 | `2e103008a4857d7780034987c585fb9ca323c6fa57a8c503ad9ab9759623e608` |
| `festapp-venue-layout-0.3.2-818fef252831.tgz` | 1137215 | `818fef2528313475d1d37dd6c45f2195b16fcb25a8409e2c50c2f4d15f5de0f0` |
| `festapp-venue-layout-0.3.3-2812e279130d.tgz` | 1137216 | `2812e279130da28098b45324c3fe05e3c38dce5d2dfc27d45dacef021d48467c` |
| `festapp-venue-layout-0.3.4-37624ab595c3.tgz` | 1137131 | `37624ab595c3eea1cb2c67bd1eddf34b6783968ca9c33c7d8a36ab2ab3ddc08c` |
| `festapp-venue-layout-0.3.5-5f0cc8723c69.tgz` | 1137139 | `5f0cc8723c69ee82c84950a1d6f6280927435558c78fa2819e746d1dc69843d0` |

Subsequent authorized [artifact follow-up](repository-artifact-followup-2026-10-21.md)
retired the one-time evidence builders. Measurements above describe this initial
phase, before that separate reduction.
