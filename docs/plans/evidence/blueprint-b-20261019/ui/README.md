> Final native review: all49 layouts render without raster backgrounds;464 editable tables,17 dashed boundaries and4516 stable chairs. Actual physical-table drag moved its caption and8 original chairs; undo restored them. The rejected bitmap comparison is superseded by `preview/blueprints-native-review.html`. See [native Basic evidence](basic-review.md).

# Blueprint B host UI evidence

Owner: Astra Medium. Workspace: `/Users/miakh/source/festapp-blueprint-b-20261019`.
No production operations, original-checkout edits, commits or publication.

## Implemented host paths

- `BlueprintLayoutHost` composes the public `VenueLayoutEditor`, host operation modes,
  product inspector, shared action bar, server swap preview and save-conflict recovery.
- Product selection reuses the catalog/editor dialogs; catalog writes are immediate,
  clearly distinguished from layout drafts, and guarded while pending.
- Order dialog uses existing analysis/create command owners, retryable analysis and
  submit errors, contact retention, authoritative total/currency and pending close guard.
- Flutter public picker uses `VenueLayoutPicker`, real typed `select_spot` result,
  atomically expanded seat units, latest session secret and existing form quantity flow.
- JS selector uses the actual archived `@festapp/venue-layout` kernel/viewer with the
  host session adapter; no local geometry or gesture implementation.
- Font choices reuse TicketFontCatalog, FontFamilyPicker and the host font provider.
- New localized text is in existing BlueprintStrings and cs/en catalogs. Package
  locale delegate is registered in the app root.

## Validation performed

- Targeted Dart analyzer on new/changed UI: no errors. Existing FormPage mutable-field
  warning and legacy style/deprecation info diagnostics remain.
- Final serial canonical shared_czech session: 199 passed, including the three Blueprint V2
  UI scenarios and server-authoritative total/currency fixtures (root-coordinated run, concurrency1).
- Operation-mode widget scenario exercises actual host/package callbacks, Escape,
  mode reset and preservation of a geometry draft. Test role fixture corrected to
  use the real occasion-editor permission, rather than assuming admin implies it.
- `node --test tests/components/blueprint_escape.test.js tests/components/blueprint_selector_v2.test.js`: 3 passed using the
  actual installed archived JS kernel/viewer and JSDOM (SVG CTM stub only). It checks
  retry after load failure, actual mount, disposal and focus restoration. It found
  and fixed a mount failure incorrectly enabling Continue.

## UI/UX skill application

Read `/Users/miakh/.codex/skills/ui-ux-pro-max/SKILL.md`, its pre-delivery checklist,
accessibility reference and verified searches for Flutter responsive layout plus
bulk/confirmation/feedback guidance. Retained existing canvas style and semantic
colors, used shared dialogs, scrollable narrow layouts, explicit status text and
labeled icon controls. The 375px product dialog test checks overflow and validation.

## Explicit open acceptance

- U06 background import is unavailable pending a reviewed Image Worker manifest
  providing verified bytes/hash/dimensions/readiness. UI explains this; no fabricated
  resource mapping or replacement uploader was introduced.
- Legacy records without a layout retain their old route until separately authorized
  activation C. V2 errors never select the legacy renderer as a fallback.
- Demo picker remains explicitly labeled and avoids live commands; a complete V2
  simulation fixture is not claimed.
## Actual local graphical QA - intermediate findings

Headless isolated `agent-browser` session `festapp-blueprint-b-ui`, Flutter port59600,
JS port59601, disposable backend API59521. Synthetic occasion2/form2/blueprint2 only.
No production requests or user browser interaction. Screenshots are actual app views,
not mockups or a simulation harness.

- `editor-default.png`: editable desktop palette/canvas, real registered font outlines.
- `editor-mixed-blocked.png`: group default, mixed products, one protected chair,
  disabled whole-group assignment and explicit free-only action.
- `editor-mobile-inspector.png`, `editor-mobile-mixed.png`, `product-dialog-mobile.png`:
  actual 375px inspector sheet/catalog dialog; text and controls fit, content scrolls.
- `editor-save-pending.png`: actual Save pending, actions disabled. Subsequent
  `editor-mobile.png` captures repairable placement rejection and preserved draft.
- `js-picker-error.png`: actual kernel mount failure, Retry/Close available and Continue
  disabled. No successful public hold is claimed at this stage.

QA discovered selection alone marking the draft dirty (root repairing host snapshot
comparison); the synthetic fixture placed table/standing partly outside canvas
(root repairing fixture through canonical save); actual browser Vite kernel validation
fails with a Dart runtime type mismatch while raw Node validation passes (host/package
owner diagnosing). Successful save/reload and public holds await these fixes.
`login-initial.png` and `editor-mixed-readonly.png` are earlier diagnostic captures,
not final acceptance evidence.

### Follow-up corrections

- Browser kernel failure traced to Vite renaming Dart2js constructors. Selector now
  loads the package raw kernel URL through public `loadKernel`, preserving compiled
  bytes. Actual archived-kernel lifecycle tests pass; browser rerun awaits server restart.
- Flutter public form initially showed unavailable despite open200 RPC. Actual
  FormBundle/FormHolder parse diagnostic passed. Existing broad load catch now logs
  error/stack and displays repairable generic Retry separately from closed/not-found.
  Exact runtime cause still awaits rebuilt app; no permission or availability bypass.

### Verified JS session and quantity flow

After the raw-kernel loader fix, actual S3 selection called `select_spot` once and
created both atomic-unit tickets (S3/S4, CZK200). Continue then reopening preserved
the unit; deselecting S3 released both and removed both tickets. No final order was
submitted. Standing quantity2 created two normal admission items at80CZK each,
without a seat hold. Final cards show the chosen product and omit required seat
input; real form validation reaches Summary160CZK. Existing summary uses generic
Registration1/2 headings without product details, so that presentation remains partial.

Final mobile screenshots: `js-standing-mobile.png`, `js-standing-order-preview.png`.
Host styles theme the shared viewer controls; generic package strings remain English.

Anonymous Flutter form loads; authenticated public form hits an unrelated optional
map-cache permission error. The broad form catch now logs its actual stack and shows
Retry rather than false closed state. Actual anonymous picker exposed nullable public
area-binding context mismatch, corrected by root; the final successful retry is recorded below. Repeated local57014 timeouts and killed debug server during workstation
pressure are recorded as environment interruptions, not successful acceptance.

See [54-row UI parity table](parity-evidence.md) for exact partial/open coverage.

### Final static release check

Final serial Flutter release was served statically on59600 (no Flutter process during
QA). Actual editor selection remained clean. Renamed Mixed table to Mixed table QA,
pressed Save, observed Uloženo, then fully reloaded: label persisted and dirty=false.
`editor-saved-reloaded.png` records the resulting saved state. Supplied verified font
resources are reused only with matching catalog SHA, valid resource structure and
complete glyph coverage; missing resources still resolve through the existing owner.

Before the final server-only correction, anonymous Flutter picker was blocked: public `get_blueprint` returns200 but
its data omits required snapshot `occasion`; compiled stack at main.dart.js48852
forces that null. Previous area-binding null was fixed separately. This is a public
DTO mismatch, not a successful hold test. UI shows retry and disables Continue.

### Final server-only projection correction and Flutter buyer result

Root added the verified occasion ID to the public get_blueprint projection, with SQL
regression coverage and no private field expansion. Same final Flutter artifact then
loaded successfully via Retry. Anonymous buyer selected S3: one select_spot200 held
both S3/S4 and produced2tickets/200CZK. Continue and reopen preserved2 selected seats.
Standing quantity2 added two normal product items without a hold RPC:4tickets/360CZK.
Returning to the form and removing one standing item gave3tickets/280CZK. Removing
S3 released both addressed members in one select_spot200 and left1standing/80CZK.
No final order or email was submitted; addressed holds were released before cleanup.

Evidence: `flutter-picker-unit.png`, `flutter-picker-standing-and-unit.png`,
`flutter-standing-mobile.png`. Minor presentation gap remains: standing's existing
product radio appears unchecked despite selected product defaults/title/price. No
claim of complete order submission, swap, cancellation or all54 parity rows follows.


## Continued completion pass (current source, QA pending)

- Background import now uses the existing Worker upload with a ready processed
  manifest, then verifies/decode-loads its resource before adding it to the draft.
  SVG is accepted only by the background profile and processed by the same owner.
  Both public clients load verified assets; failures remain retryable.
- Added visible seven-state text/count legends, package JS localization messages,
  Czech dynamic picker status text, canonical standing radio defaults and product
  titles/prices in the JS order summary.
- Offline geometry demo uses public package templates/resources with no business
  adapter. A separate explicit save callback is prepared for the event draft.
- Targeted JS preview regression: 10 passed. Public package browser picker suite:
  12 passed including localized accessibility and selection announcements.
- Fresh disposable fixture uses form1/blueprint1 and supersedes the earlier IDs.
  Actual new acceptance evidence will be recorded below after the debug app is ready.

### Completion pass: actual JS buyer and mobile recovery

- Actual public form1 selected atomic S3/S4, then standing quantity2. Summary showed
  Ticket headings, both standing product labels and 100+100+80+80 = 360CZK.
  Existing Submit Order returned accepted symbol `5R4A5P9Q8P`. Host DB verification
  found order8, four distinct tickets, two addressed and two standing lines,
  payment360, pending-only notifications with delivery fenced.
- At375x812, selecting Free premium while the local select_spot request was aborted
  showed pending guards, then restored zero selected places and a repairable error.
  Removing the route and retrying succeeded. Close/reopen restored that hold; wheel
  zoom and pointer pan changed the SVG viewBox while keeping one selected place.
  Releasing it returned zero selected places and normal form total; no hold left.
- Clicking ordered S1, blocked S2, foreign hold and unassigned place left selection
  empty and made zero additional select_spot calls (resource count4 before/after).
  Both occupied and empty places stayed nonselectable. Public tooltips contained
  public seat/product data only. Mobile page had no horizontal overflow.
- A locally aborted get_blueprint showed Retry + enabled Close + disabled Continue;
  removing the route and retrying mounted the actual viewer successfully.
- Evidence: `js-checkout-summary-final.png`, `js-order-accepted-final.png`,
  `js-selected-standing-final.png`, `js-mobile-selection-error.png`,
  `js-mobile-reopened-pan-zoom.png`, `js-mobile-unavailable-states.png`,
  `js-load-error-retry.png`.

### Completion pass: actual catalog and group draft

- Admin fresh read displayed seven-state text/count legend (including empty,
  used, blocked and held), clean Save disabled, and mixed protected table inspector.
- Created synthetic `QA Seat 10` from the existing product template, then renamed
  it to `QA Seat 2` and changed price to135 through the existing catalog dialog.
  Empty name and empty/negative-filtered price blocked Save with field errors.
  Important automation detail: Flutter's first focus synchronizes native input
  values; verify the settled field value before submitting.
- Applied QA Seat2 to the mixed group's unprotected members, preserving the sold
  member; default displayed135 and group remained mixed. Undo returned clean,
  redo restored dirty, canonical Save succeeded, full reload retained QA Seat2
  default135, two members, one protected member, and clean Save state.
- Evidence: `editor-seven-states-mixed-final.png`; catalog reload was also observed
  in the real dialog after full page reload.

### Processed background and individual seat persistence

- Actual admin selected PNG, uploaded through existing Worker, rendered processed
  image, saved and fully reloaded with clean state. Replaced it with SVG through
  the same processor, saved and fully reloaded; actual JS mobile public picker
  rendered the identical processed triangle/circle image behind seat geometry.
- Evidence: `editor-background-png-reloaded.png`,
  `editor-background-svg-reloaded.png`, `js-background-svg-mobile.png`.
- The local bridge initially duplicated CORS response headers; parent repaired
  the disposable bridge. Production transport and browser production blocks
  stayed unchanged. FilePicker immediately detaches its native input; browser
  automation retained that input for agent-browser upload of actual fixture files.
- Free premium individual override to QA Seat2/135 saved; blocking that seat saved
  and full reload retained product135, checked block switch and blocked count2.
  Unblocking restored available count2 and was saved. Other group members retained
  their previous assignments.

### Flutter buyer, safe demo and swap operations

- Actual Flutter mobile buyer selected Free standard100 and standing1/80. Standing
  radio was checked, total180. Existing checkout accepted the order for synthetic
  blueprint-b-flutter@example.invalid. Evidence: `flutter-standing-selected-mobile.png`,
  `flutter-checkout-summary-mobile.png`, `flutter-order-accepted-mobile.png`.
  Summary initially included a spurious missing-seat warning for standing; the
  narrow explicit-area condition was fixed afterward and requires final smoke.
- Actual wizard was entered via unit Create event -> step-by-step. Draft title
  persisted and appeared in the unit draft list. Its Blueprint step exposes the
  offline demo. Demo banner explicitly excludes orders/holds/catalog; renamed
  a text object and locally saved it. After clearing ResourceTiming before edits,
  zero resources/network requests occurred. Evidence: `offline-demo-edited-saved.png`.
- Actual canvas selection toggled swap seats2 ->1 ->2. Same-order preview showed
  tickets3/4 and order3 250->250; actual submit succeeded, selection cleared and
  data refreshed. Different-order preview showed tickets5/6, order4 100->150(+50),
  order5 150->100(-50); actual submit succeeded. Evidence:
  `swap-same-order-preview.png`, `swap-different-orders-price-impact.png`.
- Moving ticket6 from Other orderA to Free premium showed authoritative order5
  100->135(+35). Aborting the actual swap RPC preserved selection2 and no optimistic
  move; removing abort, reopening fresh preview and confirming succeeded, selection0.
  Evidence: `swap-network-error-preserved-selection.png`. A stale error banner after
  success was fixed by clearing it before a new preview; final smoke still needed.
- Physical-pointer failure was an isolated browser native-file-dialog artifact:
  window capture received no events. Recreating only the owned browser with private
  auth state restored normal pointer events and canvas selection. No global
  SelectionArea change was made.

### Final critical-flow evidence and corrections

- Admin replacement finally committed order20 with three tickets and350CZK. DB confirms original order3 partial cancellation (remaining150, paid250, history11) and order4 full cancellation (no assigned seats, history12). An earlier HTTP200 was a domain failure, not success; the host now requires response code200. Local canonical table ownership was repaired, then a fresh actual command succeeded.
- Final V2 swap used `swap_spot_tickets_client_sync_v1`, HTTP200, refreshed selection0 and no stale error. Earlier legacy204 observations are not evidence of the final command boundary.
- Wizard finalized event104/linkzcavyver, blueprint55/revision1 with15bindings and edited label “Wizard copied group”. Full navigation rendered the saved label. DB confirms zero foreign products and zero copied holds/orders. Screenshots: wizard-v2-copy-saved.png and wizard-v2-finalized-reloaded.png.
- Flutter buyer order19 is DB-confirmed: two tickets, one addressed plus one standing, payment180CZK. JS order8 remains four tickets/payment360CZK. All delivery stayed paused, with no external providers.
- Historical unavailable-background/demo and all54-open statements above describe earlier checkpoints. Current acceptance is the consolidated [54-row matrix](parity-evidence.md); remaining explicit gaps and canonical cutover/Basic migration gates are listed there. The old standing-warning and raw-error screenshots document findings before their fixes.

### Final canonical release acceptance

- Final release build loaded in the isolated local browser. Newly persisted QA Group2 appears before QA Group10 in the business-group chooser; selecting it leaves Save disabled. Screenshot: `group-natural-order-final.png`. Layer stacking order stays independent.
- The authorized Used ticket inspector now visibly contains ticket symbol, public and private ticket notes, Synthetic complimentary extra, customer, customer note and private order note. Screenshot: `admin-detail-notes-products-final.png`. The missing private-order-note admin projection was corrected and SQL privacy checks passed; public projection is unchanged.
- All54 parity rows now have explicit actual or combined boundary evidence in `parity-evidence.md`. All49 existing layouts passed the separate Basic visual review in `basic-review.md`, including230 visible but nonselectable unassigned chairs and18 halls reconstructed as native geometry, with zero raster backgrounds.
- Final validation reported by coordinator:222 Czech cases covered, final release build PASS, package/consumer/archive gates PASS. The wizard retry test fixture was corrected to an existing group draft because a zero-node document intentionally opens the template-gallery modal.
- Production data remains untouched. The private standalone review artifact is for the user's approval gate; completing local parity does not authorize deployment.
