# Validation receipts and limits

Commands ran in the isolated source worktrees against owned disposable local
services only. No production release gates were invoked.

| Check | Result and scope |
| --- | --- |
| Package core `fvm dart test` | 236 passed on unchanged core, followed by one real public-wire parser test passing. |
| Package Flutter seams/picker lifecycle | 7 passed, then Escape activation regression passed. Independent archive consumer repeats public seams against actual archives. |
| Package `cd web && npm test` | Final 18 passed, including actual raw classic-asset loader, real public wire, atomic/pending/quantity, camera and dispose. |
| Architecture import gate | 253 production imports checked; no host/Supabase/private-src leakage. |
| Actual pub/npm archives | Separate core and Flutter archives, actual npm pack; external clean Flutter consumer, all14 templates and extracted offline browser example. Final output `build/qa/archive-final` in package worktree. See archive-result/browser/manifests there. |
| Host JS `node --test tests/components/blueprint*.test.js tests/forms/form_session.test.js` | Final 26 passed, including real archived viewer, raw standing offer, actual rendered ticket fields and required-spot validation. |
| Host JS `npm run build` | Passing Vite production build. Exact raw kernel asset is preserved. Final CSS-only build recorded separately. |
| Host canonical Czech session | Final frozen-source serial run: `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart`, 199 passed (including all9 host cases and3 UI cases). Runtime20s; compile/startup excluded. |
| SQL selected five-file batch | Final 5 selected / 5 passed as `supabase_admin` on owned DB59432. Initial postgres attempt could not replace test helper owned by supabase_admin, then corrected role succeeded; no application defect or production escalation. |
| SQL two-session races | 8 passed; deterministic barriers, final state and timeline documented in sql-evidence.md. |
| Deno font/preview tests | 21 passed. Real local Edge outline requests also passed twice (1.619s/1.512s,316 glyphs), without changing helper after earlier transient CPU cancellation. |
| Save performance | Valid5000 seats1.198s; valid20000 seats2.898s, with3,954,608B receipt. Exact measurements/limitations in SQL evidence. |
| Actual local UI | Astra Medium, ui-ux-pro-max, isolated headless agent-browser; evidence screenshots and per-row limitations under ui/. Does not equal54-row completion. |

## Failed or limited broader checks

An accidentally broad web-client run selected the full suite despite the intended
name filter placement: 462 passed / 6 failed. Three startup mocks lack
resolveScannerRoute and three scan tests require unavailable fake-indexeddb.
Those unrelated suites were not edited or claimed green; the targeted26 pass.

`shared_default_3_test.dart` cannot compile pre-existing scan_field_mappings_cases
references to undefined specificFieldMappings. Blueprint host cases were moved to
the required canonical shared_czech session, where all9 actually execute.
A wrong plain-name probe selected0 and was not counted as a pass.

One later concurrent Czech run stopped at43 tests with FlutterPlatform stream
shutdown errors while a debug server and archive Flutter build were also active.
The exact cause is not confirmed. The user then imposed a workstation-wide single
Flutter task limit and concurrency1; all subsequent Flutter work is serialized.
Earlier successful evidence is retained, and this aborted run is not counted.

The archive browser harness initially navigated to LICENSE with octet-stream MIME
and triggered a download. A blank same-origin HTML route corrected the harness;
the loader then ran from a fresh page without the demo's preloaded kernel.


Installed host npm files were compared byte-for-byte with the final actual npm
archive: zero differing files. The package kernel SHA256 is
`e8db58030c23be0d0fb253a1fa9a02c16205fea77453236d7690d6b5c58e6bf8`.
The final migration SHA256 is
`2c8ce0b73bd27746b1daf537f0c86651cdda64091cc2af6a48aa651340921708`.


Final Flutter build passed after the serial199-test run, with no other Flutter
process active: `fvm flutter build web --release --no-web-resources-cdn --target
test/browser/full_app_e2e.dart --dart-define-from-file=<private local defines>`.
Compilation266.3s, target pinned to the owned local backend. Build file hashes are
in flutter-build-manifest.json. This is an E2E-target compilation, not a tenant
production release or deployment. It was then served for actual browser QA by the
existing local SPA server, without starting a Flutter development task.


After final compiled UI exposed the omitted public occasion field, the public SQL
reader and forward migration were corrected without changing Flutter/JS sources.
The affected layout SQL suite passed1/1 on full owned backend59522, retaining the
public privacy assertion. Server readback after actual UI Save/reload confirmed
revision3, node label `Mixed table QA`, and all4 original seat->spot IDs unchanged
(`admin-save-readback.json`).

## Continuation validation (newer than the earlier frozen handoff)

The older “final” counts above identify the first handoff inputs; they do not
certify subsequent implementation changes. Package JS now passes20/20 actual
collected tests, including real bounded raster decode/hash/dimension/abort checks
and localized picker announcements (`/tmp/blueprint-b-package-js-final.log`).
Deno font/preview tests pass22/22 including setup-draft authorization and request
shape validation. Verified image IO/110 Worker tests and local setup SQL/font
proofs are recorded in image-evidence.md and local-business-runtime.md.
The newer canonical Czech session, final consumer archives and host build must
run serially after actual UI validation and source freeze.

Continuation host JS:37/37 collected tests passed. The first batch exposed empty
resources becoming `{assets:{}}` without a protocol; the generic asset resolver
now preserves empty resources unchanged. Its actual browser regression passed3/3
and the host was reinstalled from the newly packed tarball (npm's same-version
file cache needed explicit tarball installation). Vite was restarted with --force.

Continuation SQL on59522: layout, finance, copy and authorization passed in the
normal runner. Capacity/resource initially correctly rejected the old test's
1000-unit metrics against an already genuine Edge-generated font; its isolated
rollback merge fixture now resets only its transaction-local outline and also
asserts changed-metric rejection, then passes1/1. Image resources use psql because
the existing node runner does not interpret `\\ir`; the actual image suite passed
with real ready assets. Setup drafts, availability/waves and named-slot copy each
passed through psql with the real synthetic form. This is9 actual SQL suites,
without claiming the initial mixed runner batch passed. Eight existing real
connection races also passed on the full owned backend; the harness now verifies
both exact project marker and its allowed owned port before running.

Final C05 follow-up uses only existing spot holds and PIC quantities to reject
indirect shared-context oversubscription. Its dedicated actual rollback suite and
the public wave/offer/atomic-unit regression passed. The final concurrency harness
then passed9/9 real two-connection scenarios, adding distinct buyers competing
for the last product maximum; the rejected second spot remains unheld.

Actual browser upload uncovered two local-transport defects: Flutter callbacks do
not guarantee the bootstrap HTTP-client Zone, and the local bridge duplicated
CORS headers with different case on POST responses. The E2E target now routes
BrowserClient fetch at the isolated browser boundary (optional init retained),
and the bridge merges response headers case-insensitively. Production client URL
validation/HTTP transport is unchanged. Actual PNG and SVG upload/render/save/full
reload then passed; the same processed SVG rendered in the real JS mobile picker.

## Canonical cutover final inputs (supersedes historical counts above)

- All49 real-source layouts: offline conversion PASS,4516 original physical IDs,
  labels and products preserved. Actual SQL migration+same-command replay PASS49/49
  on synthetic local owner/spot IDs, including demo; full rollback. Receipt:
  `checks/all-existing-reviewed-conversion.json` in the private local environment.
- Real two-connection SQL races:9/9 PASS after final private aggregate/receipt
  extraction (`/tmp/blueprint-b-races-cutover-final.log`).
- Canonical Czech session:222 tests collected,221 passed initially; one wizard
  save fixture incorrectly used an empty document that auto-opens the template
  gallery. Test-only fixture corrected to an existing draft; affected test1/1
  PASS. No runtime source changed. Logs: `blueprint-b-czech-cutover-final.log`
  and `blueprint-b-wizard-retry-final.log` under `/tmp/`.
- Targeted Dart analysis: zero errors,2 warnings and42 informational style/deprecation
  findings across the selected Blueprint/form/setup/E2E files. Warnings concern a
  redundant non-null assertion and the test harness SDK API against broad project
  constraints; pinned workstation SDK compiles these sources.
- Package JavaScript20/20 PASS; architecture import gate PASS255 production imports.
- Host affected Blueprint/security tests28 PASS,9 intentionally skipped,0 failures.
  Vite production build PASS975ms. The unrelated broad npm suite still has the same
  missing fake-indexeddb scan fixtures and startup mocks recorded above; it is not
  claimed green.
- All49 Basic visual comparisons PASS,23 default activity cards, year filters and
  375px no-overflow verified. No external gallery requests.

Final archive and compiled-UI receipts are recorded below after their gates finish.

Final compiled host build PASS65.3s, served on owned59600 for actual release-UI
inspection. Independent archives PASS in package
`build/qa/archive-canonical-20261019`:62 selected core files,172 selected Flutter
files, actual npm pack,4 clean-consumer tests,14 actual npm template scenes,
packed raster verification, pending lifecycle and extracted Flutter example boot.
Demo artifact smoke2/2 PASS. All consumer browser requests stayed local.

Packed browser diagnostics (same renderer/browser, no hard timing threshold):
500 seats mount24.1ms/one-state patch8.4ms;5000 seats mount240.3ms/patch15.1ms.
Both retain untouched scene-item identity, document and camera, with zero scene
issues. Final host vendor archive was force-installed offline and19 installed
files matched archive bytes exactly. Affected host tests again28 PASS/9 skipped;
final Vite build713ms, unchanged raw kernel hash recorded in web-build-manifest.

Final S09 SQL-only correction: authorized admin projection now includes the
existing private order note under `data.note_hidden`, with the dedicated order
column authoritative. Actual local `admin_private_order_note_test` PASS checks
both authorized rendering data and anonymous public/admin denial. Public safe
projection unchanged; Flutter/JS source and their passing builds unaffected.

## User-rejected visual evidence - supersedes prior Basic PASS

The user rejected rasterized tables/architecture on27/29/32/33/59 and the used-seat
cross/tooltip differences on47. Previous Basic all49 PASS is withdrawn. Native
structural reconstruction, attachment/business-group regression, state-marker and
hover-tooltip proof and all49 matched-camera visual review are pending. Earlier
chair identity/financial/SQL proofs remain valid for those recorded inputs only.

## Native reconstruction final gate (replaces rejected bitmap candidate)

- All49 final documents PASS deterministic conversion, exact4516 source spot
  IDs/products/labels/world positions,18 native halls,464 real tables,0 raster
  backgrounds and5 empty plans. Every document compiles a real scene with the
  genuine Futura resources and zero issues. Effective table appearance is
  asserted to use existing native Basic V1 white/black styling.
- Source artwork extraction preserves semantic geometry. Caption text is native;
  imported irregular sawteeth normalize through existing public zigzagLine.
  Ambiguous legacy commercial groups retain original independent chairs rather
  than invented physical attachments; reviewNotes name those cases.
- Final reviewed SQL migration+receipt replay49/49 PASS with full rollback.
  Synthetic local editor fixture230 was retained for actual drag/hover evidence,
  admitted through canonical link/form/occasion owners and refreshed to final
  native document via canonical save, revision2. ProductionApplied=false.
- Package core appearance10/10 PASS including used-seat marker suppression.
  Host canonical Czech223/223 PASS; subsequent native inspector-only change
  passed its actual collected targeted test1/1. Final runtime build60.0s PASS;
  later offline converter-only edits are covered by the separate49-document gate.
- Package JS20/20 PASS; affected host JS28 PASS/9 intentional skips, build1.25s.
  Independent native archives PASS in build/qa/archive-native-canonical-20261019:
  separate core/Flutter/npm, clean consumer4tests,14 browser scenes, real raster
  loader/lifecycle, actual extracted offline Flutter example.

Final user style corrections passed the49-document real-font scene gate: shared
Basic V1 table cornerRadius8; original hall palette is set once in document
appearance (pale green/gray and explicit purple/white exceptions), retaining
source text contrast. All17 dashed architectural boundaries use the existing
public dash geometry seam; no renderer fork or new package build was needed.
Actual native table drag moves its caption and8 original chairs while neighbors
remain fixed; Undo restores it. Actual Flutter and JS hover retain name/product/
formatted price. Used seats retain purple fill with no occupied cross.

## Visible hover and final path refinements

SVG title nodes did not reliably display a tooltip. The public JS viewer now
shows a real safe text tooltip on actual pointer hover, including unavailable
seats; leave/pan/update/Escape/dispose remove it. The actual Chromium regression
checks visibility, price refresh, no HTML injection, viewport bounds and cleanup.
Package JS21/21 PASS, affected host JS16/16 PASS, final Vite807ms. Actual packed
JS consumer14-template/raster/lifecycle/browser gate PASS using unchanged
verified Flutter archive; final npm archive is tooltip-native-20261019.

All49 new scenes validate with genuine font resources and stable physical
identities. Exact source zigzag vertices/endpoints are kept as editable native
polylines, replacing the earlier normalized half-tooth ends. All6 raster-source
arrows are existing native arrow objects. Actual card/detail pointer screenshots
and latest49-plan gallery checks pass. No backend/Flutter runtime source changed,
no services remain running, and production is unchanged.
