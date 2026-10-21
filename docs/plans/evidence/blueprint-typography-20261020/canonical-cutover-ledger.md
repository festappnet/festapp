# Canonical rendering cutover ledger

Local UX follow-up r38: reproduced stale and late native-font errors after changing fonts, missing retry, and blank Text tool without prepared Aa geometry (four red owners). Native font keys now include the actual face mapping, errors track currently rendered faces only, and active load errors expose a retry. Non-rendered couch/bar labels no longer start native text loads. The palette Text tool uses a theme-colored schematic Aa; authored text and canonical glyph contracts stay unchanged. Fifteen targeted owners pass, including canonical viewer paths and inline editing. Original unsaved font choice was unavailable; isolated browser session read the persisted local fixture and was closed. Receipt: [ux-followup-r38.json](ux-followup-r38.json).


Local UX follow-up r37: host operation summary moves into a canvas-anchored floating bottom panel. Order count and product amounts update from current selected seats, separated by currency; server order analysis stays authoritative. Top toolbar no longer carries operation actions or duplicated host dirty text. Inspector actions use consistent outlined geometry and aligned widths. New row labels use row number and spreadsheet letters, continuous across blocks; resize updates automatic labels only. Host commercial reconciliation preserves generated row labels rather than substituting group-wide numeric titles. Four targeted row owners pass. Receipt: [ux-followup-r37.json](ux-followup-r37.json).


Local UX follow-up r36: exact pointer-drop regressions reproduced failed Ctrl+Z for Text and Seat. Non-text drops now focus the canvas; clean inline insertion commits then undoes the single creation transaction, retaining redo and native dirty-text undo. Default green returns to V1 #267329. Seat context action selects physical children; row-group split preserves IDs/world geometry and removes obsolete attachments in one undoable edit. Shared editor modal entry points consistently install route-scoped Escape dismissal. Footer info contains concrete controls for the current mode and a collapsed state legend. Nineteen targeted package owners pass. Receipt: [ux-followup-r36.json](ux-followup-r36.json).


Local UX follow-up r35: viewing canvas triple-click and selected-object double-click request the existing authorized editing mode. The host transfers selection to the geometry inspector and disables this shortcut during order/swap and for users lacking editing rights. No document mutation or history entry. Receipt: [ux-followup-r35.json](ux-followup-r35.json).


Local UX follow-up r34: full-text reservation actions wrap when necessary. Standing detail shows live availability and explicit sales capacity, saved through the existing area capacity command with document history, zero capacity, undo after save and frozen-save metadata. Astra Medium consultation informed adaptive workspace colors while authored document fills remain intact. Dark schematic line previews use brighter minimum-width strokes; material choices show canonical families and unstyled seats use shared saturated green. Cinema couches face the screen with stronger backrests; entrance text and chevrons are removed. Targeted owners, clean archived consumers and all 15 template scenes passed. Receipt: [ux-followup-r34.json](ux-followup-r34.json).


Local UX follow-up r33: layer rows and commercial table/area rows highlight canvas objects on real pointer hover without selection/history changes. The reservation toolbar blocks/unblocks eligible selected seats in one draft history entry, expands atomic sofa units and rejects protected members; compact secondary actions remain visible on narrower toolbars. Removed incidental host/font preparation progress bars and animated order submission/loading indicators; authoritative analysis finishes before opening the order dialog. Required customer and attendee data fields come from the same active form used by confirmation, reuse shared form widgets/validators and send canonical field payloads. Confirmation rejects a changed form and strips client form/ticket overrides. Package layer-hover owner passes; actual required-fields/retry/protected-seat owners pass, plus final workspace hover/block/temporary-release/cancellation and atomic-block owners. Four local SQL form-contract assertions pass and roll back fixture changes. Receipt: [ux-followup-r33.json](ux-followup-r33.json).

Local UX follow-up r32: ticket grid and plan cancellation share optional partial/full-order email follow-ups. Last-ticket cancellation still changes the order to cancelled in the existing receipted command, but explicitly suppresses automatic email for this caller; other bulk callers retain their default notification policy. Temporary, unticketed reservations have a separate order-editor-only release command with same-blueprint validation, atomic-unit expansion, ordered-seat rejection and stable replay receipts. Cinema chairs have a straight screen-facing back and rounded front silhouette; applying the cinema family uses oriented upholstered seats. Local rollback SQL checks cover rights, whole-unit release, newer-hold replay safety, ordered-seat rejection and full cancellation without automatic notification. Two actual UI owners, four transport owners and template shape/capacity validation pass. The broad default session has an unrelated pre-existing scan_field_mappings_cases.dart compile failure; transport owners were run directly instead. No real email sent, and all SQL fixture mutations rolled back. Receipt: [ux-followup-r32.json](ux-followup-r32.json).

Local UX follow-up r31: selecting an attached seat now shows its own table connector without sibling links; table selection retains all connected-seat links. The Text section offers a contextual, counted transfer to editable peers of the same kind. It copies resolved typography/color/alignment, replaces target label overrides, skips locked objects/assemblies and preserves geometry, authored labels, child styles and document defaults. The operation uses one document history entry, with a compact Undo notification. Nine targeted owners pass, including a displaced chair and actual inspector transfer/undo. Receipt: [ux-followup-r31.json](ux-followup-r31.json).

Local UX follow-up r30: image/vector resize preserves aspect ratio by default, with Shift for free resizing. Committed numeric inspector fields retain focus after Enter and route undo/redo to document history; dirty fields keep native text undo. The cinema family uses existing canonical material values, and “Galaxy cinema” adds seven rows, 84 seats and four atomic two-seat couches on a starry dark canvas. Canonical bundled text resources include the new template in English and Czech. Two gesture/history owners and two shared host editor owners pass; archive consumer and all 15 npm scenes pass. Served Czech Common.cancel/Common.storno resolve to “Zrušit”. Receipt: [ux-followup-r30.json](ux-followup-r30.json).

Local UX follow-up r29: quick appearance strips own persistent horizontal scrollbars. Live material/font routes have transparent barriers. Blueprint opts into the shared font picker’s reversible hover/keyboard-preview seam; font changes use existing preparation metadata within a temporary controller gesture, exit/Escape/dismiss/session replacement cancels, click uses one permanent selection transaction. Default Ticket font picker behavior remains opt-out. Inspector sections use compact 44px headers, no expanded borders and no redundant gap before geometry. Attached manual chairs expose “Restore automatic position” in inspector and context menu; the existing setTableSeatPlacement automatic intent reflows while retaining identities, protection and undo. Twelve package owners pass (including restore/undo), plus four final host/shared font owners (default picker preview, host preview cancellation/default promotion, setup editor integration, actual route hover/Escape/click). No interactive browser walkthrough. Receipt: [ux-followup-r29.json](ux-followup-r29.json).

Local UX follow-up r28: reservation toolbar hides redundant Select/Pan controls while existing tap selection and drag panning remain. Group rename is an icon beside its title, with the trailing rename action removed. Single whole-table selection no longer repeats the bulk product action. Protected seat details omit inheritance prose, repeated warnings and disabled assignment/blocking controls; group protection notices use compact counts. Czech Common cancel/dismiss labels are “Zrušit”, with wording recorded in CLAUDE.md. Starting an order seeds only eligible available selected seats, expanding atomic units and rejecting partial unavailable units. Starting a swap seeds at most two selected eligible seats; larger selections do not arbitrarily choose a pair. Existing confirmation/server execution remains unchanged. Three targeted UI owners pass across final owning runs, including inherited order selection, swap pair/oversized selection and draft preservation. Receipt: [ux-followup-r28.json](ux-followup-r28.json).

Local UX follow-up r27: local Blueprint themes use 6px outlined/segmented control corners; image and SVG imports share one graphic picker with the existing combined extension allowlist. Template entry now includes three cached miniature scene previews. Generic numeric property fields and font/chair slider number fields use the shared focused-wheel owner and their normal validation/commit paths. Copy disappearance reproduced with real pointer copy followed by keyboard focus loss: previous canvas focus callback canceled the entire gesture and removed the new subtree. Removed incidental focus-loss rollback; pointer cancel and Escape remain authoritative. Blocked-to-valid movement, focus transfer, copy identity and release remain intact. Twenty-six targeted package owners passed, including the real-pointer regression. Receipt: [ux-followup-r27.json](ux-followup-r27.json).

Local UX follow-up r26: explicit high-contrast segmented reservation/edit modes; host-provided read-only library seam places the commercial table list on the left, while a persistent right panel groups selected seats by commercial owner. Canvas seat selection highlights owning table rows and only reveals the inner list scroll. Whole-group and seat product/price assignments retain existing draft/save/protected guards. Commercial detail modal removed; catalog product choice remains its existing selector. Selected reservations expose ticket cancellation with the shared selection confirmation and dedicated storno_tickets_client_sync_v1 command. Rights, session and current ticket associations are rechecked after confirmation. Existing partial-order email follow-up extracted into one shared helper used by TicketsTab and Blueprint; full-order email remains server-owned. Widget tests cover grouped seats/row highlights/no detail modal/cancellation dismissal/no order-right action, existing mode/draft/bulk flow and inner-scroll behavior. Dedicated ticket command accepted/rejected owners pass. No live reservation cancellation or backend writes performed. Receipt: [ux-followup-r26.json](ux-followup-r26.json).

Local UX follow-up r25: rejected translations show red translucent target hulls at the attempted pointer position without mutating the last valid document. Successful movement/release/cancel clears the transient overlay. Duplication highlights collision footprints only within the copied subtree, using existing placement issues; those warnings now have a translucent red fill. Sixteen targeted furniture drag/copy/locale owners passed, including Ctrl/Cmd atomic copy and blocked drag last-valid/undo checks. Receipt: [ux-followup-r25.json](ux-followup-r25.json).

Local UX follow-up r24: plan style opens as a compact nonmodal right inspector page, keeping the canvas accessible. Two-column family previews and palette swatches are separated from collapsed floor/details. Hover uses reversible controller gesture previews, exit/Escape restores and click commits one undo. Both editor style entry points use this page. Table round label is Czech “Kulatý”; add-seat disables at table or document capacity. Font-default promotion is hidden until the user explicitly changes the font in that scope, then uses a shorter, spaced action. Targeted owning tests and final archive/build evidence are recorded in [ux-followup-r24.json](ux-followup-r24.json). No production/backend writes or interactive browser walkthrough.

Local UX follow-up r23 incorporates r22 selection emphasis. Templates are pinned above Objects in the left library; Plan style is pinned above the right inspector. The shared host font picker can promote its selected family to the document label default using the existing metadata/preparation owner; an actual widget test verifies default change and undo. New seat groups (including empty tables) receive a priced seat-product suggestion, preferring the last explicit choice and then existing usage/latest catalog entry. Existing bindings are not silently rewritten. Explicit whole-table product selection opts into replacing free-seat exceptions in one draft/undo transaction; the generic default-only API retains its original preservation semantics. Selection dialog now states assignment persists with plan Save; catalog mutation notice stays in catalog editing. Targeted checks passed: 5 package panel/mode owners, 19 host commercial owners including suggestion/draft/undo and protected replacement, plus the actual default-font UI owner. No production/backend writes or interactive browser walkthrough. Receipts: [ux-followup-r23.json](ux-followup-r23.json), [ux-followup-r22.json](ux-followup-r22.json).

Local UX follow-up r22: decoupled strong selection outlines from commercial check markers. Native seat and object selections now use the existing constant-screen-width 3px primary outline over a 6px white contrast halo plus subtle selection tint, including outline-only administration/swap selection. State glyphs and commercial markers retain their existing semantics. Existing chair/table/group/handle selection owners: 11 passed. No interactive full-app browser walkthrough. Receipt: [ux-followup-r22.json](ux-followup-r22.json).

Local UX follow-up r21: Snap/Grid are adjacent, canvas settings are pinned before save actions, and saved-state text has horizontal spacing. Footer reduced to 24px content plus 2px vertical padding with a matching host help affordance. Alignment/distribution actions use labeled icon tooltips. Double-click respects an already selected group and the logical selection target, retaining Alt child selection. Material/chair styles use a right-aligned live-preview chooser: hover/tap previews within one controller gesture, Apply commits once, Cancel/Escape/dismiss restores the baseline. Font/chair sliders reset by double-click through canonical default/inheritance owners. Repetitive inheritance captions are removed; reset affordances remain. Text is an initially expanded collapsible section with consistent weighted headings. Ordinary field apply checkmarks are removed; Enter/blur commits remain. Palette card outlines/labels and chair/round-table preview sizes are stronger; canonical scene colors/default declarations were not rewritten by this visual refinement. Final owning checks passed across targeted runs (30 unique owners); earlier failed compilation/gesture-timer attempts are retained. No interactive full-app walkthrough. Receipt: [ux-followup-r21.json](ux-followup-r21.json).

Local lifecycle follow-up 2026-10-20: host asset load, bitmap upload, view transition
and host/setup-demo save now contribute resources to the current controller map.
Late loads reject replaced/deleted manifests and stale sessions; canceled uploads
cannot insert nodes. View transition finishes native composing/focus plus a frame
before capturing the document, shares one Future/busy state, rejects stale work
and retains edit/retry on error. Frozen save preparation remains independent.
Snapshot-only seat picker/setup callbacks and synchronous editor setters retained.
No vendor, SQL, protocol, build, browser or production changes.

Verification: first owning session batch selected all eight blueprint suites and
found 15 fixture/UI failures. Canonical asset refs, native font input fixtures,
decode waits and stale toolbar/library/scroll test interactions corrected without
weakening functional assertions. Latest passing evidence: 80 tests total, including
UI 19/19 and upload 6/6 on focused reruns; other passing suites unchanged since
first batch. No claim of a second full passing batch. Targeted analyzer: no errors
or warnings, 33 style infos; final changed UI/upload tests analyzer: two infos,
no errors/warnings. Synthetic composing input does not prove physical platform IME.
Dirty worktree retained; no commit/push/deploy. Exact per-run results and final
source hashes: [lifecycle-followup-20261020.json](lifecycle-followup-20261020.json).

Local UX follow-up r20: moved plan style/templates and host image/SVG/background import actions into the shared left library. Removed the separate global font shortcut (fonts stay in canonical plan/object appearance) and pointer-mode Resize/Rotate buttons; resize/rotation handles remain. Host legend/help now occupies the trailing footer slot while hints remain centered. Added actual scene previews to material/chair-style options. Extracted the existing gesture slider into one shared LayoutNumberSliderControl, with a thin font adapter and full-width track/number field, small 6px thumb, 2px track; chair dimensions/gaps use canonical configureTableSeating previews with one undo per gesture. Targeted package owners: 21 passed, including chair slider identity/undo, font gestures, mode switching and named-style workflow. Import pickers use explicit SVG-only versus bitmap extension filters without changing upload owners. No interactive full-app browser walkthrough repeated. Receipt: [ux-followup-r20.json](ux-followup-r20.json).

Local UX follow-up r19: centered footer hints, including wrapped lines, and added 12px top/8px bottom content padding to object geometry, chair layout and advanced appearance expansion sections so floating field labels do not meet the expansion clipping edge. The single toolbar introduced in r18 remains in both modes. No new tests or interactive browser walkthrough for these narrow visual changes; distribution/compilation gate retained. Receipt: [ux-followup-r19.json](ux-followup-r19.json).

Local UX follow-up r18: pointer tools now share the existing host/editor toolbar, after the mode prefix and before other actions. Removed the separate pointer-only toolbar and its divider in both viewing and editing modes. The existing horizontal overflow and pinned trailing save actions remain the single toolbar contract. Two targeted widget owners passed at widths 600 and 1280, confirming pointer tools belong to the main toolbar and retain their positions across mode changes. No interactive browser walkthrough repeated. Receipt: [ux-followup-r18.json](ux-followup-r18.json).

Local UX follow-up r17: restored the existing shared font-size slider through a scoped canonical document update callback, preserving one gesture/one undo. Actual-face B/I gating remains authoritative; missing cuts now have visible explanation, and unsupported Blueprint underline is hidden without changing the Ticket default. The inspector includes the six existing material families in a horizontal strip. Its overflow menu saves the current appearance as a named canonical empty-node preset; saved styles are offered immediately, can be renamed/deleted, persist in the plan and retain undo. No schema/SQL migration or second style storage owner was added. Targeted checks: 23 passed plus the added create/offer/rename/delete/undo workflow owner passed. The focused-number wheel owner that failed on r16 now passes with the restored slider. Distribution gate passed (exact archives, clean consumer, 14 npm scenes and archived Flutter boot). No interactive full-app browser walkthrough was repeated. Receipt: [ux-followup-r17.json](ux-followup-r17.json).

Local UX follow-up r16: Astra Medium reviewed the existing controls with the ux-designer skill. The global scope selector now has an explicit label, filled outline and 24px spacing before subsequent fields. The object inspector starts with Name, followed by table shape/seat count or type-specific essentials, then appearance/font. Position/size, chair layout and advanced appearance are collapsed independently. Open paths retain primary stroke controls. Targeted widget run: 24/25 passed, including new scope-spacing and inspector-priority checks; the existing focused-number wheel test still expects panel scroll but observes no offset change. Its model/history nonmutation assertions were not reached; no passing claim is made for that test. The test was retained unchanged. No interactive browser walkthrough was repeated. Receipt: [ux-followup-r16.json](ux-followup-r16.json).

Current follow-up r15 supersedes the r10 UX note below. The editor uses cached native font paragraphs during edits; save and viewing still use canonical prepared vectors. Shared Ticket/Blueprint controls, square style cards, right-aligned style dialog, independent floor choice, rotation handle positioning, Czech inspector captions and shared Escape handling are implemented. The r14 package archive/consumer gate passed. Host checks passed for 42 owners across the suite and the corrected palette owner run (the initial palette assertion failure remains recorded). Package final checks passed: 12 shared/native/style owners and 3 final Czech/style owners. Actual isolated browser checks on r13/r14 confirmed continuous table resizing, two native font requests and zero layout-text requests during edits, Czech controls and Escape dismissal. No QA document was saved.

The r15 host-only change clips dialog body painting at its boundary so scrolling content cannot paint over the fixed header. No further browser check was run, as explicitly requested by the user. Current build/source receipt: [ux-followup-r15.json](ux-followup-r15.json). Earlier receipts and the table below describe their historical gates, not repeated checks on r15.

Local UX follow-up r10: native selection uses bounds; continuous custom-table edge dragging retains its pointer; color controls show swatches; Czech style controls and six quick material families restored with separate palettes; style dialog has a top-right close button and Escape. Targeted widget checks: 16 passed. Actual archive consumer/example and locally served application build passed. Authenticated browser confirmed the quick dialog and Escape. Current source/build receipt: [ux-followup-r10.json](ux-followup-r10.json). Prior r9 receipts below remain historical and are not claims about the updated source.

Current local state, 2026-10-20. The original execution plan remains authoritative.
The local implementation and original acceptance are complete. The requested
subsequent architecture review found and fixed obsolete text-batch dispatch. Production migrations, conversion,
publication and pushes have not been performed.

Canonical owner: document 2 authoring source -> validated core scene -> Flutter
painter / SVG consumer. Whole-text preparation owns immutable positioned paths;
private SVG source is retained for editing and stripped from public projections.
The same BlueprintPlanEditor is used in setup and existing occasions. Commercial
permissions, stable spot identities, revisioned commits and live history guards
remain in the Festapp host. Legacy parsing exists only at the explicit offline
import boundary; it is not a second runtime renderer.

| Boundary | Current evidence |
| --- | --- |
| Core and legacy import | 259 core tests retained; final affected core/import owners 33 passed |
| Flutter editor | Full current wrapper suite: 260 passed, one opt-in raster skip |
| Native/browser text quality | 576 actual-CSS configurations across 12 sheets passed; 10/12/16/24px, DPR1/2/3, zoom0.5/1/2/4, rotation0/30/90, four actual Roboto cuts |
| SQL/Dart/distributed JS | Four fresh complete save/read/admin/public/setup/copy scenes match exactly |
| Native/general SVG raster | 144 exact hard-ink bounds; 140 no nonedge RGB difference. Four gradient cases retain strict diagnostic failures; bounded one-channel review is recorded separately in raster-review.json |
| Distributions | Final candidate r9 passed exact pub/npm selection, clean consumer, 14 npm templates and archived Flutter browser boot. Previous byte-identical Flutter build reused; only distributed archive-check shell tooling changed |
| Host dependencies | Repository-relative vendored pub-selected wrapper0.3.0/core0.2.0; npm0.3.0 immutable archive with lock. All installed npm files match r9. No absolute checkout override |
| Host integration tests | 10 UI +17 business +3 setup draft +11 text/assets/upload owners passed; 21 JavaScript host tests and27 package browser tests passed |
| Private migration | 49/49 documents,4516 stable spots,230 unassigned,18 halls/464 tables,5 empty; exact source hashes retained, no production writes |
| Actual setup fonts | Four native immutable faces verified through the owned local Worker/R2/Edge path; revisioned draft preparation/save/read passed, draft removed |
| Performance | Scene-cache VM p95:5000 seats3.49ms,maximum20000 seats14.659ms, exact scenes. Browser5000 seats16.8ms p95 with0/120 frames over20ms. Maximum20000-seat SVG remains slow at133.4ms p95; no60fps claim |
| Actual full-app build | Release E2E build passed on final vendored Dart inputs. Real full-app SVG/PNG/JPEG import, transform, copy, save/reopen, synthetic browser IME and actual Roboto B+I passed after the backend was recovered |

## Completed application and architecture acceptance

The user-authorized Colima restart recovered the disposable backend. Its exact
project marker, PostgreSQL readiness and REST200 were verified; fixtures and
saved IDs were retained. No other project's data was modified.

Actual admin saves reached revision7 with five converted SVG objects, PNG and
JPEG objects, and NFD Czech text with ligatures/currency symbols in actual
Roboto bold-italic. The SVG text import used the same whole-text service.
Malformed script SVG was rejected with no dirty checkpoint. Original physical
nodes were unchanged. Save/close/reopen and object copies retained source;
public RPC stripped original SVG, and the actual public selector rendered
60 SVG groups and both verified embedded bitmaps without render errors.
Auth used a real local session seeded through the supported storage key; UI
login is not claimed. Only the task-owned headless native file chooser was
intercepted. These boundaries do not substitute for rendering or persistence.

Only after this original acceptance completed, the fresh architecture review
identified unnecessary dispatch of queued obsolete text batches. The written
plan was immediately implemented: UI preparation cancels between batches;
captured saves continue through the same preparation owner. Five owning tests
passed, including the33-paragraph/two-batch cancellation/save distinction.
Targeted analysis has no errors or warnings (16 nonfatal style infos).

The maximum-size SVG frame-time limit remains material:20000 seats133.4ms p95
in this headless environment.5000 seats16.8ms p95, zero frames over20ms. No60fps
maximum-size claim is made. Raw strict raster/centroid diagnostics are retained
unchanged; the independent bounded quality review explains the four one-channel
gradient exceptions. No production migration, conversion, push or deployment
was performed.

Machine receipts and exact source/artifact hashes:
[progress-20261020-local-gates.json](progress-20261020-local-gates.json),
[final-inputs.json](final-inputs.json),
[full-app-journey.json](full-app-journey.json), [raster-review.json](raster-review.json).
Architecture plan:
[post-cutover review](../../blueprint-post-cutover-architecture-review-2026-10-20.md).
Older chronology is historical evidence, not the current status.
