# Demo occasions - implementation evidence, 2026-10-14

Final tenant scope: vstupenky.online / festapptickets / organization 3. Operational fixture version: `2026-10-14.3`.

- Ball: 249-seat plan based on the sanitized structural reference from occasion 82, 240 active synthetic participants, admission tickets/PDF, grouped orders, underpayment, split payment, overpayment, unmatched payment, additions and cancellations with history.
- Concert: 55 synthetic admission tickets, two price variants, shared capacity and no seating plan.
- Weekend: 24 admitted and 4 waiting, accepted offer retaining the person's original ticket-table identity, lodging and program. No admission symbols, ticket layout/PDF or seating plan. Internal ticket rows remain the existing application model.

Shared demos stay protected against persisted mutations. Their open forms use the existing model, fields, validation, seat picker, price calculation and preview. A server-derived `demo_simulation` flag changes only the submission/reservation boundary to a local simulation in both clients. No checkout/waitlist/reservation RPC, payment or email is issued. The normal result component explicitly identifies the demo and says registration was not saved, no email was sent and no payment was started. Forged client flags cannot bypass SQL protections. Own copies use the existing receipted duplication command and start hidden with closed forms, empty occupancy and no demo bank/customer/history data.

## Verification

Owned disposable local Supabase API 56831 / database 56832, never production test data. Bootstrapped current main schema and forward migrations; the Slunovrat-specific migration prerequisite used an explicitly synthetic organization 19. Earlier local fixture versions were withdrawn, not reused as current evidence.

- 7 targeted SQL suites passed: demo permissions, direct RLS/bank/media protection, fixture integrity, copy/replay, existing creator and destination behavior, app-config tenant scope.
- 13 web form/session/result tests passed, including checkout and waitlist with zero write calls and seat selection/removal with zero reservations.
- 57 Deno tests passed: real Edge entrypoint registration/auth rejection, shared ticket rendering and background reuse.
- Targeted Dart analysis: no errors; pre-existing FormPage immutability warning and style info remain.
- Isolated headless full Flutter app: login, catalogue, ball administration/orders, form and seating-plan display, concert form validation/preview/demo result, weekend waitlist form, ball copy to owned Unit and editable settings. Copy readback: hidden/closed, no orders, no open/banked forms, 249 unoccupied seats. External notification SDK was stubbed; production and legacy endpoints were blocked.
- Four final renderer PDFs: Czech diacritics and QR `DEMO-7K6M8R` decoded; demo footer present only on source examples. Weekend intentionally has no PDF.

Screenshots and PDFs are adjacent to this document. `catalog-desktop.png` was captured before creating the own copy. The seating-plan image is the genuine reference geometry, with synthetic occupancy.

## Reproduction and activation

Generate the migration with `python3 automation/assemble-demo-occasions-migration.py`. It contains exact canonical SQL sources, including removal of the two superseded read helpers without CASCADE. Apply the migration and ledger atomically through the protected canonical backend workflow. Seed only the explicitly selected tenant with `automation/seed_demo_occasions.sql` and `demo_organization=3`. This maintenance entrypoint does not invoke production checkout, Auth invitations, bank ingest or email producers. It creates an unlisted version and is idempotent for that tenant/version. After verified backend, Edge and client release, run `automation/activate_demo_occasions.sql` for organization 3. Withdrawal changes `is_listed` only; retired versions remain protected.

## Navigation correction after live review

Demo cards now enter the same existing reservation shell as an ordinary ball. All three keep its established tabs; no demo administration tab list is composed. Ball has Tickets and Blueprint, concert has Tickets without Blueprint, weekend has Applications without either. Legacy demo `/admin` entries normalize to this shell. Desktop and mobile breadcrumbs show the viewer's owned organizer and a localized demo suffix on the occasion title. The demo notice, return and copy actions use the wizard's floating card styling, centered over the content, including nested page footers. The card appearance remains as reviewed.

The originating owned occasion list is retained in `demoReturnTo`; return restores that list, including after physical reload. Direct entries fall back to an owned Unit, never the demo's storage Unit. Local headless checks compared ordinary and demo ball tabs, checked concert/weekend differences, legacy-entry normalization, desktop/mobile footer and both return paths. Three focused navigation tests passed and targeted Dart analysis found no errors.

## Presentation and settings correction

The existing fixture links and IDs remain stable. `20261014180000_demo_presentation.sql` corrects only organization 3's registered `.3` synthetic fixtures. The same temporary maintenance routine runs at the seed boundary, including repeat calls. Sales now span six weeks before the fixed 2026-10-14 reference, payments/history/waitlist dates follow registrations, pending payments have current deadlines, and upcoming admission events predominantly use the ordinary `sent` state with no premature check-ins. Monetary totals, participant counts and seat assignments are retained. Services are disabled in fixture configuration, removing the Capacity Groups tab without changing ordinary events.

Read-only occasion settings previously mounted the ticket editor thumbnail, which requested the editor-authorized preview endpoint. Settings now propagate their existing editing permission into that component, preventing preview/edit calls in read-only mode. The editable settings path keeps its thumbnail. A focused widget regression covers zero preview requests; the isolated concert settings route also records zero such requests and no unexpected-error toast. Four settings widget cases, four navigation cases and three targeted SQL suites pass; targeted Dart analysis has no errors/warnings. The rendered report now shows September-October sales instead of future January sales. Desktop/mobile screenshots capture the organizer breadcrumb and floating panel.

## Floating overlay and read-only form inspection

The demo panel lives in a Stack above the whole administration page instead of its bottom navigation slot. The content keeps the full viewport height and remains visible behind the floating card. The overlay sits 64 px above the viewport bottom, leaving the ordinary save/cancel footer visible. Read-only forms allow field selection and product-detail dialogs; title/configuration editing, HTML uploads, reordering and saves stay disabled. Field selection does not mark the form as changed. The same inspection behavior applies to ordinary read-only forms through their existing editing permission. A regression opens the real product dialog and verifies disabled inputs/HTML editing, unchanged product data and zero edit notifications. Another verifies full page height and clearance above a nested footer. Together with existing form preview/action coverage, 26 targeted tests pass; targeted Dart analysis has no errors or warnings. No database or Edge changes.

Response tables omit the waitlist-detail column for all forms. The capacity header renders only when its summary or offer action is visible; forms with disabled capacity no longer retain an empty 32 px padded header below their tabs. Waitlist detail remains in the ordinary order/waitlist workflows.
