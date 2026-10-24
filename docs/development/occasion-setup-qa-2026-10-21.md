# Occasion setup - browser QA, 2026-10-21

Initial QA result: NOT PASS. Creating a new event worked, but copying an event
with a blueprint failed, and reopening a finalized draft trapped the user.
The initial QA made no product-code or production changes. The repair follow-up
below resolves these original findings locally; it is not a whole-wizard release
sign-off. No production writes or deployment were performed.

## Environment and method

- Current working tree on `feat/occasion-setup-wizard-20261007`, HEAD
  `eb2304724`, including existing uncommitted changes.
- Real Flutter app through `test/browser/occasion_setup_e2e.dart`, debug wizard
  enabled, current `AppConfig.isAppSupported=true` configuration.
- Fresh owned Supabase project `festapp-wizard-qa-20261021`, canonical baseline
  and forward migrations, local seed account, API/DB ports 56821/56822.
- Six configuration-only source snapshots imported from the existing private
  October 5 local fixture. No customers, orders or payments imported.
- Isolated local headless Chromium session `wizard-qa-20261021` with an empty
  browser config. Production Festapp/Supabase and OneSignal requests blocked.
  Push callbacks stubbed by the existing entry fixture.
- Flutter pointer clicks did not invoke handlers reliably. Tested buttons and
  switches through DOM clicks on their actual Flutter semantic nodes. Input
  fields used browser fill. This proves application handlers and persistence,
  not all physical pointer hitboxes.

## Confirmed defects

### 1. Copy with blueprint cannot finalize

Reproduction:

1. In the event list, choose Skautsky ples 2026 > Create copy > confirm.
2. Keep the selected source and proceed through the questions.
3. Keep its copied form and blueprint, with 182 seats.
4. Skip optional organization verification, confirm review, create event.

Actual: only generic failure and Retry/Back are displayed. Retry fails again.
The database reports `Occupancy is server owned`; no copied event is committed.

Cause: `database/functions/occasion_setup/sources.sql` supplies seats with
`state=available`. `finalize.sql` removes `id`, `order_product_ticket` and
`secret`, but retains `state`. The current `update_blueprint_internal_v1`
rejects any object containing server-owned `state` or `secret_expiration_time`.
The failure also occurs after opening the real blueprint editor, increasing
width from 32 to 33, and saving successfully into the draft.

Additional compatibility finding: a rollback-only diagnostic probe stripped
`state` and `secret_expiration_time` from the copied draft. Finalization then
failed with `Invalid ticket layout`: this historical source contains layout
schema 1, whereas the current validator requires schema 3. This is evidence
for the imported older configuration, not a claim about current live sources.
Fixing occupancy alone is therefore insufficient for this fixture.

### 2. Finalized draft stays resumable and Leave fails

Reproduction:

1. Finish a new event successfully.
2. Return to the unit event list. The event exists, but its draft also remains
   under unfinished drafts at 100%, with Continue.
3. Continue that finalized draft and choose Leave.

Actual: the wizard remains open and displays the generic draft save error.

Cause: `get_occasion_setup_drafts` includes finalized rows. `_leave` forces
`_dirty=true` and saves them, while `save_occasion_setup_draft` explicitly
rejects `finalizedOccasion`. Finalization replay itself is safe: a direct
authenticated rollback probe returned the original receipt and created no
additional event.

## Passed scenarios

- Local authentication, event list, new wizard entry through More options.
- Empty event name blocked; corrected name saved.
- Invalid event slug blocked; corrected slug saved.
- Autosave failure simulated by aborting `save_occasion_setup_draft` requests:
  visible error, changes retained, Retry succeeded after restoring requests.
- Form title and slug, payment deadline 7 days, reminders enabled, text and
  note fields added and persisted.
- Leave, physical browser reload, Continue: resumed at the form question with
  saved configuration. Screenshot confirmed the restored form title.
- Optional organization verification skipped; review remained accessible.
- Review required its confirmation checkbox and a separate confirmation step.
- New event finalized into exactly one hidden, closed event. Persisted form
  `QA Registrace`, slug `qa-registrace-20261021`, five stored form fields and
  one product. The form remained closed. Browser navigated to event settings.
- Copy entry selected the correct source automatically, with four source form
  fields, 182 available seats and product prices. Blueprint width change saved
  into the draft without materializing an event.
- Review visually inspected at 390 x 844: readable content and fixed navigation.
- Existing database suite: `2 Passed, 0 Failed` for
  `database/tests/occasion_setup`.

## Limits and evidence

Date/time picker interaction was not established through this browser's
semantic layer; finalization used the generated default dates. Physical pointer
interaction, dragging seats, the ticketing-only wizard's separate payment/ticket
questions, live ticket PDF preview, organization verification submission and
external integrations are not claimed as passed.

The fresh storage initially lacked the historical source background. Its bytes
were recovered read-only from the old local storage volume and uploaded to this
owned project's bucket (HTTP 200). The running Flutter image retained its cached
error, so the source background's rendered appearance is not claimed as passed.

Private local evidence, command logs and screenshots are in
`/tmp/festapp-wizard-qa-20261021/`. The failed copy and successfully finalized
draft remain in the disposable database for reproduction. Rollback probes did
not commit fixture changes or diagnostic events. Browser and owned services
were stopped after the session.


## Repair follow-up - 2026-10-21

The original findings are resolved in the owned local project
`festapp-wizard-qa-20261021` (API/DB 56821/56822), without resetting its data.
Canonical SQL and forward migration
`20261021190000_occasion_setup_finalize_repair.sql` contain the repair. The
migration was applied with `automation/baseline.py upgrade-local`; its ledger
and canonical definition parity were checked.

- The finalization boundary strips seat IDs and all four server-owned occupancy
  attributes: state, order_product_ticket, secret and secret_expiration_time.
  Sources also omit secret_expiration_time. The general blueprint command keeps
  its strict occupancy validation.
- Finalized rows are excluded from resumable drafts. Their rows and receipts
  remain stored. A permission-checked single-draft RPC lets an already-open page
  recognize concurrent completion after a rejected save, retain the receipt and
  leave. An active revision conflict still requires explicit recovery.
- Historical schema 1/2 is an offline import format, not a supported runtime
  layout. The existing canonical converter is
  `automation/tickets/product-type-cutover/convert.ts`; settings, authoring and
  renderers support schema 3. No second runtime converter/renderer or relaxed
  validator was added. The four October 5 local source fixtures (IDs 5-8) were
  converted using that converter. New inactive slots use its canonical preset;
  existing artwork, geometry, fonts and flow use its historical conversion.
  The source-5 draft's layout was updated consistently (revision 13 to 14).
  All converted references passed SQL validation before the local transaction
  committed. This does not establish the state of any production source and
  does not authorize production data changes.

### Verification performed

- `database/tests/occasion_setup`: **3 passed, 0 failed**. The new finalization
  regression exercises source serialization, editor occupancy fields, a real
  blueprint, new seat/product IDs, ticket product-type remapping, closed/hidden
  state, no copied orders or holds, stale revisions, two replay command IDs,
  terminal receipt reads, exclusion from the resumable list and rollback after
  late invalid-layout rejection. Reinstalling the original finalizer inside a
  rollback-only transaction makes it fail with `Occupancy is server owned`.
  The original source serializer also failed the new hold-expiry privacy check.
  The final regression additionally passed a corrected retry using the same
  command after late rollback. It owns a synthetic actor/unit/organization so
  concurrent manual QA cannot exhaust its creation-rate budget.
- The added single-draft authorization assertions passed separately, including
  denial after editor rights are revoked and denial for anonymous callers.
- `deno test --allow-read --allow-env --allow-net
  supabase/functions/_shared/ticketTemplateImport_test.ts`: **4 passed**.
- Targeted Dart analysis of the draft model and page: no errors or warnings;
  three preexisting brace-style infos. The real Flutter web app compiled and
  exercised the changed client code. Migration layout/coverage checks passed.
- Isolated headless browser `wizard-repair-20261021`, explicit empty config,
  blocked production/push requests, real local Auth. The shared single Flutter
  server on 56880 was owned by the concurrent deeper-QA session; no second
  Flutter task was started.
- Resumed the originally failing source-5 draft and finalized it through the UI:
  occasion **53**, **182 seats**, width **33**, every seat bound to a new product
  in the new occasion, no reservation secret/expiry/order relationship and zero
  orders. Event hidden/closed, form closed. The finalized draft disappeared.
- Created **Repair nová akce 2026-10-21** from scratch through the wizard's real
  questions, skipped optional verification, confirmed review and finalized:
  occasion **57**, hidden/closed, one closed form, navigation to its settings.
- Opened a separate draft **Repair souběžné dokončení** in the browser, completed
  it through the authenticated finalization RPC in a second client, then used
  the retained page's save-and-leave action. Its save was rejected (HTTP 400),
  the single-draft read returned the terminal receipt (HTTP 200), and the page
  returned to the event list without a save-error trap. The finalized draft was
  absent from that list and its receipt remained stored.

Button handlers were exercised through Flutter semantic DOM nodes where physical
pointer clicks did not work reliably. This still does not prove pointer hitboxes,
calendar interaction, dragging, live PDF output or external integrations. The
background's rendered appearance was not reassessed. Broader independent QA has
also reproduced a separate `Bez plánku` defect: selecting no blueprint after
copying retains blueprintObjects, which finalization still materializes. That
new scenario is outside this repair and prevents calling the entire wizard QA
complete; it is being recorded by the separate deeper-QA session.

Private evidence is under `/tmp/festapp-wizard-qa-20261021/repair-*`; do not
publish raw network logs or configuration inventories. The repair browser was
closed. The backend and shared Flutter server were explicitly handed back to the
ongoing deeper-QA session and were left running for it.
