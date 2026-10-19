> Final native review: all49 layouts render without raster backgrounds;464 editable tables,17 dashed boundaries and4516 stable chairs. Actual physical-table drag moved its caption and8 original chairs; undo restored them. The rejected bitmap comparison is superseded by `preview/blueprints-native-review.html`. See [native Basic evidence](basic-review.md).

# Blueprint B parity evidence

Consolidated actual disposable UI evidence plus relevant host/package/SQL boundary checks. All54 rows are verified by the stated evidence; “Verified combined” does not claim that every server rejection was replayed through the browser. The final release UI proves the natural group chooser and complete authorized detail. All49 real-layout Basic visual review passed; see [review](basic-review.md). Final release build and222 Czech cases are covered. This is implementation/local-validation acceptance, not a production migration or deployment claim.

| ID | Evidence / remaining acceptance |
| --- | --- |
| P01 | Verified - actual catalog names, selected product and formatted CZK prices; existing dialog retains natural sorting. |
| P02 | Verified - actual create from existing product template, reload retained QA Seat; missing-template widget coverage. |
| P03 | Verified - actual rename and price135 retained after full reload; catalog save separated from layout draft. |
| P04 | Verified - actual blank title and empty/negative-filtered price validation; server authoritative amounts retained. |
| P05 | Verified combined - actual mixed-group free-only assignment/save/reload retained protected member; host atomic full-group assignment tests cover all eligible members. |
| P06 | Verified - actual individual Free premium override135/save/reload preserved other assignments. |
| P07 | Verified - actual mixed/default/member-price inspector before and after persisted assignment. |
| P08 | Verified combined - actual empty/unknown groups and unassigned seat show empty, no invented price; host null-product tests. |
| P09 | Verified combined - host explicit group inheritance tests and wizard reconciliation; mixed/unknown groups require explicit default rather than silent first-product fallback. |
| P10 | Verified combined - actual protected group and used-seat controls disabled; free-only persisted; SQL covers ordered/used/foreign and own holds atomically. |
| P11 | Verified combined - catalog mutation persisted separately; actual target-price swaps and SQL payment/history proof establish financial owner. |
| S01 | Verified - actual QA Group10 and QA Group2 created/saved, DB revision16 confirms stable new UUID. Final release chooser displays2 before10; selecting group leaves Save disabled. Natural-sort widget assertion passes; layer order unchanged. |
| S02 | Verified - actual group highlights/count/default/mixed inspector; selection does not dirty layout. |
| S03 | Verified combined - shared editor deletion plus host protection and SQL protected-delete rollback; no separate browser destructive replay. |
| S04 | Verified combined - exact existing A..Z/AA formatter reused by host; explicit group default/inheritance retained. All49 conversion preserves4516 identities/source labels; final host regression passes. |
| S05 | Verified combined - actual block/unblock save/reload; generic authoring create/remove and SQL protected geometry tests cover remaining mutations. |
| S06 | Verified combined - actual used/protected controls and SQL all protected-state structural guards/races. |
| S07 | Verified - actual seven-state text/count legend and own/unavailable behavior. Basic review decision: physical unassigned chairs remain green but unavailable/nonselectable with no-product tooltip; absence of a node is transparent. All230 unassigned chairs remain visible. |
| S08 | Verified combined - widget mode/Escape preserves geometry draft; actual successful swap/order clears temporary selection and refreshes states. |
| S09 | Verified - actual final release screenshot shows ticket symbol, public/private ticket notes, additional product, customer, customer note and private order note. Admin-only projection fix is SQL-tested; anonymous projection still excludes private data. |
| S10 | Verified combined - explicit binding membership and host reparent/history tests; copied wizard binding remap verified in DB. |
| W01 | Verified - actual two-seat toggle2->1->2, ticket/customer summary and confirmed operations. |
| W02 | Verified combined - UI only activates valid bound seats; SQL rejects same/missing/cross-event/blocked targets. |
| W03 | Verified - actual same/different-order swaps; DB retained ticket/order identities; final receipt RPC200 refreshes selection0. |
| W04 | Verified combined - actual ticket6 moved to free target; SQL two-free no-op coverage. |
| W05 | Verified - target retained QA product135, source retained100; existing owner changed moved ticket/order amount. |
| W06 | Verified - actual same-order250 unchanged and different-order100->150/150->100; DB payment/history checks. |
| W07 | Verified combined - actual occupied and free cases; SQL used/held rejection and metadata identity coverage. |
| W08 | Verified - actual aborted submit preserved selection/no optimistic success; retry succeeded; final canonical receipt200 refreshed selection and cleared error. Receipt replay SQL coverage. |
| O01 | Verified - actual three-seat selection/toggle/count and successful order; empty action disabled. |
| O02 | Verified - actual selected occupied SameA/OtherB plus free OtherA; blocked/decorative selection guarded by host/SQL. |
| O03 | Verified - actual analyze_new_order_spots showed authoritative three items/350CZK before confirmation. |
| O04 | Verified - actual preview partial order3 and full order4 cancellation with customer/ticket/product/amount detail; DB confirms both effects. |
| O05 | Verified - actual conflict dialog retained no-storno-email notice and financial explanation. |
| O06 | Verified combined - actual email validation, mobile dialog, failed-command retry and accepted fresh command; widget pending close/duplicate suppression. |
| O07 | Verified - actual existing Edge/command owner created order20, three tickets350; DB exact completed receipt. |
| O08 | Verified combined - actual accepted replacement clears selection and refreshes counts; SQL concurrency/revalidation rejects stale state atomically. |
| C01 | Verified - JS order8 four tickets360 and Flutter order19 two tickets180, both addressed plus standing; DB products/prices/payment match. |
| C02 | Verified combined - both actual clients hold/release atomic pair through one select_spot; SQL ownership/expiry/race coverage. |
| C03 | Verified combined - actual JS aborted selection rolls back and retry succeeds; package lifecycle and Flutter host tests prevent duplicate/past-generation results. |
| C04 | Verified combined - both clients reopen retained own unit and release it; host secret adoption and actual checkout payload tests. |
| C05 | Verified combined - actual both checkout flows and standing quantities; authoritative offered/wave/max guards plus nine real races, including maximum race. |
| C06 | Verified - actual failed reader shows Retry/Close, Continue disabled; retry recovers; close/continue preserves current selection. |
| C07 | Verified combined - actual public labels/status/price only; SQL anonymous projection privacy assertions exclude private customer/order data. |
| C08 | Verified combined - actual mobile both clients, JS pan/zoom/keyboard/Escape/reopen; shared renderer lifecycle and disposal tests. |
| U01 | Verified combined - actual admin/public routes, product and authorized ticket/customer previews; SQL projection/role tests. |
| U02 | Verified combined - actual rename, product assignment, block, background dirty/save/reload and undo/redo; host geometry/history/late-save regression. |
| U03 | Verified combined - canonical save stable IDs and new/copy identities tested; actual wizard copied15 bindings with zero foreign products/holds/orders. |
| U04 | Verified combined - actual successful canonical save; SQL revision/product/protected-delete atomic rollback and replay tests. |
| U05 | Verified - actual host Save/full reload through existing command wrapper; SQL receipts and publication coverage. |
| U06 | Verified combined - actual PNG/SVG processed upload/render/save/full reload and remove; JS same background mobile; generic canvas dimensions and canonical geometry persistence tests. |
| U07 | Verified combined - actual read-only/editor context, distinct operation controls; SQL geometry vs order role/scope rejection tests. |
| U08 | Verified combined - cs/en localization seams, actual Czech mobile products/orders/standing/error/loading, widget320px and final release chooser/detail. |
| U09 | Verified - reachable wizard offline demo banner, local edit/save and zero requests after ResourceTiming reset; no live business controls. |
