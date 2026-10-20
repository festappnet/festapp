# Stage A verification evidence

## Curvature, chair attachment and editable paths - 2026-10-18

Curvature has a direct number field and slider, preserving one undo transaction
per slider gesture. Chair drop highlights the target table and attaches/reassigns
the same seat ID. Capacity rejection cancels provisional insertion; existing
manual chair positions remain preferred unless explicitly reparented. New
palette chairs use the same dimensions and default style as generated chairs.
Open paths have zoom-aware screen-sized hit targets, direct endpoint/vertex
handles and normalized editing bounds. Resizing explicit paths scales their
points. Finished paths are selected and insertion returns to selection; stroke
color and width are directly editable.

Full Flutter suite passed 93 tests with one opt-in raster skip before the final
insertion-mode/style refinement. The final interaction batch verifies attachment,
full-table rollback, one-shot line insertion and endpoint manipulation; a style
fixture initially used the wrong scene lookup fields and was corrected to the
seat body ID/kind. The final style case has its own receipt. All 89 core tests pass,
including seven path hit tests and six path manipulation tests. Seven JS tests
pass. Analyzer and rebuilt demo pass. Receipts:
`build/qa/curvature-chair-path-{flutter,core,analyze,build,js}.log`,
`curvature-chair-path-selection-recheck.log`, and
`curvature-chair-style-final.log`.

An isolated desktop browser attached a seventh chair to Stůl 1, confirming
seven matching attachment records, and changed curvature from 3 to 7.25 while
retaining 40 row seats. Evidence: `chair-table-hover.png`,
`curvature-visible.png`, `curvature-changed.png`.


## Curved rows and default wheel zoom - 2026-10-18

Corrected row tangents divide curve derivative by seat spacing. Full generator
settings are persisted; legacy row settings can be inferred and the demo safely
repairs matching old generated angles on recovery. Custom/manual/locked chair
placements and identities are preserved. Inspector row/column inputs and +/-
controls reconcile the same assembly without losing curvature or existing IDs;
invalid fractional counts reject and one row is the minimum. Advanced fields
expose curvature, both spacings, blocks and aisle width.

Default wheel input now zooms around the pointer, including when an object is
selected. Shift-wheel pans; native trackpad pan/pinch remains supported.
Seven targeted UI/navigation/canvas tests pass; all 76 core tests pass,
including six row tangent/metadata/inference/legacy repair regressions.
Targeted analyzer and rebuilt demo pass; runtime source manifest matches.
Seven JS tests pass. The isolated desktop browser added a sixth curved row:
seat count rose from 40 to 48, all original seat IDs remained, and outer
chair angles were about 20.56 degrees rather than the old near-right-angle
rotation. Ordinary wheel input zoomed the selected assembly. Row assemblies
use count/spacing controls instead of the meaningless 40x40 resize handles;
the rotation handle is positioned above the complete assembly bounds.
Browser evidence: `arc-rows-inspector.png`, `arc-rows-added-zoom.png`.
Receipts: `build/qa/arc-rows-wheel-tests.log`,
`arc-rows-core.log`, `arc-rows-wheel-analyze.log`, `arc-rows-wheel-build.log`.


## Desktop navigation, copy gestures and package i18n - 2026-10-18

Wheel/trackpad pan now works independently of object selection. Ctrl/Meta-wheel
zooms around the pointer; pinch and editing drag retain separate camera/object
semantics. Ctrl/Meta-drag creates a fresh assembly inside the same undo gesture;
cancellation removes the provisional copy. Insert/paste/duplicate allocate
noncolliding table numbers in spatial order, preserving custom names.

The package owns Flutter-native localization delegates, English fallback and
Czech messages. The demo selects Czech using those delegates. Hosts can override
terminology through VenueLayoutStrings; stock document labels/text/section
names are localized explicitly without changing IDs, level keys or custom text.
Columns and minor structural decoration omit default labels.

The initial full Flutter run passed 85 tests, skipped one opt-in raster test and
found two issues: the locale test lacked Material/Cupertino delegates, and a
painter raster fixture sampled the old pre-camera coordinate. The combined
Flutter delegate list and corrected viewport sample resolve those issues;
their affected 24-test batch passes. The final controller/copy/localization batch
and analyzer receipts are `navigation-copy-i18n-final.log` and
`navigation-copy-i18n-analyze.log`; final demo build is recorded in
`navigation-copy-i18n-build.log`. Dedicated navigation tests cover selected-object
wheel pan, pointer-anchored zoom and trackpad pan/pinch without object edits.

An isolated desktop browser confirmed Czech table names, stage/dance-floor
text and unnamed columns. A wheel event on the selected table panned the
scene upward by 120 pixels while selection stayed visible and serialized
node geometry remained byte-identical. Evidence:
`build/qa/navigation-i18n-selected.png` and `navigation-i18n-scrolled.png`.


## Canvas double-click editing - 2026-10-18

A double-click on empty space inside the canvas enters canvas selection,
clears node selection, displays eight border handles, and opens the existing
canvas inspector with editable width, height and color. Object double-clicks
retain inline editing. Outside/read-only clicks cannot enter this mode;
selecting an object or Escape exits. Handle drags resize any side/corner from
the gesture baseline, preserve object geometry and stop at content bounds and
the minimum size. Canvas drag edges round outward to whole schematic units.
A drag is one undo transaction and cancellation restores the original canvas.

Three canvas widget tests cover an actual double tap and handle drag,
dimensions, undo, content containment, cancellation, selection exit and
read-only/outside guards. The adjacent inline/editor batch passed 25 existing
tests. The isolated desktop browser confirmed selection handles, the open
inspector, and a bottom-edge drag increasing height from 1200 while retaining
all 91 nodes. Final rounding is covered by the widget test. Evidence:
`build/qa/canvas-double-click-{recheck,analyze,build}.log`,
`canvas-double-click-selected.png`, and `canvas-double-click-resized.png`.


## Manual chair edge regression - 2026-10-18

A chair moved independently became `manual`, and bounded table movement treated
that placement as immovable. A regression test reproduced the table stopping
62 world units before the wall. Manual now means a preferred position, not a
lock: attached unlocked manual chairs can relocate if they leave the canvas;
inside manual placements remain exact. Identity, attachments, count, fixed
canvas and atomic undo are retained. Locked chairs remain fixed.

The new regression and affected controller/widget batch pass 19 tests. The full
core run passed 68 tests and identified one fixture enforcing the superseded
manual-as-lock policy; its updated edge batch, with an additional inside-manual
regression, passes 12 tests. Targeted analyzer and rebuilt demo pass. JS tests
are recorded in `build/qa/manual-chair-edge-js.log`. Failure and fix receipts:
`manual-chair-edge-red.log`, `manual-chair-edge-green.log`,
`manual-chair-edge-core-recheck.log`, and `manual-chair-edge-build.log`.


## Regular spacing, manual chairs and clipboard - 2026-10-18

Tables now attract to aligned row/column continuations and equal edge gaps,
with an 8-unit gentle grid fallback. Table chairs can be selected and dragged
individually, retaining attachment and identity as manual placements. Table
body drags still move the full assembly. Copy/paste clones complete assemblies
with new identities, bounded insertion, progressive offsets and one undo step.
Native editable text keeps its clipboard shortcuts. Web paste consumes the
browser paste event rather than requesting clipboard-read permission.

Checks: full Flutter suite 76 passed, one opt-in raster skip; final affected
controller/widget batch 6 passed after the native paste change. Full core suite
69 passed; JS suite 7 passed. Targeted final analyzer is clean and demo build
passes with a matching runtime source manifest. An isolated desktop browser
confirmed the native-paste event handler accepted a seven-node table fragment,
raising the draft from 12 to 13 tables (91 to 98 nodes). Clipboard event data
was injected at the browser boundary; OS clipboard key delivery was not proven
by that check. Keyboard dispatch and clipboard serialization are covered by
Flutter widget/platform clipboard tests. Headless Chromium modifier-key
redispatch interfered with direct CLI shortcut checks; no user browser/profile
was touched.

Evidence: `build/qa/spacing-chair-clipboard-{flutter,core,js,build}.log`,
`build/qa/spacing-native-paste-{tests,analyze}.log`, and
`build/qa/spacing-chair-clipboard-result.json`.

## Bounded manipulation and uncluttered seats - 2026-10-18

This user revision tightens the earlier placement policy: new objects and
manipulations cannot leave the canvas. The canonical bounded move clamps the
physical body first, repacks automatic chairs, then projects remaining fixed
geometry inward. When the requested wall position cannot hold every chair at
normal spacing, movement stops at the closest feasible position. Rotated/nested
groups, multiselection, fixed chairs, insertion, resize and rotation use the same
boundary policy. The controller also rejects new/worsened overflow from direct
edits; previously invalid drafts can still be repaired progressively.

Seat numbers remain in document/accessibility data but never emit canvas glyphs
in either renderer. Other object labels and state indicators remain visible.
Snapping uses actual viewport scale, a 7-pixel attraction range, canvas/object
edges and centers, and visible alignment guides. Table magnets use their body
bounds rather than asymmetric chair extents after wall reflow.

Checks: the full Flutter suite passes 70 tests with one opt-in raster test
skipped. Core passed 59 tests and exposed two obsolete fixtures which required
seat glyphs; both were changed to non-seat label fixtures and their 21-test batch
passed. The final bounded-operation and asymmetric-table snapping batch passes
12/12. Seven JS tests pass. Targeted analyzers and the final demo build pass;
the source manifest matches the current runtime files.

The real desktop browser dragged a six-seat table beyond the canvas. Its body
stopped at world x=95, y=330 (left edge exactly zero); all six chairs stayed
inside, and the canvas remained 1600x1200. The JS consumer confirmed all bounds,
six retained seat labels in data, and one SVG group per chair without label
glyph groups. A subsequent drag from the asymmetric wall layout showed a guide
aligned to table body edges. Evidence: `build/qa/bounded-desktop-result.json`,
`bounded-wall-clamp.png`, `bounded-web-no-numbers.png`, and
`bounded-final-snap-guides.png`. The isolated QA browser is closed.

## Placement and layers update - 2026-10-18

The latest user direction supersedes automatic canvas growth and collision
rejection during editing. The canvas now changes only through explicit canvas
operations. Overlapping drafts remain editable and autosavable; explicit Save
checks overlap and world bounds, draws red warning bounds, and retains its error
message after background autosave.

Assemblies are contiguous hierarchical layers, including their text. Dragging
temporarily lifts the whole manipulated subtree without modifying stored ranks.
The inspector supports front/back and one-step movement with undo. Hit testing,
full/partial core scenes, Flutter painting and JS presentation patches use the
same canonical stacking. Locked siblings permit only mechanical rank changes
which preserve their content and order relative to all unselected objects.

Automatic attached chairs move to feasible perimeter slots at canvas edges.
IDs, count and metadata are retained. Manual/locked placements stay fixed;
impossible fits retain every chair and surface save warnings. This does not
silently reduce capacity or compress chair spacing.

Validation: core 55 tests pass. Root Flutter full batch passed 67 tests and
exposed one mechanical-rank comparison regression; fixing sparse map comparison
then passed all 11 controller tests. Targeted analyzer is clean. The six existing
JS tests passed; the new patch-order regression passed after correcting its
test-only flat-transport fixture. UI foreground/group-order tests pass 2/2.
Receipts are `build/qa/placement-*.log`.

The real isolated desktop browser dragged Table 1 directly onto Table 2:
both reached world (610,330), all 72 seats remained, and the canvas stayed
1600x1200. The active label/body painted above the other assembly. Save marked
the seven overlap pairs red. Moving Table 3 to the left edge redistributed all
six original chair IDs inside the canvas, with no canvas growth. The table body
was 2.5 units beyond the edge and was correctly reported as an additional
boundary warning. The Save warning remained after the 500 ms autosave interval.
Screenshots are `placement-drag-foreground.png`, `placement-edge-reflow.png`,
and `placement-final-save-warning.png` under `build/qa/`. The QA browser closed;
the user's original demo server remains available. The prior inline AX snapshot
limitation below remains outside this placement verification.

## Desktop interaction update - 2026-10-18

The current demo adds eight Ticket-style compact resize handles, opposite-edge
anchoring, restrained rotation controls, and selection bounds which do not
repaint glyph outlines. Selected table/furniture/standing labels and text edit
inside the canvas; new text enters editing immediately after click or drag.
Enter/blur commits, Escape cancels, IME composition is preserved, and insertion
plus its initial text is one history transaction. Inline input lays out in
viewport pixels and follows camera zoom/position and object rotation.

Eight new targeted regressions pass after the final viewport/boundary changes
(`/tmp/venue-inline-viewport.log`), with a clean targeted analyzer. The earlier
full root suite exposed two click-placement regressions; restricting the new
double-tap recognizer to selection mode fixed both, and the 24-test gesture and
inline batch passed (`build/qa/inline-web-gesture-recheck.log`). The six public
JS tests also passed. The final demo build passed; its source manifest matches
the current runtime files.

The ordinary headless desktop browser journey actually renamed `Table 1` to
`Rodinný stůl`, inserted `Vítejte na plese` through the palette and native text
input, and loaded both edits in the JavaScript customer preview. Selecting one
seat produced a 250 Kč seating total. Returning to the editor and opening the
preview again preserved the document JSON exactly, including IDs, and cleared
only the ephemeral customer selection. Screenshots are under `build/qa/` with
the `inline-final-` and `inline-web-final-` prefixes. The QA browser was closed;
the existing user demo server remains running.

**Remaining limitation:** automated accessibility-tree snapshots repeatedly
stalled with inline editing focused. Explicit semantic boundaries and the
viewport input overlay pass widget accessibility checks, but the browser AX
issue remains unresolved. Ordinary desktop typing/commit and the preview
round-trip pass; these checks do not certify a physical screen reader.

The web preview uses the package's real JavaScript customer picker, with a web
client style demo shell. It does not integrate the production Festapp web client,
create reservations, or submit orders. A per-tab IndexedDB handoff commits the
whole portable bundle before navigation, avoiding the localStorage size limit
and cross-tab replacement of another preview's document.

The original Stage A checks below cover the standalone package only. The later
shared editor UI work also changes local Festapp picker adapters; its evidence is
recorded separately. No database, production tenant, registry or deployment is
changed by these checks.
Passing a package simulation never proves database atomicity or payment behavior.

## Reproduction

Prerequisites for rebuilding: pinned FVM SDK, cached Flutter/Dart dependencies,
Node/npm with `web/node_modules` installed and Playwright Chromium installed,
and Python 3. Dependency/toolchain installation can require internet. Runtime
checks block all non-loopback network requests. Every harness closes its own
browser and loopback server, including failed runs.

After the coordinator freezes source and builds `tool/demo.sh build`:

```sh
fvm dart run packages/venue_layout_core/tool/qa_export.dart build/qa/fixtures
fvm flutter test test/layout/qa_raster_test.dart --dart-define=QA_FIXTURES=build/qa/fixtures
QA_PHASE=parity node tool/qa_browser.mjs build/qa/fixtures build/qa/browser/final-kernel-parity
QA_PHASE=performance node tool/qa_browser.mjs build/qa/fixtures build/qa/browser/final-performance
QA_PHASE=ui node tool/qa_browser.mjs build/qa/fixtures build/qa/browser/ui
node tool/qa_picker_flow.mjs build/qa/browser/final-picker
node tool/qa_raster.mjs build/qa/fixtures build/qa/raster
(cd web && npm test)
tool/archive_check.sh
```

`qa_browser.mjs` compares decoded VM/browser scene JSON exactly, including Czech
outlined text, rotated hierarchy, inverse hit tests and motion at 0/80/160/240 ms
of a 240 ms interpolation. It compares full 500/5000/20000-seat scenes exactly.
CPU mount/patch/wheel timings, browser RAF intervals, cold first usable preview,
JS heap samples and UTF-8 document size are recorded independently. RAF timings
include vsync; they are not CPU drawing duration. Desktop touch emulation is not
a representative physical phone benchmark. JS heap values are browser estimates,
not process RSS or Flutter heap.

`qa_raster_test.dart` captures the actual Flutter `LayoutScenePainter` at a fixed
camera. `qa_raster.mjs` captures the public JS SVG viewer with identical camera,
resources and presentation at 360/900/1440 logical px, DPR 1/2, zoom 0.5/1/2 and
the four motion samples. It reports exact RGB mismatches outside the union of
one-pixel color-edge masks, plus hard-ink bounds and centroids. Edge confinement
alone is not a declaration that every raster difference is acceptable: the
bounds/centroids and representative captures must be reviewed for shifts.

`archive_check.sh` derives each Dart tar file selection from the **actual**
`pub publish --dry-run --verbose` archive list, validates exclusion of workspace
caches/overrides, records per-file SHA256 and creates real tar files. It also runs
`npm pack --dry-run` and `npm pack`. Its temporary Flutter consumer resolves only
the extracted core/wrapper plus cached third-party SDK dependencies; it loads
archive-only font resources, creates all nine templates, verifies fresh IDs and
roundtrips, and opens/selects every template through the standalone editor gallery.
It builds the extracted example and boots it in a browser. The extracted npm
archive is independently imported and renders all nine scenes with its own local
font assets. No checkout source is used as a consumer dependency.

## Run results

Hardware: Apple M5, 10 CPU cores, 16 GiB RAM, macOS arm64; Chromium
156.0.8078.4; Flutter 3.47.2, Dart 3.13.2. The final source receipts are in
`build/qa/validation.json` (package/core/example tests and analyzers). The optional
raster test is run independently. Public JS browser tests passed 6/6 (`build/qa/npm-test-final.log` and
`build/qa/npm-result.json`), including
independent late rejection, unavailable seats, paired-unit rollback, standing
quantity, retained scene/camera patches and malformed import preservation.

The final parity receipt is `build/qa/browser/final-kernel-parity/result.json`:
two fixtures (registered crop and rotated Czech glyphs), all hit/motion samples,
and full 500/5000/20000-seat scenes compare exactly. Its kernel SHA and source
change flag identify the actual input. Interim failures remain in their original
folders; they are diagnostic history, not the final receipt.

The final current-kernel performance receipt is
`build/qa/browser/final-performance/result.json`, SHA256
`87acea7c19ffec1e2443a22707613942aa2a4ec87f6476703c5ab18b7f942b9f`,
161,079 bytes / 51,051 bytes with Node's default gzip, below 500 KiB. Every
cold resource timing confirms this exact kernel. Source remained unchanged.
The perf-only lane does not retain a second VM-oracle/browser scene in memory.
All font resources were supplied, and the canvas encloses every corpus node.
Shared glyph LOD uses a 6 logical-pixel minimum without reducing authoring data.

| Seats | Cold preview ms | Loaded-context mount CPU ms | Interaction wall p95 ms | Patch CPU p95 ms | Wheel CPU p95 ms | Document bytes | Scene bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 500 | 161 | 128.8 | 16.8 | 1.0 | 0.9 | 121,926 | 2,557,100 |
| 5000 | 1174 | 1118.6 | 16.8 | 1.6 | 1.9 | 1,229,839 | 32,869,008 |
| 20000 | 5259 | 5122.7 | 37.8 | 5.8 | 7.1 | 4,962,691 | 149,376,706 |

The final 5000-seat cold preview passes 2 seconds; its interaction wall p95
**misses 16.7 ms at 16.8 ms**. Earlier `build/qa/browser/kernel/result.json`
measured 17.6 ms against the preceding 160,298-byte kernel. That historical miss
remains recorded and is not presented as current-kernel performance. The loaded
browser-context mount above includes uncached document compilation, rather than
precompiling the scene for an oracle comparison.

A separate 120-frame scheduling diagnostic,
`build/qa/browser/frame-timing.json`, uses the identical final kernel and actual
RAF callback timestamps while applying one public state patch and wheel zoom per
callback: p95 16.700 ms, wall callback p95 16.800 ms, patch CPU p95 1.7 ms,
wheel CPU p95 1.8 ms, zero intervals above 20 ms. Raw IEEE subtraction produces
16.700000000000273; comparison precision is explicitly 0.000001 ms. This separate
diagnostic does not replace either recorded wall target miss. Machine load was
observed in both runs; no competing Flutter build/test was seen, but the shared
workstation is not claimed exclusive.

Final CDP V8 used heap (cold/loaded context) is 50.1/24.3 MB for 500 seats,
430.0/121.9 MB for 5000, and 1957.8/2079.6 MB for 20000. These are transient JS
heap samples without forced GC; they exclude Flutter/process RSS. The large
20000-seat scene expansion is a measured memory concern. Privacy-rounded
`performance.memory` values are not used as evidence. The 20000-seat authoring
JSON is below 8 MiB. Font fixture JSON is 455,863 bytes (99,903 gzip), separate
from the kernel. Physical-phone frame performance remains unverified.

Raster evidence is `build/qa/raster/result.json` and its self-contained
`index.html`: 144 Flutter/SVG comparisons over two fixtures, four motion times,
three widths, two DPRs and three zooms. The strict four-neighbor edge mask reports
28 failing pairs, 196 interior RGB differences. Those raw failures are retained.
All differences are one RGB step (Flutter 34 versus SVG 33), 188 at a diagonal
color edge within one physical pixel and eight within two. All 144 hard-ink
bounding boxes match; maximum hard-ink centroid delta is 0.374 physical pixels.
The coordinator reviewed aligned representative pairs and accepted this separately
recorded, scoped antialias fringe classification: <=1 channel step only within
Chebyshev distance 2 of an actual measured edge, exact hard-ink bounds, centroid
delta <=0.5 physical pixels. Every nonedge difference must be enumerated. This is
not a global pixel tolerance or an assertion of pixel-identical rasterization.

Six real editor flows passed at 360/900/1440 px and DPR 1/2, with touch at 360,
keyboard actions and reduced-motion contexts: `build/qa/browser/ui/result.json`.
The final detailed organizer journey passes under
`build/qa/browser/final-journey/`: classic template, seventh chair (79 total),
price, Czech multiline serif text, exact 37-degree rotation, color, undo/redo,
local PNG, portable/geometry export, real JS file import of the same bundle,
reopen, corruption rejection, autosave reload and all simulated failure/export
recoveries. The actual paired/standing flow passes independently in
`build/qa/browser/final-picker/result.json`: both Flutter and JS load the same
12-seat/six-pair/20-capacity export, select a two-seat couch and quantity 2 while
keeping total capacity 20 distinct. Flutter uses its real accessible seat list
and quantity dialog; JS uses actual file input, seat selection and quantity UI.
A physical handset, native IME/virtual keyboard and real screen reader remain
unverified. Headless touch emulation does not establish those assertions.
With web accessibility enabled, opening the dynamic diagnostics panel leaves an
Insert semantic pointer rectangle overlapping the font-race control even though
the painted positions differ. The actual keyboard focus/Enter/Space path passes;
post-panel pointer semantics are not claimed universally correct. No CSS override
or forced click was used in final acceptance.


Final distribution evidence is `build/qa/archive/archive-result.json`: actual
pub-selected core/wrapper archives, actual npm pack, byte-equivalent core staging
outside git, clean archive-only nine-template API/gallery consumer, extracted
example release build (17.2 s), nine npm scenes and offline Flutter boot. Browser
checks report zero external requests and zero errors. The wrapper dry run reports
one dirty-checkout warning (exit 65); no fatal validation/analyzer errors were
ignored. The core dry run has zero warnings/errors. No registry publication ran.
The archives are `venue_layout_core.tar.gz` (42,942 bytes),
`venue_seat_picker.tar.gz` (828,310 bytes) and
`festapp-venue-layout-0.2.0.tgz` (442,056 bytes), all under `build/qa/archive/`.
Their exact SHA256/file manifests are in the receipt. Final verification prose
and the additional picker harness were produced after archive capture; runtime
sources remained frozen and the consumer used only extracted package content.

## Acceptance map

`Package` means a real package check can establish the geometry/UI assertion.
`Simulation` means the package/demo host seam can be exercised, while production
business behavior remains B. `B` means intentionally outside this authorization.
A partial package fixture is identified explicitly; it does not establish every manual gesture in the full criterion. Production assertions remain B even when their package seam passes.

| Criterion | Scope and owning evidence | Current status |
| --- | --- | --- |
| DA01 | Archive-only consumer, nine template APIs/galleries/counts/fonts; actual example build | Pass - final extracted archive consumer |
| DA02 | Real editor insertion/undo/redo/save/preview browser gestures; detailed font/color/rotation/export/reopen flow | Pass - final real organizer journey |
| DA03 | Public JS state-patch retention, Flutter paired-unit rollback, lounge quantity host simulation | Pass - actual Flutter/JS paired and standing UI from identical export; simulation only |
| DA04 | Bundle corruption/path/hash rejection, font race controller test; browser autosave/storage/conflict recovery | Pass - final real failure/reload/export journey |
| DA05 | 360/900/1440 DPR1/2 browser pointer/touch/toolbar flows and reduced-motion context; physical keyboard/IME/screen-reader proof remains unverified | Browser matrix passes; native IME/keyboard/screen-reader gap |
| DA06 | Exact VM/browser scenes/hits/text/motion pass; full corpus init/frame/heap measured; reviewed raster and physical-device limitation | Exact parity and reviewed raster pass; measured wall target miss; phone gap |
| DA07 | Build/check/stop kit; browser outbound-request block; automatic owned server cleanup; static report | Build/check/cleanup/offline/manifest pass |
| DA08 | Pub-selected core/wrapper archives and npm archive; extracted consumer; API/resource manifests and no backend imports | Pass - final extracted Dart/npm consumer |
| AC01 | Package stable-ID table reflow and JSON roundtrip; save is local simulation | Package core/reflow fixtures pass; production save B |
| AC02 | Package rotated hierarchy/detach preservation; controller undo/redo | Package transform/detach/undo fixtures pass |
| AC03 | Host constraint simulation can reject sold-slot deletion; real database sold-seat contract is B | Locked-descendant package guard passes; sold-slot authority B |
| AC04 | Package row generator/reconcile numbering fixture; full manual-exception browser path | Generator/manual-ID reconciliation fixture passes; full manual gesture scenario unverified |
| AC05 | Public bus template count/editable geometry; targeted removal gestures | Standalone bus API/gallery counts pass; targeted removal gesture unverified |
| AC06 | Public train template sections/count plus shared scene; production product/spot order is B | Standalone train API/gallery counts pass; product/order integration B |
| AC07 | Package font outline parity and local fixtures; shared production ticket font catalog/picker is B | Exact outlined Czech text/font parity passes; production catalog/ticket bridge B |
| AC08 | Package stale font resolve and failure controller fixture | Controller race/failure pass; real demo race simulation passes |
| AC09 | Package polygon validation, shape serialization and real polygon widget gestures | Core validation and polygon gesture pass; every shape/vertex/alpha gesture unverified |
| AC10 | Package clone/preset fresh IDs; full rotated-parent drag/drop scenario | Clone/preset ID-remap fixtures pass; full rotated-parent preset drag scenario unverified |
| AC11 | Package rotated/inverse-hit parity; UI resize/rotate/pivot gestures | Core rotated hit parity and widget resize pass; all pivot/snap gestures unverified |
| AC12 | Package canvas reject/fit/cancel and rotated bounds | Package canvas bounds/fit/cancel fixtures pass |
| AC13 | Package background placement/registration/clip; local replacement/undo scenario; production uploads B | Crop/registration exact parity + replacement aspect/undo widget pass; local PNG pass; production upload B |
| AC14 | Local resources/history simulation; actual production upload ownership B | Retained local resources/bundle corruption tests pass; full failed-upload/remove/undo UI scenario partial; production ownership B |
| AC15 | Local deterministic conflict simulation only; two-editor SQL revision lock requires B | Conflict simulation pass; two-editor SQL revision lock B |
| AC16 | No SQL receipt/retry proof in A | B - not exercised |
| AC17 | No two-session hold/finalize/save lock proof in A | B - not exercised |
| AC18 | Package structural/size validation; tenant/product scope and domain rollback require B | Strict package structure/budget rejection pass; domain/auth rollback B |
| AC19 | No production legacy conversion in A | B - not exercised |
| AC20 | Package clone ID remap; occasion setup/finalize/product map require B | Package clone remap pass; setup/finalize/product map B |
| AC21 | Flutter/JS callbacks and pending/reject simulation; real reservation spot identity requires B | Flutter/JS pending/reject simulation pass; actual reservation spot ID B |
| AC22 | Emulated touch/reduced-motion/focus/UI checks; physical IME/screen reader and virtual keyboard unverified | Emulated browser matrix/keyboard/reduced-motion pass; device/IME/screen-reader gap |
| AC23 | Exact scenes pass; fixed camera/DPR/zoom/motion raster corpus reviewed; measured perf above | Exact scene + reviewed raster pass; frame/init/heap measured, wall target miss and phone gap |
| AC24 | Actual extracted Dart/npm archives and standalone consumer | Pass - final extracted standalone consumer |
| AC25 | Package paired-unit selection simulation; tickets/scan/cancellation/swap/finance require B | Paired-unit package selection/rejection pass; real ticket/scan/finance B |
| AC26 | Package quantity callback simulation; inventory/checkout atomicity requires B | Standing quantity2/20 callback passes; real capacity/checkout atomicity B |
| AC27 | Controller automatic expansion/return/cancel/undo; real gesture coverage | Controller expansion/return/cancel/undo pass; actual beyond-right insertion pass; four-edge pointer corpus partial |
| AC28 | Package geometry+host history participant simulation; production persisted product defaults require B | Geometry/host shared history and reload simulation pass; attachment-price complete scenario partial; production defaults B |
| AC29 | Public ballroom templates and organizer browser flow; actual persisted product pricing requires B | Final organizer journey passes including seventh chair/price/37-degree rotation; production pricing B |

Performance goals remain the original contract: desktop 5000-seat p95 frame
<=16.7 ms, representative phone <=33 ms, cold usable 5000-seat preview <=2 s,
kernel gzip <=500 KiB, and 20000-seat authoring JSON <=8 MiB. Missing or failed
goals must be stated explicitly; the corpus size is not silently reduced.

Known production boundaries remain B/C: authentication/authorization, SQL writes,
reservation idempotency and locks, inventory and payment behavior, shared
production font/image services, legacy conversion/contraction, registry
publication and tenant activation.

### Desktop assembly interaction follow-up - 2026-10-18

Selection is now dispatched on primary pointer-down, before Flutter's double-tap
timeout. The surface regression asserts the callback before any timer/frame
advance and separately confirms double-click and handle isolation. Row gap
selection, eight aggregate handles, anchored whole-assembly resize, preserved
seat identities/dimensions, fixed canvas and one-step undo have widget coverage.
Selection-only controller notifications no longer rebuild/persist the demo shell;
reselecting an identical validated selection emits no redundant notification.

The full Flutter batch passed 98 tests with one opt-in raster skip. After the
final steep-arc minimum-size fix, all 8 affected row/surface widget tests passed.
The final core batch passed 106 tests, including collision-free table attachment
and ten row resize cases. Targeted analyzer is clean. This verifies event timing
and correctness; it is not a new 5000-seat frame-rate benchmark.

An isolated headless desktop browser also created a 5x8 curved assembly through
the palette, dragged its southeast handle, retained all 40 chairs, and selected
it through a gap after deselection. Selection left the persisted bundle unchanged.
Screenshots: `build/qa/assembly-rows-selected.png`,
`build/qa/assembly-rows-resized.png`, `build/qa/assembly-gap-selected.png`.
The rebuilt JS kernel's 7 tests pass; the final demo source manifest matches.

### Table resize and wall placement follow-up - 2026-10-18

Final core suite: 120 tests pass. New coverage exercises safe free-seat removal,
protected trailing IDs/atomic units, reference cleanup, all four walls/corners,
independent chair slot position/orientation and rejection of occupied slots.
The full Flutter batch passed 102 tests with one opt-in raster skip and exposed
one incoming-attachment/manual-mode regression. The focused final interaction
batch checks that correction together with circle/Shift-ellipse behavior,
protected rollback, resize history, transparent centered feedback and notices
that leave the canvas viewport unchanged. Live host protection is simulated in
controller tests; this local demo does not execute production reservations.

Browser follow-up caught two fixture gaps before handoff: the real demo uses
190x110 tables (requiring canvas-clipped chair slot phases), and its round-table
palette uses `shape:ellipse` with equal dimensions. Final tests now cover those
actual representations. Final geometry suite: 121 tests pass; thirteen affected
widget tests passed after those corrections.

Selection-context regression checks cover switching from a scrolled object to
another object's top-level properties, keeping scroll during same-object moves,
returning global settings on deselection, and the multi-selection inspector.
Multi-selection gesture coverage checks Shift toggle even if key-up precedes
delayed tap recognition, dragging through a row child without collapsing the
set, atomic history, additive marquee, and plain-click focus without text editing.

Final combined Flutter suite: 105 pass, one opt-in raster skip. Final desktop
browser verification confirms the real190x110 demo table at exact corner center
(95,55), all six chairs retained; palette round table shrunk from160x160/6chairs
to88.412109375x88.412109375/5chairs. A marquee selected three tables and a
subsequent member drag moved all three by identical (45,55) coordinates. The
inspector showed the active object's name/properties and the multi-selection
context, with unrelated canvas controls absent. Runtime source manifest matches.

### Couch geometry and vector drawing follow-up - 2026-10-18

Full Flutter suite:108passed, one opt-in raster skip. Final affected drawing,
path selection and navigation batch:11passed. Final core suite:135passed,
including6couch geometry,3shared furniture scene and5path insertion/removal
regressions. The furniture scene uses the same paths in Flutter/JS, retains
hit/seat identities, suppresses sofa name glyphs, and honors selected/occupied/
custom host cushion colors. Table corner aliases/defaults and explicit zero are
covered. Final targeted analyzers are clean.

An isolated desktop browser created a couch through the palette, increased it
from2to4actual seats, drew a line with two clicks and a live cursor preview, and
dragged its midpoint to create a3vertex polyline while retaining the path ID.
Artifacts: `build/qa/couch-four-seats.png`, `vector-line-live-preview.png`,
`vector-line-completed.png`, `vector-bend-created.png`.

The final rebuilt desktop runtime was reloaded and checked again: localized path
inspector omits ticket price controls for shapes, couch4seat state persisted with
body width176, and a3point polyline was drawn through successive clicks + Enter.
Final runtime manifest matches; JS suite7/7passes. Browser session closed.

### Symmetric couch sizing and centered wall rows - 2026-10-18

Final core suite:139pass. Full Flutter suite:108pass, one opt-in raster skip.
Targeted core analyzer clean. Coverage includes reversible default/custom rotated
couch count dimensions, stable cushion and atomic unit IDs, wide366x128table
with6top/6bottom/2blocked-side chairs, mirrored wall transfer, normalization of
already-contained uneven wall drafts and idempotence; previous190x110corner
fixtures still pass.

An isolated headless desktop browser verified couch2/160 ->3/232 ->2/160 with
the actual inspector controls and persisted local bundle. It then loaded the
wide-table regression fixture and physically dragged it to the right wall:
center(817,300), top/bottom x=-142.5,-85.5,-28.5,28.5,85.5,142.5; opposite
left chairs y=-26,+26, no right chairs, all14IDs retained. Screenshot:
`build/qa/table-wall-centered-final.png`. Runtime source manifest matches.

## Regular zigzag clarification - 2026-10-18

Read-only canonical reference lookup identified KDU-ČSL Ostrava-Jih / Farní ples
2026 / K-Trio. Its SVG uses regular black zigzag divider fragments, eight diagonal
legs per fragment. This supersedes the earlier freeform-polyline palette behavior.

Core: 145 tests passed, including six zigzag geometry/identity/validation cases.
Flutter: 108 passed, one opt-in raster skip. Targeted editor analysis is clean.
Release demo rebuilt; source manifest matches. Isolated headless native-pointer
check drew a vertical zigzag with two clicks, verified Czech pattern controls,
endpoint/height handles and persisted zigzag metadata. Evidence:
`build/qa/zigzag-drawn.png`, `zigzag-flutter.log`, `zigzag-analyze.log`,
`zigzag-demo.log`. Browser session closed after checking.

Zigzag tooth stepper: plus/minus buttons update the selected path immediately,
retain its ID/endpoints and support undo per click. Buttons respect read-only,
saving and 1-255 limits. Focused couch/vector widget suite: 3 passed
(`build/qa/zigzag-stepper-test.log`).

## Palette bounds, localization and appearance - 2026-10-18

Palette previews cancel outside the actual canvas, including outside drops with
no history entry. Appearance exposes table/assembly seat fills, multi-object
fill, an always-visible canvas color field and the existing host image importer
in the background section. Color dialogs receive document colors and the
decoded background for artwork suggestions. Group placeholder dimensions/fill
are hidden. Numeric assembly dialog field labels now use package localization;
the Czech catalog covers preview/assembly/background/settings messages.

Targeted analysis clean; full Flutter suite 114 passed, one opt-in raster skip.
Tests include bounds re-entry/drop rollback, atomic chair color/undo/used palette
and host background callback reachability. Release demo rebuilt and source
manifest matches. Isolated native-pointer browser review confirmed visible
canvas color, background upload control and Czech used-color suggestions
(`build/qa/appearance-used-colors.png`). Native OS file selection was not
automated; image import retains the existing bounded host importer. Browser closed.

## Actual-scale drag feedback and object styles - 2026-10-18

Palette feedback uses the shared painter at the actual canvas scale and aligns
the canonical origin, including asymmetric/rotated fragments. A stable per-drag
fragment is kept independently of the cancelable canvas preview. Native browser
testing found a null-lifetime error on gray-area crossing; the final fix retains
the same fragment through crossing/re-entry and is covered by a real drag test.

Style is visible immediately below object name. Named palettes and independent
object/chair colors reuse the shared color dialog. Right-click and touch long
press expose style, copy/paste style, duplicate, layer order and delete actions.
Styles preserve geometry/labels/seat identity, honor locked ancestors, and keep
open paths transparent. The OS/browser context menu is suppressed only inside
the editor canvas with custom actions.

Final targeted drag/appearance/context batch: 10 passed; final analysis clean.
Full-suite retained evidence: 116 passed, one opt-in raster skip; two new fixture
failures corrected and all three context/style tests subsequently passed. No
runtime source changed after final build; demo manifest matches. Isolated native
right-click/style application and gray-crossing/drop checks passed without
console errors. Evidence: style-context-menu.png, style-context-dialog.png,
style-drag-scale-fixed.png and style-drag-placed-fixed.png under build/qa.
All browser sessions closed.

## Editor grid - 2026-10-18

Ticket editor reference: optional grid, disabled by default, constant screen
stroke. Blueprint adds independent Grid chip and G shortcut, aligned to the
existing world-origin 8-unit snapping lattice. Adaptive multiples avoid dense
moire at low zoom; painting is limited to the visible canvas, after background
and before objects. Viewer/drag feedback remain grid-free by default.

Targeted analyzer clean; 22 targeted widget/navigation tests passed, including
grid toggle/keyboard, unchanged snapping, document/history and painter wiring.
Demo rebuilt; source manifest matches. Isolated browser native click confirmed
visible clipped grid and no console errors (`build/qa/grid-visible.png`). Browser
session closed.

## Shared plan-wide appearance - 2026-10-18

154 core tests passed, including nine appearance contract/scene cases; compiled
JS kernel roundtrip and full/partial scene inheritance passed. Flutter full suite
125 passed, one opt-in raster skip. Seven JS tests passed. Targeted analyzer
clean. Final release demo rebuilt and source manifest matches.

Coverage includes strict immutable contract/roundtrip, all-kind preset one undo,
local exceptions and reset, numeric validation/commit, scope targeting, shared
color suggestions/alpha, future objects, unchanged identity/geometry and state
color precedence. Native isolated browser changed all existing furniture with
the Warm global preset, placed a new inheriting table, and transferred the same
bundle into the JS customer preview with matching style and no console errors.
Evidence: build/qa/plan-style-{dialog,applied,new-table,web-preview}.png and
plan-style-{analyze,flutter,js,demo}.log. Browser closed.

## Inspector simplification - 2026-10-18

Global preset cards now reuse the shared colored style previews. Canvas color,
size and image controls live in one expanded Canvas section. Per-object style
controls are collapsed below primary seating/geometry; context styling remains
available. Reusable-object library/save/import/export entrypoints and the demo
price inspector are removed. Duplicate/delete remain; Group appears for multiple
objects and Ungroup only for ordinary groups. Portable preset and host-price
data contracts are untouched.

Analyzer clean. Full Flutter suite: 125 passed, one opt-in raster skip. Final
canvas spacing fix: four affected appearance/context tests passed. Final demo
rebuilt and source manifest matches. Isolated native browser review verified
colored global presets, uncluttered selected-object panel, unified Canvas and
fixed floating-label clipping. Screenshots: inspector-global-style-previews.png,
inspector-object-default.png, inspector-unified-canvas-final.png under build/qa.
Browser sessions closed.

## Palette versus appearance, schematic chair materials - 2026-10-18

Global styling has explicit Colors and Appearance tabs. Palettes change only
fill/stroke/text colors and canvas background; material, corner radius, stroke
width and opacity remain unchanged. Appearance independently selects plain, wood
or upholstered seats and numeric shape controls. Preset thumbnails render the
canonical scene. Canvas starts collapsed, automatic seat filling is removed,
and Czech UI consistently uses plánek.

Core: 162 tests passed; compiled JS parity passed 12 style/state cases. Flutter
initial full batch: 125 passed, one opt-in raster skip, one old wording expectation
updated to plánek and then passed in the focused localization run. Affected
style/editor/context batch: 33 passed. Final segmented-tab/global/localization
batch: nine passed. Analyzer clean; seven JS tests passed. Final demo rebuilt and
manifest matches source. Native isolated browser independently applied the Warm
palette and Wooden seat appearance, verified persisted style-only keys versus
color-only keys, and visually confirmed schematic wood slats and canvas tint
without console errors. Evidence: palette-colors-tab.png, palette-appearance-tab.png,
palette-chair-appearance.png, wood-chairs-canvas.png under build/qa. Browser closed.

## Selection, live appearance previews and architecture - 2026-10-18

Inspector close and Escape clear selection without document/history mutation.
Text inputs keep their Escape cancellation. Appearance has canonical live
specimens for every supported scope and three selectable chair material cards;
Colors remains independent. Added cached specimens do not compile the working
plan. Both English defaults and Czech clear/preview messages are available.

The shared editor/viewer/picker surface now owns one `LayoutSceneCache` adapter
for geometry and presentation patches. Parent changes invalidate descendants;
structure/global/resource edits and compiler issues use full compilation.
Unchanged display items retain identity. Five dedicated cache regressions prove
exact full-scene parity, unchanged-item reuse, combined state/geometry changes,
structural invalidation, invalid-document recovery and missing-font recovery.

Core comparison helpers replace controller whole-document JSON comparisons and
retain O(1) immutable selection snapshots. Furniture atomic-capacity lookups are
indexed. Inspector color collection is lazy; one index and one selection snapshot
serve each build. Geometry-only changes reuse the layer projection/row subtree;
collapsed layers skip projection/row creation. Search, labels, hierarchy, z-order,
locks and context reset remain covered.

Final validation: 169 core tests; complete Flutter suite 148 passed and one
opt-in raster test skipped; seven JS tests; targeted analyzers clean. Final demo
kit rebuilt and source manifest verified. Isolated native browser confirmed the
selection close affordance, live table specimen, and all three chair material
cards. Screenshots: architecture-selected-close.png, architecture-appearance.png,
architecture-chair-previews.png under build/qa. Browser session closed afterward.

Final idle VM diagnostic (`tool/benchmark_layout_scene_cache.dart`, eight measured
samples after four warmups): 5000 static seats plus one moving six-chair table,
full scene median 23.536 ms, incremental cache median 2.216 ms, exact scene equality
in every sample. Snapshots are prevalidated equally; this measures scene CPU work,
not end-to-end frame time. Inspector instrumentation reduced selection reads from
41,632 to eight across eight 5000-seat/100-selected notifications. Debug widget
pump timing improved too, but concurrent core optimizations and debug execution
prevent an isolated release-performance claim.

[Data/performance audit](AUDIT-2026-10-18.md) records reservation fixes, stable
seat/parent/atomic membership, production DB binding gaps and remaining validation
cost. No production database, tenant or dependency pin changed. The 5000-seat
16.7 ms full-editor drag budget is not established by these CPU diagnostics.

## Actual furniture appearance families - 2026-10-18

The user's clarification replaces decorative-only chair styling as the primary
Appearance workflow. Modern, Timber and Lounge are coordinated one-click visual
families with canonical composite previews of chairs, tables and couches. Numeric
per-kind controls are collapsed under Fine-tune appearance. Colors remain
independent. Family application and color-palette application each construct one
snapshot and go through controller validation once, with one undo checkpoint.

Core `objectStyle` is a strict simple/wood/lounge visual enum. Timber chairs have
a tapered seat, backrest, posts/leg hints and tan material frame; Lounge chairs
have a round seat and curved back. Tables have family-specific rim/joinery;
couches have family-specific arms, backs and cushion treatment. The shared
node-outline module owns both visible paths and hit contours. Original authored
footprints, transforms, table shapes, IDs and atomic memberships remain unchanged.
Couch cushions stay cushions; automatic legacy oval-table seat facing is corrected
visually while manual chair poses are retained.

Validation: 175 core tests, 23 affected Flutter tests, seven JS tests; analyzers
clean. Exact VM/compiled-JS parity passed 12 nested/family/state cases and 1080 hit
probes. Fixtures are retained under build/qa/appearance-families. Demo rebuilt;
manifest matches final runtime sources. Native isolated browser reviewed the
three distinct family previews and applied Timber to the plan; existing canvas
objects and palette thumbnails both inherited it. Persisted data contained
visual-family keys and retained colors/IDs/counts. Screenshots under build/qa:
appearance-families-dialog.png and appearance-families-timber-canvas.png.

## Object library presentation - 2026-10-18

Object tiles now use compact outlined controls with consistent preview zones,
optically sized canonical thumbnails, restrained hover/selected/focus treatment
and two-line centered captions. Standing previews omit redundant internal names;
text uses an Aa specimen. All thumbnail canvases are transparent.

`LayoutPaletteThumbnail` is a display-only painter, with no camera, gesture,
focus or interactive surface per tile. Immutable themed preview documents are
retained across geometry-only editor updates; appearance changes invalidate them.
Drag feedback still uses the actual insertion fragment and canvas scale.
The existing catalogue regression now verifies transparent, centered previews of
all supported kinds and a single interactive canvas. Targeted editor/feedback/
drop batch: 24 passed; analyzer clean. Native desktop review at 1440x900 caught
one long Czech caption; fixed-height two-line captions preserve its full name.

## Round table details, bars and missing web seats - 2026-10-18

Round/ellipse table rims now use the same proportional inset on both axes;
circular tabletops retain circular rims. Wooden round tables replace rectangular
plank seams with a small circular detail clear of upright names, including at
90-degree tabletop rotation.

The Bar palette component creates a counter and four stable stool seats. Inspector
controls guest side/count/dimensions. Infeasible side changes leave geometry,
identity, history and displayed dropdown value unchanged and explain how to fix
placement. Guest-only reflow, wall clamping, protected shrink, stool attachment,
all appearance families, schema and import constraints use the existing core
node/attachment authority. Catalogue previews, naming and localization support Bar.

The web seat bug was reproduced before the fix with only two chairs and a native
pan in a wide SVG. preserveAspectRatio=meet exposes more world area than the
nominal viewBox; culling incorrectly discarded a chair that was visibly inside
the actual SVG viewport. The adapter now derives conservative visible bounds
from all four viewport corners through inverse getScreenCTM, and observes SVG
resize. Disposal disconnects its observer. Tests cover wide/tall views, resize,
partial presentation patches, three chair families, background and zigzag layers.
The fix retains culling and canonical paint order.

Final checks: 186 core tests, 44 targeted Flutter/editor/controller tests, ten JS
tests; targeted analyzers clean. Exact VM/JS parity passed 52 bar/rim/state cases
and 2160 hit probes (fixtures under build/qa/bar-viewer). Final static demo built
and source manifest verified. Native browser inserted a bar, reviewed its controls
and opened the editor's actual web-preview handoff. All 76 seat centers inside
the SVG had rendered nodes before and after a native pan to viewBox
507.61421319796955 0 1600 1200, including the left-side places outside the nominal
viewBox. No browser errors. Screenshots: bar-palette-desktop.png,
bar-inserted-desktop.png, bar-web-pan-visible-seats.png under build/qa.

## Transport schematics, floor materials and bounded cameras - 2026-10-19

Added subtle plain/wood/tile/carpet floors as one bounded canonical path, with
custom background precedence, shared previews, family presets and a collapsed
canvas control. Inspector geometry is collapsed; open paths expose outline
color, thickness and type directly. Form sections reserve space for floating
labels. Bus/coupe templates now use the same assembly factories as insertion.
Single/double-deck bus and carriage schematics include physical outlines and
operating features; count controls reconcile stable seats and reject protected
removal. Transport rotation uses its actual footprint; misleading resize handles
are omitted because seat/row controls own these assemblies' dimensions.

Camera regressions reproduced excessive zoom-out and pan-away. Flutter's XY
scale now excludes its unchanged Z-axis; both viewers clamp minimum zoom to
90% of canvas fit and bound pan, preserving pointer anchors and Shift-pan.

Validation: all 195 pure-core tests pass; targeted Flutter suites passed,
including final transport/rotation and five navigation regressions; 11 browser
JS tests pass. Initial Flutter checks caught a generic-decoration validation
regression and stale protected-seat capture; both were corrected and their
8-test recheck passed. Targeted analyzers are clean. Receipts:
`build/qa/floor-transport-inspector-{flutter,recheck,analyze}.log`,
`floor-transport-handles.log`, `floor-transport-surface-analyze.log`,
`floor-transport-js.log`, `floor-transport-demo-build.log`.
Transport/floor Dart VM versus compiled JS parity passed 12 scenes and 1296
hit probes (`build/qa/transport-floor-parity.json`). Final demo runtime source
manifest matches. An isolated headless browser verified Czech labels, material
previews and floor selection, canonical bus template, selecting via body gaps,
collapsed geometry and correct rotation handle. Screenshots:
`floor-transport-families.png`, `floor-transport-fine.png`,
`floor-transport-bus-final.png`, `floor-transport-selected-final.png`.

Vehicle drawings are configurable generic schematics. Production reservation
binding remains the separately scoped Stage B integration.

## Centreline surface sketch, branch handles and template library v2 - 2026-10-19

Dedicated Draw table / Draw bar tools sketch a centreline and generate a closed
editable footprint around it, with a live breadth control. Drag creates a
straight surface; successive clicks plus Enter create bends. Edge plus handles
pull out shouldered branches in the pointer direction. Vertex handles reshape
the outline. Names, stable root IDs and one-command undo are preserved. New bars
have no stools or stool controls; previously authored explicit stools survive.
Concave tables reconcile safe outward seat positions through the existing
protected-seat contract. Both renderers use the canonical polygon path.

Template library v2 has three styled ball variants, a cinema, a theatre with
balcony/backstage, a conference/reception layout with a U counter, transport
layouts and retained balcony/lounge/blank presets. Material families are shared
pure-core data used by templates and UI. Transit adds contoured seats, headrests
and armrests, with travel direction arrows in transport schematics.

All 201 core tests pass. The targeted Flutter batch ran 54 real tests; one
outdated preview-count assertion was updated for the fourth family and its
9-test recheck passed. An erroneous nonexistent test path in that batch was
removed from subsequent commands. The final 3-test surface editor suite passes
centreline-U drawing, actual pointer extrusion and undo. Targeted analyzers and
all 11 web tests pass. Final demo build succeeded; runtime source manifest
matches. Twelve material/surface VM-JS scenes and 48 hit probes match exactly.

Receipts: `build/qa/surface-{core-final,flutter-tests,global-style-recheck,
editor-final,templates-analyze,templates-demo,js-tests}.log` and
`surface-parity.json`. An isolated headless browser drew a U counter, pulled a
diagonal branch and opened the public web preview; the transferred document had
one surface, 12 polygon vertices and zero seats. No browser errors were reported.
Screenshots: `surface-classic-final.png`, `surface-gallery-final.png`,
`surface-gallery-bottom.png`, `surface-sketch-u-final.png`,
`surface-branched-final.png`, `surface-web-final.png`.


## Modular surface painting and real seating references - 2026-10-19

This supersedes the centreline editor interaction above. Paint table / Paint bar
joins whole virtual grid cells under the held pointer. Each cell is 100 x 100
world units, a compact table with one seat on each side (four perimeter slots).
The same lattice is drawn during painting; there is no small-pixel brush size
control. A stroke stores one polygon, supports branches and enclosed cutouts,
and commits one undo step. Boundary edges cancel incrementally, repeated visits
to a cell do not rebuild the preview, and fast pointer jumps fill intervening
cells. Seat identities and normal selection/editing remain canonical.

Cinema now has 198 seats in continuous tapered rows, lateral access and a cross
aisle, with a visible screen label. Theatre has 188 seats in continuous curved
stalls, six side boxes and a balcony, with stage/backstage/orchestra pit labels.
Train has two nine-compartment carriages (108 seats), opposing three-seat columns
per compartment, a side corridor, sliding doors, windows, end vestibules and WC.
The templates are synthetic, not replicas of the referenced venues.

References inspected as rendered plans:
- https://www.cinestar.de/media/Kinos/FrankfurtMain-Metropolis/Downloads/Saaluebersicht-Sitzplaetze.pdf
- https://www.divadlonavinohradech.com/content/files/DOKUMENTY/vecerni_odpoledni_odzari.pdf
- https://seznam.cd.cz/zeleznicar/provoz-a-technika/projekt-mnichov-ziskava-tvar-v-nymburce/-18279/21%2C0%2C%2C/

Final validation: 206 core tests, 34 targeted Flutter tests, 11 web tests passed;
targeted analyzer clean. Demo rebuilt with a matching runtime source manifest.
Logs: build/qa/module-{core,flutter,analyze,js,demo}.log. An isolated headless
browser painted a U with a side branch on a blank canvas, verified the module
grid and Czech guidance, then transferred the single seatless surface to the
public SVG viewer. Screenshots: build/qa/module-{grid,painted,web-final}.png.
Gallery previews of cinema, theatre and carriages were visually inspected.


## Free perimeter seating, material contours and gesture grid - 2026-10-19

Moved table chairs now treat nearby physical objects as unavailable perimeter
space. A spatial query limits candidate tests to neighbouring objects. Only the
moved table's attached chairs are rearranged; stationary neighbours and seat IDs
remain unchanged. Manual positions yield when obstructed, locked positions stay
fixed, and an infeasible translation returns the gesture baseline without losing
chairs. Updated an older regression whose explicit expectation that neighbours
never obstruct chairs was superseded by this request. New tests cover both
rectangular and painted concave tables plus a fully obstructed destination.

Custom polygon tables and bars now share material-family rims and wooden plank
joints with ordinary tables. Offset contours follow concave branches and holes;
joints are clipped to filled intervals. Scene decorations leave persisted
geometry and hit regions unchanged. All three non-simple families are covered
for both custom tables and bars, including enclosed holes.

Painting grid is hidden before the gesture. The first module is centered at the
start point (clamped only at canvas edges); this becomes the temporary grid
origin. Subsequent whole modules and visible grid lines use that same origin.
The normal editing grid preference is independent and preserved.

Validation: 216 core tests, 19 targeted Flutter tests and 11 web tests passed.
Analyzer clean. Logs: build/qa/followup-{core,flutter-final,analyze,js}.log.
Final demo build: build/qa/followup-demo-final.log. Isolated headless browser
confirmed hidden-before/visible-during grid, painted a wooden L surface, and
opened it in the public SVG viewer. A real pointer drag moved Table 3 towards
Table 4 and relocated the obstructed right chair into a centered two-chair left
row while preserving six seats and the neighbouring table. Screenshots:
followup-before-grid.png, followup-grid-started.png, followup-painted-wood.png,
followup-neighbour-drag-final.png and followup-web-style.png in build/qa.

One warmed synthetic Dart VM timing (100 moves, 808 nodes) averaged 5.15 ms per
bounded table movement; this measures core movement, not browser frame time.
Receipt: build/qa/followup-move-benchmark.log.


## Rounded custom surfaces and narrow painted bars - 2026-10-19

Custom table/bar polygon contours now follow the active family corner radius,
including concave corners, hole contours and inset material rims. The shared
canonical path supplies both Flutter and SVG plus visual hit contours; authored
polygon vertices and seating identities stay unchanged. Oversized radii are
locally bounded by adjacent edges. Bar painting uses 60-unit modules/grid, versus
100-unit four-seat table modules, with matching Czech tool guidance.

Validation: existing full 216-test core suite, final 12-test surface regression
suite (including two new corner-hit/large-radius cases), 17 Flutter tests and
11 web tests pass; targeted analyzer clean. Receipts in build/qa/rounded-narrow-
{core,regression,flutter,analyze,js,demo}.log. One new test probe was corrected
from 5 to 3 units from a corner to account for the same quadratic fillet used by
ordinary rounded rectangles. Demo rebuilt and runtime manifest matches.

Isolated headless browser verified narrow bar painting, rounded L table and bar
in the lounge family and their SVG preview. During the rapid style-dialog input
sequence the headless render became blank without reported JS errors; reload
restored the persisted lounge document. Slower subsequent painting succeeded.
Screenshots: rounded-narrow-bar.png, rounded-narrow-unselected.png and
rounded-narrow-web.png in build/qa. This transient browser observation is not
covered by the targeted unit tests.


## Original scout hall template and graphical comparison - 2026-10-19

The user selected the Skautský ples 2026 reference (182 seats), superseding the
initial investigation of the 280-seat Větřkovice variant. Only the selected scout
hall is added to the library, as `scout-ball-182`, the thirteenth template in
library v3. The temporary unselected template and extractor were removed.

Source: the existing private local configuration snapshot, grid 32 x 32, 31
numbered tables; 29 tables have six seats and tables 18/19 have four each. Every
seat label, world coordinate and table membership is preserved. Source raster
SHA256: 37a346f6c7063c3e10cef03d462f736cefe41d7610e713bdaaaf3e778b807d77.
The original 3000 x 3000 raster was visually inspected, and the black rectangle
edges were read against expected seat-lattice positions to review all 31 table
footprints, room boundary, stage, entrance and two columns. Separate edge runs
preserve the small gaps between the bottom vertical table pairs. The reviewed
bounds are in tool/fixtures/scout_hall_geometry.json. Geometry-only generated
Dart data has SHA256 e99d23db32b931ce35d7d509df45560d78766e66aaa0819bc0d6491ed80b5cf0.
Source products, states, orders and database identities are excluded. The source
raster remains a local comparison artifact and is not a runtime/package asset.

Native nodes reconstruct the layout without a background bitmap dependency.
The Traditional hall appearance family supplies wooden chairs, a plain floor
and coordinated 14-unit table corners; the selected template uses a restrained
ivory/sage palette. Choosing a template now remounts only the editor surface to
fit its new canvas immediately. Ordinary edits do not reset the viewport.

Final targeted validation: 218 core tests, 29 Flutter tests including exact
182-seat registration, group counts, source footprint bounds, fresh identity,
serialization, cloning and existing style/navigation coverage; 11 web tests.
Targeted analyzer clean. Logs: build/qa/scout-{core,flutter,analyze,js,demo}.log.
The final runtime source manifest matches the rebuilt demo.

An isolated headless browser selected the new gallery card, verified automatic
whole-canvas fit, visually inspected every hall region with all 182 chairs and
opened the same document in the actual SVG viewer (182 seats, 31 tables).
Screenshots: scout-gallery.png, scout-editor.png, scout-web.png in build/qa.

Graphical evidence: build/qa/scout-comparison.html is self-contained and works
from file://. It places the original raster plus original seat-coordinate marks
beside the actual SVG extracted from the new viewer; overlay mode has adjustable
opacity and the original markers can be toggled. Both embedded original images
load at 3000 x 3000, the slider/overlay interaction was checked and the original
marker count is 182. Screenshots: scout-comparison-final.png and
scout-overlay-final.png. The comparison intentionally shows changed furniture
styling and font treatment; it is not a claim of identical raster pixels.

### 2026-10-19 - table selection and second scout hall

- Reproduced the reported click regression with the actual `scout-ball-182`
  document and editor selection callback. Core hit testing returned the table;
  editor parent mapping incorrectly selected the hall section. The regression
  failed before the fix and passed afterward. Coverage also checks Shift selection,
  individual table seats, Escape deselection and ordinary atomic object groups.
- Read-only canonical tenant source: second Skautský ples 2026, 6 February,
  form `/form/12c6facd8b9c4ef5afa201669869a750`. Verified activation, tenant
  organization, SSH hostname and active database. No production writes.
- `scout-ball-balcony-249`: all 249 original world positions, labels and group
  assignments; 21 exact SVG table footprints, 234 attachments and source group
  22's 15 seats without an invented tabletop. Structural digest:
  `fa8d556db13c686e64f379fc4d80cf23268e78dcd95ff3114bb2e581e4221024`.
- Targeted Flutter selection/template/controller/style suite: 28 passed.
  Core appearance/furniture scene suite: 12 passed. Web suite: 11 passed.
  Targeted Dart analyzer: no issues. Demo kit rebuilt successfully.
- Isolated headless browser: real pointer selection of table 1 in both scout halls
  opened table properties; inspected new gallery, editor and web viewer. The viewer
  painted all 249 seat IDs, with no missing seat primitives.
- Visual evidence: `build/qa/scout-table-selection-fixed.png`,
  `scout-balcony-selection.png`, `scout-balcony-editor.png`,
  `scout-balcony-web.png`; self-contained graphical reference comparison:
  `build/qa/scout-balcony-comparison.html` (side by side and opacity overlay).

### 2026-10-19 - table relationships and distinct banquet seating

- Editor-only attached-chair outlines and short dashed perimeter connections;
  tabletop retains the sole selection hull and all eight resize handles.
- Added separate banquet chair geometry to the shared core and public style enum;
  regenerated the JSON contract. The scout balcony family now uses this geometry
  rather than the lounge upholstered chair.
- Targeted Flutter run: 20 passed; a new rotated-link check exposed inconsistent
  matrix precision. Connection transforms were aligned with scene quantization;
  both new geometry/handle tests then passed (21 distinct targeted tests overall).
- Core banquet/appearance/furniture scene checks: 13 passed. Targeted analyzer
  clean, including the final connection helper after the precision fix.
- Final painter additionally culls off-screen connection segments and bounds dashed
  work for exceptionally distant manual seats. The two relationship tests passed
  again; final painter analyzer clean. Rebuilt demo kit after these changes.
- Isolated headless visual check: selection outlines all ten chairs at table 1 of
  the scout balcony hall, while eight handles enclose only its tabletop. Inspected
  both fit and zoomed views, localized inspector explanation and distinct tapered
  banquet geometry. Web viewer reports `seatStyle: banquet` and paints all 249
  seat IDs. Web tests: 11 passed.
- Evidence: `build/qa/table-links-selected-detail.png`,
  `build/qa/table-links-selected-fit.png`, and self-contained actual-render detail
  `build/qa/banquet-chair-detail.html`.

### 2026-10-19 - original minimalist scout floorplans in V2

- Both source templates now use the existing simple/plain presentation and original
  floor/table colors. Source-sized V1 green rounded seat markers replace material
  furniture details. All 182 / 249 seat identities, labels, world coordinates and
  memberships remain covered by the original reference tests.
- Balcony `Stůl N` labels follow vertical tables using optional `labelOrientation:
  object`; the default remains screen-oriented. Contract validation/serialization,
  full/partial compilation and unchanged default orientation are regression-tested.
- Flutter template, selection/handle and gallery checks: 9 passed. Core and
  appearance checks: 37 passed; new label-orientation check passed after correcting
  its test assertion to use LayoutIssue.reason (38 distinct core checks). Targeted
  analyzers clean. Balcony checks rerun after making all 16 stair treads render
  above the balcony floor: 2 passed. Web checks: 11 passed.
- Rebuilt demo kit. Isolated headless browser screenshots captured both native V2
  editors and actual viewer output. The viewer paints all 182 / 249 seat IDs and
  all 16 stair treads have foreground z-order.
- Self-contained comparison `build/qa/scout-minimal-comparison.html` contains original
  raster/SVG backgrounds with the existing V1 available-seat styling, alongside
  actual new viewer SVGs. Switchable hall variants and opacity overlay were checked;
  no horizontal page overflow. Source availability markers are structural examples,
  not copied reservation status. Geometry is transferred, not flattened to an image.
- Evidence: `scout-minimal-182-editor.png`, `scout-minimal-249-editor.png`,
  `scout-minimal-182-comparison.png`, `scout-minimal-249-comparison.png`,
  `scout-minimal-249-overlay.png` under `build/qa/`.

### 2026-10-19 - V1 checking parity, basic style and physical chair rules

- Shared core selection feedback now uses the V1 green enlarged marker and centered
  white check. The check stays upright for rotated chairs, authored corner radii
  and hit geometry remain stable, and pending requests retain the check.
- Flutter and JS both initialize explicit preselection, visibly release it, reject
  duplicate pending clicks, roll back the affected IDs on failure and respect
  unavailable / selectable:false seats. Status-only updates preserve local selection;
  explicit selected:false clears it. Layer-patch removal coverage now uses explicit
  deselection rather than an unrelated availability patch to erase ownership.
- Registered Minimalistický appearance + Původní palette. Default new classic ball
  uses the minimal helper; sparse document constructors retain prior semantics.
- Added validated physical table seating properties and one shared TableSeating
  policy for capacity, slots, incoming-chair sizing, reflow and spacing. Legacy
  default 40-unit / 52-pitch layouts retain capacity behavior. Both source halls
  specify their original 77.5-unit chairs and spacing. Oversized loose chairs now
  normalize to their target's seating profile; the attachment regression asserts
  the new matching-size behavior plus absence of collisions.
- Inspector exposes collapsed chair width/depth/clearance/spacing controls. Field
  labels are padded clear of the expansion header. Configuration is one undo and
  preserves IDs; impossible dimensions reject atomically.
- Core suite: 222 passed. Targeted Flutter suite: 30 passed. Final picker/settings
  subset after UI refinement: 7 passed. Final core selection/appearance subset
  after upright-check/radius refinement: 22 passed. Web suite: 12 passed, including
  initial-selection release/rejection/pending and nonselectable-seat coverage.
  Targeted analyzers clean. Final demo built and source manifest verified.
- Isolated browser: real plus click at source table 21 produced a seventh chair.
  Actual transferred V2 document shows all seven as 77.5 x 77.5. Inspected controls
  showing width/depth 77.5, clearance 11.25 and spacing 22.5.
- Real Flutter and web clicks both produced upright white checks on green enlarged
  markers; Flutter customer view has no editor outline. Web Clear selection removed
  the check and returned the selected count to zero. Inspected the new basic family
  card and Original palette in the global-style dialog.
- Screens under build/qa: chair-profile-added.png, chair-profile-settings-final.png,
  selection-parity-flutter.png, selection-parity-web.png, minimal-basic-palette.png,
  minimal-basic-family.png. Tests use simulated host callbacks; no production
  reservations, orders or backend data were changed.

### 2026-10-19 - Palette physical scale and insertion stacking

New couches, straight/curved rows and vehicle assemblies use the prevailing
physical chair size (77.5 x 77.5 in the scout reference), including subsequent
count changes. Vehicle outlines and aisle decoration scale with their seats;
bar dimensions follow the same document scale. New roots go above existing
layers on both controller insertion and canvas drop, with one undo transaction.
Thumbnail caches also refresh when the document seating profile changes.

Validated: 24 Flutter widget tests (palette drop, rows inspector, editor widgets,
appearance/drop), 35 affected core tests (rows, layers, transport and furniture),
12 web tests, targeted analyzer clean. Demo rebuilt and every manifest source
hash matched. Receipts: `build/qa/palette-seating-{verified,core,web}.log`,
`palette-seating-analyze.log`, `palette-seating-final-analyze.log` and
`palette-seating-demo.log`.

### 2026-10-19 - Stable table drag and physical couch minima

Reproduced a blocked table preview jumping from x=600 to its gesture origin
x=500. Constrained movement now keeps the last accepted preview and skips the
second chair reflow in controller acceptance. The shared surface also retains
pointer-down coordinates when drag recognition arrives beyond the pressed item.
A delayed-recognition regression fails on the former focal-point behavior.

Reproduced 77.5-unit couch cushions compressing to 32 x 24. Couch roots now retain
physical minimum width/depth in existing seating geometry fields. Resizing clamps
the body to those dimensions plus upholstery, while count changes keep IDs.

Passed: 31 targeted Flutter tests, 20 affected core tests, 12 web tests and
analyzers. The four regression tests also pass after removing timing probes.
Headless browser checks of the actual rebuilt scout hall confirmed fast table
movement and that an attempted couch squeeze retains full-size cushions.
Receipts: `build/qa/furniture-drag-verified.log`, `furniture-drag-core.log`,
`furniture-drag-web.log`, `furniture-drag-regression-final.log` and analyzer logs.
Visual receipts: `furniture-fast-drag-final.png`, `furniture-couch-minimum.png`.
Final demo source hashes matched the runtime manifest. Callback timings were
collected during diagnosis, but overlapping validation/JIT activity makes them
unsuitable for a comparative FPS claim.

### 2026-10-19 - Atomic palette insertion and localized placement feedback

Reproduced blocked drop publishing a helper fragment at the origin, producing
an unrelated canvas-overflow error. Also reproduced insertion of a tabletop over
another tabletop when its chairs happened to fit outside the obstruction.

Palette click/drop share the constrained transaction and cache the combined
fragment per gesture. Invalid hover never publishes the origin fragment; invalid
release rolls back the complete insertion with no undo entry. Re-entering free
space and starting another insertion both recover cleanly. Table-body collisions
now block constrained placement alongside chair collisions; decorative background
and labels remain nonblocking. The former edge test explicitly allowing table
collisions was updated to verify the new requested behavior and retained its
manual-chair wall-reflow assertions.

Passed 37 targeted Flutter cases including recovery, Czech feedback rendering,
English fallback, host overrides, dynamic capacity/lock messages and prior drag
regressions. Core run passed 221 cases with only the obsolete collision assertion;
after that assertion update all 12 edge-seating cases passed. Runtime core code
was unchanged between those runs. Targeted analyzers clean; 12 web cases passed.
Final rebuilt demo hashes match current source. Headless browser confirmed a
rejected click over an existing table keeps 72 seats and shows Czech feedback;
the next click on free floor succeeds at 78 seats with feedback cleared.
Receipts: `build/qa/insertion-recovery-{final,core,core-final,web}.log`, analyzer
logs, `insertion-rejected-czech.png`, `insertion-recovered.png` and demo build log.

### 2026-10-19 - Measured blocked-drag performance and single preview owner

`fvm dart tool/drag_overlap_benchmark.dart` measures the same 182-seat scout hall,
30 warmups plus 60 samples for blocked and free positions. Before: blocked median
20,960 us / p95 29,726 us; after: 553 us / p95 803 us. Free median stayed within
792-833 us. Both runs rejected all 60 blocked samples and accepted all 60 free
samples. This measures the core operation, not total UI frame time.

Tabletop collision now returns before perimeter generation/packing, sharing the
same spatial index with reflow when a tabletop fits. Flutter regression confirmed
that palette feedback and the canvas both painted the same dragged object. The
feedback now hides inside the canvas; invalid hover also removes the previous
valid inserted preview once, eliminating stale copies without repeated rebuilds.

Passed: 222 core tests, 16 targeted Flutter tests (including real palette drag,
feedback ownership, stale-preview removal, recovery and prior drag regressions),
12 web tests; affected runtime and benchmark analyzers clean. Final demo hashes
match source. Isolated headless browser exercised repeated blocked/free drags on
the actual scout hall: 54 rAF samples, median 16.7 ms / p95 17.6 ms / max 33.3 ms.
These are observed frame intervals on this workstation, not a cross-device FPS
promise. During blocked hover the count returned from 188 to 182 with no helper
left on the floor; free re-entry committed exactly one new table.

Receipts: `build/qa/drag-overlap-{baseline,after}.json`,
`drag-performance-{core-verified,flutter,web,analyze,benchmark-analyze,demo}.log`,
`drag-browser-frame-cadence.json`, `drag-single-preview.png`,
`drag-blocked-no-ghost.png`, `drag-recovered-single-table.png`.

### 2026-10-19 - Visible blocked preview and editor-equivalent SVG wheel zoom

Blocked palette hover keeps one translucent preview under the cursor, a theme
error outline and a prohibition icon with localized `Cannot place here` text.
The canvas contains no invalid helper; valid re-entry hides the overlay and uses
one canvas preview. Actual browser screenshot confirms Czech `Sem nelze umístit`.

Reproduced SVG wheel delta -100 producing width ratio 0.904837 (old 0.001
coefficient), versus the editor's expected exp(-100/200)=0.606531. SVG now uses
that same exponential distance, retaining existing limits and Shift pan. The new
browser test checks an off-center cursor anchor and reversible zoom. Actual built
demo ratio 0.60653064 with 0.13-pixel anchor error at its responsive viewport.

Passed 11 Flutter feedback/recovery/drop tests and all 13 web tests; off-center
anchor regression passed separately after strengthening its cursor position.
Affected runtime analyzers clean. Final demo source manifest matches all inputs.
Receipts: `build/qa/blocked-preview-tests.log`, `blocked-preview-analyze-final.log`,
`web-wheel-parity-verified.log`, `web-wheel-anchor-final.log`,
`blocked-preview-wheel-demo.log`, `web-wheel-demo-parity.json`;
visuals `blocked-preview-visible.png`, `blocked-preview-recovered.png`.

### 2026-10-19 - Visible polygons and stage-facing theatre template

Drawn polygons now use opaque #CBD5E1FF and path insertion raises the new subtree
above existing backgrounds. The existing polygon widget regression uses a z=900
white background and asserts effective fill, front ordering, undo and cancellation.
Actual editor screenshot: `build/qa/polygon-filled.png`.

Template family version 7 corrects theatre stalls/balcony to concave rows facing
the stage, preserving row bounds and 188 seats. Row labels follow the corrected
outer row positions. Box assemblies rotate inward around their true midpoint;
root transforms and negative arc parameters retain the direction in ordinary
count/spacing edits. A geometry test checks every seat's transformed front points
upward and inward, both curved generators remain negative, validation succeeds
and no physical collisions are introduced.

Targeted polygon and theatre tests passed; affected analyzer clean. Final demo
rebuilt with matching source hashes. Actual headless editor review of the freshly
selected theatre confirmed the corrected layout:
`build/qa/theatre-facing-corrected.png`. Logs: `polygon-fill-test.log`,
`theatre-facing-final-test.log`, `polygon-theatre-analyze.log`,
`polygon-theatre-demo-final.log`. Existing authored drafts are not rewritten;
select the theatre template again to use the corrected starting layout.

### Distinct appearance families and circular seats (2026-10-19)

Removed Modern/simple and Traditional hall/hall from the authoring gallery,
retaining Lounge and stored-document support. Added Round seating with a shared
circular body/hit contour. Targeted verification: 16 core style tests, 9 global
style widget tests, 13 web tests; targeted analyzer clean. Demo rebuilt and source
manifest matched. Isolated headless Flutter check confirmed the six family
previews and applied Round seating to the 72-seat Classic ball, including palette
previews. Evidence: `build/qa/round-family-dialog.png` and
`build/qa/round-family-selected.png`.

### Flutter/SVG paint parity (2026-10-19)

Reproduced Flutter zero-width hairlines with a real raster painter test;
reproduced hidden fit-view labels with canonical scene culling, and SVG
group-opacity differences with the actual public mounted viewer. Regressions
now pass: 18 Flutter tests, 19 core tests, 14 web tests; targeted analyzer clean.
The same conference document was painted at 960x720 / scale .4 by Flutter and
the built JS kernel/SVG viewer. All 136 canonical items and paths, outline
widths and 13 labels matched, with no scene issues. Visual captures retain
engine-specific antialiasing differences. Comparison artifact:
`build/qa/render-parity-review.html`; demo rebuilt with matching source manifest.

### Attached-chair facing and explicit rotation (2026-10-19)

Reproduced a manually displaced circular-table chair retaining a stale heading.
Core now resolves automatic facing in world matrices and persists it on moves.
Explicit rotation marks manualRotation and survives subsequent movement, JSON
round-trip and undo. Coverage includes rotated parents, detachment preserving
pose and controller actions. All 228 core tests and 22 targeted Flutter tests
passed; targeted analyzer clean. An earlier label-LOD assertion was updated to
the authored-label visibility contract established by the renderer parity fix.

All 14 existing web tests plus a new real-kernel SVG regression passed. The
new browser test checks automatic facing, explicit rotation and subsequent
movement in the mounted viewer. Local demo rebuilt; source manifest matches.

### Global chair gap and complete palette labels (2026-10-19)

Added a plan-style chair gap with a live specimen and existing/new-table
behavior. Coverage includes rect/circle/custom surfaces, manual positions and
rotations, locked assemblies, empty plans, JSON persistence, invalid/infeasible
input, palette default inheritance and single-command undo. All 231 core tests,
17 targeted style/seating/selection Flutter tests and 15 web tests passed.
Palette clipping was reproduced with real RenderParagraph glyph boxes extending
below the 28px label box at text scales 1 and 1.25. Tiles now reserve two complete
scaled lines and keep thumbnail space.

Palette fix validation: 19 targeted Flutter tests passed, including both real
paragraph-box regressions at scales 1 and 1.25; targeted analyzer clean.
The rebuilt demo was visually checked in an isolated headless browser;
`build/qa/palette-complete-labels.png` shows the complete Czech Arc row label.
Global-gap commit/default/undo is covered by the widget regression. Demo source
manifest matches current runtime sources.

### Focused numeric wheel editing (2026-10-19)

Shared wheel behavior passed three focused-field/form/bounds/scroll-ownership
widget regressions. The 12 global-style tests include real wheel gap updates
and one-step undo; existing editor widget tests passed. Festapp canonical Czech
session executed the new ticket-width wheel/undo case and the existing paper
settings/margin case (one collected test each), both passed. Targeted analyzers
were clean in both repos. Isolated built Flutter browser confirmed gap 12 -> 13
on wheel while retaining panel position; `build/qa/number-wheel-browser.png`.
Demo rebuilt with matching runtime source manifest.

### Zero-gap round table distribution (2026-10-19)

Reproduced an unobstructed 200-unit circular table with eight chairs at gap 0
falling back to 30-degree slots and leaving a 150-degree hole. Regressions now
cover 5-10 chairs at five diameters, visible round-lounge front contact, genuine
obstruction with bounded fallback deviation and restoration on returning to
free space. All 234 core tests, 18 focused Flutter tests and 15 web tests passed;
targeted analyzer clean. Built viewer visually checked with two eight-chair
tables at gaps 0 and 24, no scene issues. Evidence:
`build/qa/round-spacing-review.png`. Demo source manifest matches current code.

Chair controls: 235 core tests and 13 global-style widget tests passed; targeted
analyzer clean. Coverage includes physical dimension updates, persisted defaults,
locked profiles, live slider drafts without document mutations, one-step undo,
exact entry and wheel edits. The built headless Flutter demo was visually checked
for style-first ordering and all five sliders, including a real pointer drag with
no browser errors. Evidence: `build/qa/chair-styles-order.png` and
`build/qa/chair-sliders-review.png`.

Simplified chair controls: all 15 dialog tests passed, including a real double
click plus one undo, linked size, isolated count simulation, unchanged specimen
table geometry and visible capacity limits. Targeted analyzer clean.
Built demo visually checked in isolated headless Chrome with six chairs and
an over-capacity request, no browser errors. Evidence:
`build/qa/chair-simple-review.png`, `build/qa/chair-capacity-review.png`.

Elliptical chair dimensions: regression reproduced the round body's unchanged
20-unit radius after doubling width. Canonical body and lounge accent paths now
scale along each authored axis. New path regression and existing zero-gap/
distribution cases passed; the outdated circle-only style expectation was
updated to the ellipse equation and rotated major-axis picking. Core run passed
235 cases before that old assertion, then all 11 seat-style cases passed after
updating it. All 15 global-style widget tests passed; targeted analyzer clean.
Demo rebuilt with the shared geometry fix.

Appearance tuning now shares the chair slider/number/reset control for stroke
width (0.1 steps), corner radius (1) and opacity (0.01). All 16 dialog tests
passed, including fractional live-preview drafts without document edits, one
undo per completed adjustment and opacity reset by real double click. Targeted
analyzer clean. Demo rebuilt with the standardized controls.

Appearance slider resets resolve defaults from the canonical material family
for the currently selected object kind, instead of shared numeric fallbacks.
All 17 dialog tests passed, including real double-click resets for lounge table
radius 18, timber outline 1.2, and minimal chair outline 0/radius 8, each reversible
in one undo. Targeted analyzer clean.
