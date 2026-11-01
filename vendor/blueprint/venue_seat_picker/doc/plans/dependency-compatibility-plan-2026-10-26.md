# Broaden Venue Layout compatibility without changing its behavior

Date: 2026-10-26
Status: Implemented and locally verified; new registry releases not published
Verification: standard (published dependency and SDK contracts)
Baseline: `7cf27b1ca51940ffa86d4595f929439c619b4727`, Flutter wrapper 0.4.3 / core 0.2.2.

## Outcome and scope

Remove unused direct runtime declarations, allow compatible dependency updates,
and prove the oldest supported Flutter/UI combination alongside the current
release toolchain. Preserve every public widget, SVG backdrop, color dialog,
localization, document, font fingerprint, selection and reservation behavior.
This task implements and verifies source changes; registry publication and
Festapp production rollout are separate actions. Do not republish existing versions.

## Evidence and decisions

| Confirmed evidence | Consequence |
|---|---|
| `lib/` and `example/lib/` have no `cupertino_ui` or `flutter_localizations` package imports. `VenueLayoutLocalizations.localizationsDelegates` uses `GlobalMaterialLocalizations.delegates` exported by `material_ui`. | Remove these two direct declarations; retain their legitimate transitive use. |
| pub.dev manifests: material_ui 1.0.1-1.3.0 and cupertino_ui 1.0.0-1.1.0 support Dart 3.12 / Flutter 3.44. material_ui 1.4+ requires Dart 3.13 / Flutter 3.47. | Investigate minimum `material_ui ^1.0.1`, Dart `^3.12.0`, Flutter `>=3.44.0`; publish that floor only after real SDK validation. |
| Actual material_ui 1.0.1 archive contains `MaterialUiCompatibilityBridge` in `lib/src/migration_utility.dart`. | Existing color-picker boundary may remain without a replacement bridge or dual UI implementation. |
| `lib/src/editor_ui/editor_color.dart` uses flutter_colorpicker; `lib/src/widgets/venue_seat_viewer.dart:_backdrop` uses flutter_svg for public inline/network SVG backdrops. | Retain both used dependencies. Replacing a working color picker or deleting backdrop support is outside cleanup scope. |
| `packages/venue_layout_core/pubspec.yaml` pins crypto 3.0.7, vector_graphics_compiler 1.3.0 and xml 6.6.1 exactly. Core imports all three. | Relax crypto/XML ranges; retain the compiler version required by the confirmed receipt contract. |
| Registry compiler 1.3.0-1.3.2 allows XML >=6.3.0 <=7.0.1; compiler 1.3.1+ needs Dart 3.11. XML 7.0.1 requires Dart 3.11. | Target ranges: crypto `^3.0.7`, XML `>=6.6.1 <8.0.0`. Retain compiler `1.3.0` because `graphic_import.dart:importSvgGraphic` returns `converter: vector_graphics_compiler@1.3.0`; no caller/version provenance should become false. Keep core's declared Dart 3.10 floor; the resolver selects older supported releases there. |
| Current CI validates only Flutter 3.47.7 and uses local core overrides. | Add minimum/runtime-lowest resolution coverage and retain the existing archive consumer check; only the local core source may be overridden; no external dependency or SDK override may count as compatibility evidence. |

Registry evidence: https://pub.dev/api/packages/material_ui,
https://pub.dev/api/packages/cupertino_ui,
https://pub.dev/api/packages/vector_graphics_compiler,
https://pub.dev/api/packages/xml. Dart recommends compatible version ranges and
actual downgraded-dependency tests: https://dart.dev/tools/pub/dependencies.

## Invariants and retained boundaries

- One canonical geometry/import implementation in venue_layout_core; no alternate
  parser, renderer, SDK-conditioned source or dependency overrides in shipped manifests.
- One standalone Material UI contract at all supported SDK versions. No return
  to a separate SDK Material implementation. Keep only the existing external
  flutter_colorpicker compatibility bridge.
- Never lower a declared SDK floor on the strength of manifest arithmetic alone.
- Do not widen a major dependency boundary unless actual core import/text/scene
  regression tests pass at both supported ends.
- Preserve flutter_svg, flutter_colorpicker, all public exports and current UI.
- Runtime production resolution excludes dev dependencies from dependency counts.

## Implementation waves

### 1. Remove redundant direct dependencies

Update root and example pubspecs to drop direct cupertino_ui (both) and
flutter_localizations (root). Verify no owned source directly imports them.
No public API, visual or transitive localization change is intended.
Exit: only directly consumed packages remain in runtime manifests.

### 2. Broaden core constraints

Use the candidate ranges above. Resolve and run core tests with lowest supported
packages and with latest compatible packages, including XML 7.0.1 on SDKs that support it. Keep compiler 1.3.0 to preserve
the public import receipt identity. Existing graphic_import, text_contract, legacy import
and canonical scene tests own behavioral proof. Record exact resolved versions.
The lowest test runner also has to compile: use test `^1.31.0` as a dev-only
lower bound because test 1.25.15 downgrades to Dart-incompatible watcher/file/
pub_semver versions. Resolve test tooling normally first, then downgrade the
named runtime dependencies only: even test 1.31.0 permits historical
frontend_server_client versions whose compiler snapshot no longer exists.
These development-only bounds do not restrict consumer dependencies.
If a real compiler/XML incompatibility appears, constrain only the failing
boundary and document it; do not hide it with overrides.
Exit: supported low/high graphs pass; core Dart 3.10 remains honest and gets CI coverage.

### 3. Prove the wrapper SDK and Material floor

Install isolated Flutter 3.44.0 through FVM without changing the development
`.fvmrc`. Run minimum dependency resolution, analysis and the wrapper tests on
that SDK. Test latest compatible resolution there too; current Flutter 3.47.7
keeps using current Material UI. Use the existing regression tests for color,
localization, viewer/picker/controller and imported seating behavior. Run only
one Flutter task at a time and tests with `--concurrency=1`.
If normal public APIs differ, adapt through an API available at both ends only
when behavior stays the same. If resolving requires a fork, shim or duplicated
UI path, keep the current floor and record the precise unsupported API instead.
Exit: lowest declared SDK/dependencies actually compile and behave, with current
SDK regressions still passing.

### 4. Keep compatibility enforced and document the contract

Add CI minimum Flutter resolution coverage (lowest and latest compatible), plus
core minimum-Dart runtime coverage. Retain the current SDK dependency graphs
alongside the qualified npm archive so later release verification identifies
the resolved graph, not only the source revision. Retain the current full build/archive/browser release
lane. Use the documented commands directly in isolated CI jobs; no additional test
runner is needed. Local verification restores the normal resolver state and
never changes the development SDK pin. Update CONTRIBUTING, README and a compatibility
note with supported SDKs, UI/theme/localization integration, retained dependencies
and explicit reasons for any remaining constraint. Add unreleased changelog entries.
Update this plan with executed commands, resolved graphs and actual results.
Exit: future source/dependency upgrades cannot silently invalidate the claimed floor.

## Deletion ledger

| Item | Action | Proof |
|---|---|---|
| Root direct cupertino_ui / flutter_localizations | Remove if no direct use | Scoped import search and analysis |
| Example direct cupertino_ui | Remove if no direct use | Scoped import search and example analysis |
| Core exact crypto/XML pins | Replace only by verified compatible ranges | Low/high resolver receipts and core regressions |
| Core compiler 1.3.0 pin | Retain at the SVG receipt/provenance boundary | `SvgGraphicImport.receipt.converter` names that exact implementation |
| Old test-only 1.25.15 floor | Raise to 1.31.0 without changing runtime deps | Lowest-core test runner compiles on supported Dart |
| Root material_ui 1.8 / SDK 3.13 lower bound | Relax only after minimum real SDK checks | FVM 3.44.0 resolution, analyzer and tests |
| Existing SVG and color-picker dependencies/bridge | Retain at named public boundaries | Existing backdrop and color integration tests |

## Verification and completion

Standard targeted validation applies because dependency ranges are public
contracts. Batch changes before checks. Run full core tests at the low/high
endpoints, wrapper analysis/tests on the minimum and current SDK, and public
consumer/distribution checks after source inputs are final. Reuse unchanged
passing evidence. CI must repeat minimum coverage for future releases.

Completion means redundant declarations are removed, all broadened ranges are
backed by actual resolution and tests, the documented floor is enforced in CI,
and no public behavior was removed to achieve a smaller dependency list.
Unpublished source changes receive unreleased notes; a later package release
must use new versions (expected core 0.2.3 before wrapper 0.4.4).

## Assumptions and residual risks

- The existing wrapper uses no indispensable post-3.44 framework API. Resolve
  this assumption through actual 3.44 analysis/tests; change the target floor if
  evidence disproves it.
- A future compiler relaxation must migrate the exact-version receipt identity
  truthfully and prove compatible numerical output. The current change retains
  that compiler boundary and verifies the broadened XML/crypto ranges.
- Removing direct declarations does not remove packages still required by
  Material; do not describe that as reducing the installed runtime graph.
- Registry releases remain immutable. No production tenant or published package
  is changed by this implementation task.

## Execution record

- Planning: completed focused source, dependency-graph and registry-manifest reconnaissance.
- Flutter 3.44.0 / Dart 3.12.0: installation, lowest dependency resolution and
  full analysis passed; 353 wrapper tests passed, one existing skipped test.
  Resolved material_ui 1.0.1, cupertino_ui 1.0.0, crypto 3.0.7,
  vector_graphics_compiler 1.3.0 and XML 6.6.1.
- Flutter 3.38.0 unexpectedly bundles Dart 3.10.0-290.4.beta; its resolver
  correctly rejects the stable >=3.10.0 floor. Do not weaken the public floor
  to accept this prerelease. Select a stable 3.10 SDK for core verification.

- Deep-check finding: the SVG converter receipt hardcodes implementation 1.3.0.
  Retain that one justified pin; broadening it without a provenance migration
  would silently make public receipt metadata inaccurate. No importer API change
  is part of this conservative dependency cleanup.

- Dart 3.10.0 from Flutter 3.38.1: core analysis passed and all 306 tests
  passed with minimum runtime versions; a second 306-test run passed with
  latest compatible runtime versions. Test tooling is resolved normally first.
- Flutter 3.44's test-asset cache missed the shader added between Material UI
  releases. Fresh `build/unit_test_assets` restores the package shader. CI graph
  jobs are isolated; local reproduction instructions clear only that cache.
  Do not impose a Material UI version exclusion for this cache behavior.

## Final verification matrix

All wrapper rows passed full analysis and 353 tests, with one pre-existing skip.
All core rows passed 306 tests; minimum and current SDK analysis also passed.
The compiler remains 1.3.0 in every graph.

| Consumer / SDK | Resolution | Material / Cupertino | Crypto / XML |
|---|---|---|---|
| Wrapper, Flutter 3.44.0 / Dart 3.12.0 | Lowest | 1.0.1 / 1.0.0 | 3.0.7 / 6.6.1 |
| Wrapper, Flutter 3.44.0 / Dart 3.12.0 | Latest compatible | 1.2.0 / 1.0.2 | 3.0.8 / 7.0.1 |
| Wrapper, Flutter 3.47.7 / Dart 3.13.5 | Latest compatible | 1.8.0 / 1.1.4 | 3.0.8 / 7.0.1 |
| Core, Dart 3.10.0 | Lowest runtime | Not used | 3.0.7 / 6.6.1 |
| Core, Dart 3.10.0 | Latest compatible runtime | Not used | 3.0.8 / 6.6.1 |
| Core, Dart 3.13.5 | Latest compatible runtime | Not used | 3.0.8 / 7.0.1 |

Additional checks passed: frozen pnpm install, JavaScript kernel build,
actual pub-selected wrapper/core archives, clean archive consumer, offline
archived Flutter example and 15 JavaScript browser scenes, plus both demo-kit
smoke checks. CI YAML was parsed locally; the new jobs are configured but have
not been executed remotely for these uncommitted changes.

Evidence logs and exact resolved dependency graphs are in
`/tmp/venue-compatibility-20261026/`. The root development SDK pin remains
Flutter 3.47.7, and its normal dependency resolution is restored. There are five
wrapper runtime declarations instead of seven; legitimate transitive
Cupertino/localization packages remain installed.

### Completion and release boundary

All four implementation waves are complete. No runtime source, public widget,
SVG/color interaction, document or reservation contract was removed or forked.
The compiler pin is intentionally retained at its named provenance boundary.
New package releases remain pending: publish a new core version (expected 0.2.3)
before a new wrapper version (expected 0.4.4). A refreshed npm kernel archive
also needs a fresh npm version if its bytes change; never overwrite 0.3.7.
The local archive smoke qualifies the implemented runtime/dependency changes;
final immutable release receipts must be created from the eventual committed,
versioned release source. Published 0.4.3 still has its original SDK constraints.
No Festapp tenant, backend or production deployment was changed by this task.

## Authorized release follow-up

The user approved publication and requested persistent rules against unnecessary
latest-version minimums. `AGENTS.md` and `CONTRIBUTING.md` now require concrete
reasons for raising SDK/dependency floors and enforce minimum/current checks.
The release includes the canonical main fix `3b56d2448fe75a60248e99bde8653afd5e052bdd`
for requested-side fixed-chair removal. Prepare core 0.2.3, wrapper 0.4.4 requiring
that fixed core, and npm 0.3.8. Final exact-source CI revalidates the combined
source; prior matrix receipts remain evidence for the compatibility design.
Keep qualified dependency graphs inside the archive artifact directory so the
release downloader retains its existing flat artifact layout.

### Fresh-CI release corrections

The first final-source CI exposed two local-environment assumptions. Minimum
wrapper jobs must resolve the core development package context before analyzing
the entire checkout; otherwise package:test imports fall back to the wrapper
graph. XML 7 deprecates XmlName's original constructor, while XML 6 does not have
XmlName.parts. Preserve the common constructor with exactly three documented
local diagnostic suppressions. Do not raise the XML floor or globally disable
fatal analyzer diagnostics. Old release archives are invalidated; qualify the
corrected committed source through a fresh full CI run and new archive receipts.
