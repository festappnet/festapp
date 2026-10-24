# Flutter test architecture - final implementation record

Date: 2026-10-15. Waves 0-7 and the subsequent session/production dependency
cuts are implemented locally. No commit, push, backend operation or deployment.
The authoritative [plan](../plans/flutter-test-architecture-plan-2026-10-15.md)
remains the architectural contract. Final measurement details are in the
[session performance receipt](flutter-test-sessions-performance-2026-10-15.json).

## Production architecture

| Portable entrypoint | Actual production responsibility | Application boundary |
| --- | --- | --- |
| sync.dart | Protocol, polling, atomic store/orchestration and portable HTTP | Explicit Sembast storage and Supabase private remote composition |
| forms.dart | Immutable definitions/options, metadata/defaults and registration contracts | FormBundle attaches account/occasion context; editor drafts freeze at commit |
| eshop.dart | Immutable product/type catalog, existing price/wave/account/report projections | ProductGridRecord and explicit eshop commands use the existing generic grid |
| program.dart | Immutable events, captured occasion time, relations and saved-program coordination | EventGridRecord, presentation and explicit application commands |
| map.dart | Place/path data, GPX, directions, style rules and manifest schema | PlaceGridRecord, MapPlaceProgram and native manifest verifier |

The [core package](../../packages/festapp_core/README.md) has only forms -> eshop
and program -> map module edges, plus a small recursive JSON ownership utility.
Core has no application, Flutter, dart:ui, native IO or foreign internal import.
Actual production consumers use the same algorithms as the tests. Replaced old
model/protocol/store/remote/parser/helper paths and dead event writers are gone.
No forwarding implementation or test-only production switch remains. Product
relations use IDs and one catalog. Event codecs capture occasion time explicitly;
codecs preserve missing/null and wire shapes without mutating input snapshots.
SQL remains authoritative; RPC payloads, atomicity, identity fences and retry
rules were retained. Actual grid cancel/save/rejection flows are covered.

The additional production cut removed schedule feature lookup from generic
ThemeConfig. EventTypeColors now owns the same lookup; all six actual page,
timeline and timetable call sites use it. Disabled-feature lookup, first-match
selection, seed/custom colors, occasion/unit context and fallback remain covered.
ThemeConfig's app closure fell from about 693 files to 3; EditorActionBar from
693 to 7. These AST counts include conditional branches and only app files.
A negative architecture fixture prevents transitive context/router dependencies
from returning to the generic theme. Native ARM64 binaries were verified; the
legacy darwin-x64 directory name does not mean tests run under Rosetta.

A further production cut separates all three command contracts (eshop, forms,
events) from their concrete Supabase adapters. Database composition and adapter
contracts import the concrete owner explicitly; interface consumers do not.
All 68 grid field IDs now have one dependency-free owner, EshopColumnIds;
renderers and row adapters use the same identifiers. Nine ticket-feature-selected
labels moved to OrderItemStrings, while ordinary OrdersStrings no longer reads
application context. ProductGridRecord's app closure fell from 694 files to 12;
each command contract fell from 694 to 1. RPC implementations and all field
values were verified preserved. A conditional/transitive negative architecture
fixture prevents renderer or application composition imports returning to these
contracts. Large integration sessions still reach the app router.

## Test environments and ownership

The finite [classification](../../automation/client_test_classification.json)
now has **10 Flutter roots**, down from 15 before the latest consolidation,
22 before the preceding consolidation, 76 at the start of this follow-up and
137 in the first architecture baseline. Three shared default environments host
the previous five application sessions, standard widgets, visual primitives and
local auth-session storage. One actual Czech-catalog environment hosts the
previous three Czech sessions. The previous consolidation retained eleven
byte-identical moved roots and passed 1,018 affected cases in reverse order.

The latest consolidation moves eight more byte-identical roots into three
sessions: bank/media/news widgets; information/event command contracts; and
Google locale matrices plus empty-catalog timeline contracts. SDK scopes are
initialized and disposed sequentially inside their original groups. Information
and event contracts capture disjoint services. Public widget roots load the
intended translation catalog before assertions. Catalog differences alone do
not require separate engines. Auth/rights integration roots still remain separate
because they share services that cache a client. All 50 affected semantic cases
passed in reverse order (8.78 s, 2.33 GB), including the unchanged 160-combination
Google matrix. The normal full command validates the entire original inventory.
No production code or fixture behavior changed; only registration, file paths,
metadata and an ownership comment changed.

[Scoped fixtures](../../test/support/fixtures/README.md) own clients, logs,
storage, public channels and context. ResourceScope disposes in reverse order,
attempts all cleanup and covers partial setup failure. Actual bank composition,
clients/storage and translations have A-B-A contracts in both registration
orders. Localization uses public widgets/delegates. Database handles close
before directory deletion. AuthService identity composition was not changed;
the plan's conditional local-tenant auth E2E trigger was therefore not reached.

## Discovery and runner

The [semantic inventory](../../automation/client_test_inventory.json) retains
original sources, names, groups and skips. Explicit nested registration paths
resolve wrapper/framework reporter locations; same-path origin collisions still
fail. Helper-only imports exclude main and do not count as registrations; every
actual cases main must still execute exactly once.

The originally recorded 1,249-case baseline omitted a real font-picker test
because its name began with loading. Its original reporter event (id 1434,
source root line 75) proves execution. The filter now checks source metadata;
the corrected baseline is **1,250**, with a documented correction. No original
case was removed. Two previously reviewed behavioral revisions remain explicit:
copying the server-confirmed slug and the actual ordered product comparison.
The feedback deletion test still proves save/confirmation before deletion.

`automation/test_client.sh` is the complete core + native VM + Flutter command.
Architecture validation and independent Dart/VM lanes share a light first phase;
Flutter starts after all finish. Failure of a guard or any lane fails the whole
command, even when the other lanes pass. Owned descendants are cancelled and
reaped. FVM/dependency requirements fail closed; no production env is loaded.
Default concurrency is capped at **two per lane**, with a positive-integer
FESTAPP_CLIENT_CONCURRENCY override. Three concurrent large session compilations
crossed 3 GB in a targeted probe, so higher concurrency is not the default.
The reception rollout helper uses the same concurrency policy. Feature-folder
instructions were updated to real entrypoints/cases after moving registrations.

## Verification and performance

- Core architecture guards and meaningful negative fixtures passed. Twelve
  CLI contracts cover lane/guard failure, phase ordering, cancellation, nested
  origins, synthetic discovery and real loading-named cases.
- Targeted production analysis has no remaining errors. New color/helper/session
  files and core guard analysis are clean; existing page style infos/warnings
  remain. Focused actual color/context and both fixture orders passed.
- One final complete run passed: **1,301 cases, 1,300 passed, one unchanged
  optional loopback SDK skip, zero failures**. All 1,250 corrected baseline
  cases and 51 added cases are accounted for, without duplicates.
- Core: 148 cases / 32 VM suites; native adapters: 78 / 25; Flutter: 1,075 /
  10 engines. Core wall time 3.02 s, VM adapters 2.89 s, Flutter 30.31 s;
  complete command **34.90 s**. First-phase times overlap and are not summed.
- The final single-run RSS peak including its watcher was **2.44 GB**. The
  3,000,000,000-byte watcher did not trigger. It samples summed owned-process
  RSS every half second; shared pages can be counted repeatedly. This is not an
  OS-enforced allocation guarantee on every host.
- Local release web compile passed on the previous production cut in 46.61 s,
  with sampled RSS **2.70 GB**; no deployment. Production code did not change
  during this test-only consolidation, so that passing build was not repeated.

Before the last production cut, the environment-only sessions measured a
42.96 s warm median; the next scheduling profile measured 47.34 s, with runs
39.27 / 47.34 / 61.07 s. These show material variability. The preceding 76-root
configuration measured a 76.93 s median. Their immutable source digests and
load samples are retained. **Those medians do not describe the final source.**
At the user's explicit request, repeated full benchmarks stopped; final source
received the single verification above. A final warm median below 40 s is not
established. The latest single run is below 40 s; the previous single run was
35.14 s / 2.41 GB (before that, 38.19 s / 2.61 GB). The latest difference
of 0.24 s is too small to establish a material speedup amid the previously
observed variability. Fewer roots alone do not guarantee a faster total run. A whole-command result below 30 s has not been
achieved. Cold was not measured.

Remaining cost is concrete: the latest Flutter reporter records about 18.80 s
summed loading and 38.54 s summed bodies across two workers. Average occupied
slots are 1.94/2, so a long idle tail is not the main cause. Most remaining integration sessions still reach context,
ClientSyncRuntime, rights and concrete routing. The production dependency cuts
remove unnecessary loading for narrow consumers; future work must reduce those
remaining closures or expensive widget bodies without weakening their scenarios.

Application version remains **0.20.1+485**, equal to HEAD. Existing locked
dependency versions are unchanged. Concurrent unrelated work was preserved.
Earlier [architecture](flutter-test-architecture-benchmark-2026-10-15.json) and
[consolidation](flutter-test-performance-2026-10-15.json) receipts are historical;
their old name-filter case counts are superseded by the explicit correction.


## Follow-up: three dependency cuts (2026-10-15)

The [follow-up plan](../plans/flutter-test-dependency-cuts-plan-2026-10-15.md)
is implemented locally. These results supersede the latest-run figures above;
all preceding measurements remain historical evidence. Detailed immutable input
SHAs, graphs, logs, checks and deletion ledger are in the
[dependency-cut receipt](flutter-test-dependency-cuts-results-2026-10-15.json).

- Feature models no longer own widget builders or contract context lookup.
  `feature_settings_editor.dart` dispatches to ten editor modules on the original
  model instance. Ticket layout key, occasion and save callback moved intact.
  The contract default algorithm takes explicit title/start/end/description;
  first-fill guard, manual action, only-empty fields, date/day arithmetic and
  transport extraction remain unchanged. Draft scope notifications stay in UI.
- One `ClientCommandResponse` parser now lives in core/sync; all adapters use
  the explicit application replacement applier. The sequential awaited dispatch,
  late replacement validation, map views, exceptions, saved-program before/after
  context fence and `notifyProjection: false` are retained. Old parser file,
  method and Flutter test registration are deleted without forwarding shims.
- Scoped public localization printers replace the ticket global capture and
  reduce expected empty-catalog output. Capture still precedes filtering;
  strict real-catalog missing keys still fail the warning-list assertion.
  Other warnings and all errors pass through. A-B-A, nesting and failure cleanup
  use public APIs. Mixed Google catalogs remain strict; empty Czech timeline
  suites declare their fallback policy. Debug output fell 3,271 -> 22 and warning
  output 7,451 -> 667; 351 short scoped summaries record suppression counts.

The full AST model closure **did not shrink**: 699 -> 711 app files. The
remaining shortest path is `Feature -> FormFeature -> AppConfig -> AdminPage ->
OccasionAdministrationBoundary -> AppRouter`. AppConfig composition is outside
this plan. At that explicit external seam, the guarded model closure fell from
699 to 31 app files; core command parser reaches zero app files. The guard
rejects transitive/conditional editor/context imports outside that seam, with
negative fixtures. These scoped figures must not be reported as removal of the
full router dependency.

Targeted analyze, feature/map/forms/ticket scenarios, 14 core guard/parser
contracts and actual runtime replacement effects passed. Seven affected shared
sessions passed in reverse order: 1,075 cases across two invocations. The first
invocation also named a nonexistent seventh root and returned failure solely
for that path; the correctly named seventh root passed separately. New runtime
test scaffolding initially exposed missing required constructor arguments and
an asynchronous bootstrap projection; it was corrected without production
changes. Passing unrelated checks were not repeated.

One final complete command passed: **29.87 s runner / 29.92 s externally
measured**, core 2.68 s, VM adapters 2.46 s, Flutter lane 25.84 s (reporter
25.15 s). It executed **1,314 cases: 1,313 passed and the original one skipped**.
All 1,250 baseline cases and 51 previous additions remain, plus 13 new contracts;
the baseline table was not regenerated. The original two parser cases moved
exactly once. Two workers and phased Dart+VM then Flutter scheduling remain.
Sampled summed owned RSS including watcher peaked at **2,520,006,656 B**.

The previous corresponding runner was 34.90 s; this individual result is about
5.03 s faster. A whole-command single result below 30 s is now demonstrated,
with little margin; no stable median or isolated causal speedup is claimed.
Summed worker loading/body time is 15.10/33.91 s, mean occupancy 1.95/2.

One subsequent sequential production release web compile passed in **45.39 s**
with peak owned RSS **2,681,503,744 B**. Both final commands have unchanged
source SHA `27ae9d7b7f60acb3680f22bd6be49aaa29c6fa4f78638add1d60aac96ca9807c`.
The 3,000,000,000 B watcher sampled every 0.2 s and did not trigger. It owns
process-group TERM/KILL cleanup and waits for its child; RSS remains sampled,
not an OS allocation ceiling. Raw receipts are sealed by that SHA under
`/tmp/festapp-dependency-cuts/sealed/` with artifact digests. Saved dirty inputs remain separately at
`/tmp/festapp-dependency-cuts/input/`.
Application remains 0.20.1+485. No backend operation, commit, push or deployment.


## Follow-up: AppConfig router dependency removed (2026-10-15)

The user authorized the remaining cut after the three-cut handoff. The prior
AppConfig limitation above is now resolved. `NavigationPaths.admin` owns the
unchanged `'admin'` route segment; both AppConfig and AdminPage use that constant.
AppConfig no longer imports AdminPage, and the feature boundary guard no longer
stops at AppConfig. A negative fixture checks conditional/transitive routing
through AppConfig, so the former exemption cannot hide this regression.

The **full**, untrimmed Feature/MapFeature app closure fell **711 -> 33 files**
and no longer reaches the router or application context/editor owners. This is
the actual graph, not the earlier measurement stopped at AppConfig. FormFeature
still reads the same AppConfig.isAppSupported value and retains its defaults.

The architecture guard, 11 guard tests and 68 targeted Flutter cases passed
(feature models/editors, map settings, forms widgets and actual router deep-link
matching). Analyze has no errors/warnings; the existing ROUTE naming lint remains.
The targeted run took 8.83 s with 2,386,640,896 B peak owned RSS, below the 3 GB
watchdog budget. Input SHA stayed unchanged during the run. No full benchmark or
release build was repeated; previous timings remain receipts for their own SHA.
See the [follow-up receipt](flutter-app-config-router-cut-results-2026-10-15.json) for full graphs and evidence.
No backend operation, commit, push or deployment.
