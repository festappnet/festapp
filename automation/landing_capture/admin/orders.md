# Orders footage reproduction

The retained Czech clips are genuine canonical demo data, not fabricated table
rows. Source mapping: `routing-capture/orders-overview-v3-frames` plus
`orders-overview-cue.json`, followed by `orders-export-final-frames` plus
`orders-export-final-cue.json` in the external landing review directory.

1. Bootstrap local Supabase and its canonical demo fixture (`database/fixtures/demo_occasions/seed.sql` and `layouts.sql`). The filmed occasion
   was local demo3, slug `demo-1-ball-20261014`, 95 synthetic orders/260 tickets.
   Check that those counts and Czech participant names exist before recording.
2. Launch the real Flutter app at its loopback port using the local E2E skill.
   Set persisted Flutter locale to `CAPTURE_LOCALE` (`cs` for the current cut).
   For English, use the real locale and translate fixture values, never overlays.
3. Sign in as the local fixture account and open occasion > Orders > Current.
   Capture at 1440x1000. Snapshot fresh refs. Identify the Customer filter by its
   column position, click it and type `Anna`, then Enter. Show the actual change
   from 95 to 12 matching rows. Hold the paid/unpaid status cells for 1 second.
   Avoid the old rehearsal's `AAnna` intermediate typo.
4. Open Tickets. Click the actual `Stáhnout tabulku` button (English: translated
   Download table), capturing the click and settled table. Orders itself has no
   export button: this is explicitly the tickets CSV export, not an order export.
   The source export had 260 data rows /16 columns. Observe the actual browser
   download or original unchanged Blob; do not synthesize the CSV.
5. Use the portable `encode-orders.py`, then `append-export.py` with
   `CAPTURE_OUTPUT` containing the above source folders and
   `CAPTURE_EXPORT_DIR` as a fresh external destination. They trim the order beat
   to5.2s and append the ticket export. Keep both untrimmed takes for longer cuts.
   Desktop1200x520; mobile720x800 is a focused desktop crop, not device evidence.
6. Review beginning/middle/final frames for Czech labels, names, currency and
   actual filter/export actions. Current clips passed this visual locale audit.

No order/payment state changes or outbound messages belong to this recipe.

## Current report-first refinement

Open the **same canonical demo3 occasion** at `/demo-1-ball-20261014/reservations/report`
before Orders. Current actual figures are95 orders,260 tickets/300 seats and
124950CZK net receipts. These are income after refunds, not profit after costs.
The canonical fixture already supplies95 dated synthetic orders plus matching
payments across24 days, so no totals or chart points were invented for this take.

Capture the summary, point to the receipts tile, click `Po dnech`, then
`Celkem v čase`, and show the actual chart transition. Navigate through the real
Orders tab to the same occasion, filter Customer for Anna and verify95 ->12 rows.
The current cut appends the preserved real ticket CSV export, retaining the
original distinction between Orders filtering and Tickets export.

`assemble_report_orders.py TAKE LEGACY_RAW OUTPUT` combines5.7s report,0.9s
navigation,4.3s filter/result, and the actual original export. Desktop1200x760;
mobile720x900 is a focused desktop crop showing the receipts card and payment
chart first, then the customer/status columns. It is not claimed as mobile admin.
The export code preserves original timestamps and removes setup pauses only.

Current external take: `admin-refinement/report-orders-cs-1792670770` with cues
`report-summary`, `report-daily`, `orders-navigation`, `orders-filter`.
Keep full raw frames for the later long tutorial. Current posters intentionally
show Report so viewers see the revenue evidence before playback starts.

The final revision supersedes demo3 footage: editable standalone local occasion8, created by build_report_fixture.py without demo registration, now supplies the real report/orders/export cut. See clarity.md and final-takes.json.

## Authorized local edit appendix (supersedes historical no-edit recipe)

Only disposable editable occasion8 (`capture-report-1-ball`) is used. Existing order250 / sequence95 / variable symbol710000095 has `note_hidden` changed from NULL to `Příchod v 18:30` using the real Orders grid. Customer/email columns are read-only, so the supported internal-note cell was chosen. Payment state remains paid; no order creation, sending, email, payment or cancellation action occurs.

At1440x1000, navigate Orders/Current, horizontally scroll right until `Skrytá poznámka` appears, click its first-row cell, enter the Czech note, Tab, then click `Uložit změny`. Reopen via physical reload and horizontal scroll: the actual cell still displays the saved value and Save is disabled. Read-only SQL independently verifies order250.note_hidden and unchanged paid state. Proof and raw take order-note-cs-1792690032 live in external orders-edit, with saved.png, reloaded.png and edit-proof.json.

`append_order_edit.py OUTPUT web/organizers-media` first preserves the approved13.1s overview outsideGit, then appends6s actual cues (open1.2s/type1.6s/save1.8s/result1.4s). Desktop1200x760, mobile720x900, total19.1s. The mobile Save cue deliberately widens the actual source crop to include the real Save button; typing/result crop focuses on the note. Outer matte#ebf1f6. Approved Report posters stay unchanged; edit-proof*.jpg are separate evidence. Current Czech locale uses real app labels; for another locale rerun the same native steps with localized note. For longer YouTube retain untrimmed raw cues and the actual reload proof. Browser/Flutter closed; local backend owner requested backup-preserving shutdown.
