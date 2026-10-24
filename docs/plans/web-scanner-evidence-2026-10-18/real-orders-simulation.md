# Real-order scanner simulation - 2026-10-18

User authorized read-only sampling of actual Skautský / AKH / Country orders and local scanner simulations. Canonical festapptickets target was verified against tenant branch configuration, live activation (generation 1), protected SSH hostname, runtime database setting/current_database and organization 3. All production SQL used explicit read-only transactions. No production scanner session or admission RPC was invoked and no production state changed.

Sources: Skautský ples 2026, Domoradovice (occasion 82); Ples AKH 2026 (1072585); Country bál 2026 (32316). The similarly named Scout occasion 101 was inventoried to resolve identity but was not sampled. Captured sample: 3 orders per event, 27 tickets total. Scout: 8 used + 1 sent; AKH: 8 sent; Country: 5 sent + 5 ordered. One actual Scout order contains one used and one sent ticket. This is the default Scout scenario and its CTA is Potvrdit platné (1).

Customer content and screenshots are intentionally outside the repository in a workstation-private directory (0700, files 0600). Export excludes original ticket QR values, scan secrets, customer email/contact fields, bank identifiers and payment credentials. It retains only relevant order/holder names, non-hidden custom answers, notes (private notes only where the source event permits them), products/short titles, amount paid/remaining data and selected seat/group configuration. Local identities/form-field IDs and QR values are remapped; no original production QR is used. Imports preserve captured ticket/order states and refuse resetting an existing catalog. Earlier preliminary copies were retained; the active catalog uses the final mixed-order sample.

Implementation: `web_client/scripts/scanner_import_real_samples.mjs` imports into the existing isolated `festapp_scanner_*` database and writes a private catalog. `scanner_integration_server.mjs` accepts SCANNER_REAL_FIXTURES_FILE; optional loopback-only metadata routes select one of the private local event fixtures. The test browser offers event/order selectors, selected-order QR display and a clearly marked private simulation. Normal default fixture behavior remains available. The demo persists selected real event/scenario in its URL and auto-selects a mixed used/unused order when present. Product captions consistently identify dinner and transport using configured short titles.

Validation:
- All 27 imported tickets checked via local real scanner RPC against the private source for state, order grouping, purchaser name, notes, products and short titles.
- Actual mixed-order local admission attempted both codes inside a transaction: one accepted and one already_used conflict. Rollback verified the original one-used/one-sent simulation remained unchanged.
- UI confirmBatch regression confirms only eligible remaining tickets and skips used/unpaid; no second confirmation for already-used tickets.
- Cross-event lookups rejected another simulation event's QR in all three local scopes.
- Actual browser: Scout default 2 tickets / same order / one used / one valid / confirm 1; AKH 8 valid tickets across 3 orders; Country 10 tickets across 3 orders with 5 unpaid and confirm 5. Mobile 390 px had no horizontal overflow. Physical camera access was denied in the isolated automated profile.
- Final scanner JS: 41 passed, 1 skipped. Existing SQL contracts unchanged by the simulation harness work; actual scoped importer/RPC checks and rollback admission above were executed.
- Private PDF: 9 A4 pages, all 27 remapped QR labels and all page footers checked; dense last page visually inspected.

Routes on existing local server: `/scan?real=skaut`, `/scan?real=akh`, `/scan?real=country`. Confirmations affect only the selected local copies. Refreshing or selecting Znovu does not reset consumed tickets.
