# Product price scheduling - local validation, 2026-10-04

Implemented in the existing uncommitted working tree, preserving the other ongoing
editor/report changes. No commit, push, production migration or deployment.

## Database

A new disposable Supabase project `festapp-price-e2e-20261004` used PostgreSQL 15.8,
API `http://127.0.0.1:56721` and DB port 56722. Existing projects on 55432, 55434 and
55442 were not reset. Restored the canonical `20260805230000` baseline, all newer
repository migrations and seed; then loaded `test/fixtures/product_price_scheduling/tenant.sql`.
Supabase CLI 2.111.0. Runtime setup followed the festapp-local-e2e runbook.

```sh
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:56722/postgres?sslmode=disable' \
node web_client/scripts/run_db_tests.js \
  product_price_scheduling_test product_price_sync_failure_test \
  product_price_scheduling_flow_test create_ticket_order_test \
  create_ticket_order_errors_test form_editor_deletion_test \
  client_sync_production_hardening_test

DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:56722/postgres?sslmode=disable' \
FESTAPP_DISPOSABLE_PRICE_DB=yes \
node web_client/scripts/test_product_price_scheduling_migration.js

DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:56722/postgres?sslmode=disable' \
FESTAPP_DISPOSABLE_PRICE_DB=yes \
node web_client/scripts/test_product_price_scheduling_concurrency.js
```

Results: 7 SQL tests passed. The contract test was subsequently extended with
explicit product-deletion cleanup and passed again. Real authenticated-role
creates round-trip through the RPC. Viewer/foreign-user writes, stale revisions,
colliding instants, invalid/overflow amounts and past times are rejected. Ordinary
product and embedded form saves cannot change currency while plans remain.

Migration harness restores the old columns and introduces a valid null-owner
plan, duplicate instants, an invalid value and orphan. Valid ownership is
backfilled; all invalid rows, including both duplicates, survive as failures.

Concurrency harness uses separate connections and verifies actual lock waits:
two workers, cancellation after application, cancellation before application,
and moving a due plan into the future while the worker waits. Chronological
backlog produces exactly three sync commits; retry produces none. Fault injection
into the real sync boundary leaves the price unchanged and the plan unapplied.

The real order integration creates an order at 1000, applies a planned price of
1200, then submits a second order with a stale client price. The server charges
1200 for the new order; the old order, payment and history stay at 1000. No
checkout implementation change was needed.

## Flutter and tab refresh

```sh
fvm flutter test \
  test/components/single_data_grid/tab_refresh_test.dart \
  test/components/single_data_grid/data_grid_column_header_test.dart \
  test/components/single_data_grid/data_grid_helper_test.dart \
  test/components/eshop/occasion_report_test.dart \
  test/components/eshop/product_price_scheduling_test.dart \
  test/components/forms/form_editor_actions_test.dart
```

Result: 32 tests passed. Coverage includes DST gaps and overlapping instants in
Europe/Prague, keyboard Enter on the cell action, a complete pending timeline,
applied records hidden, read-only rights, disabled repeated submission and
preserved form after a failed request, mobile layout at 1.5 text scale, automatic
tab reload, retained drafts, editing begun during a request, sort/width retention,
Report reload and the existing embedded editor save/discard behavior.

Targeted `fvm dart analyze` covered the changed feature, grid, tab activity,
reservation/admin shells and new fixtures. No errors; two redundant null assertions
in the new test were removed and its analyzer then reported no issues. Remaining
findings are informational repository style/deprecation notices, including the
existing uppercase grid column identifiers. `git diff --check` passed.
Translation unify/reorder scripts ran successfully.

## Actual headless UI

```sh
fvm flutter run -d web-server \
  --target test/browser/product_price_scheduling_e2e.dart \
  --dart-define-from-file <private-local-defines.json> \
  --web-hostname 127.0.0.1 --web-port 56780

agent-browser --config <task-owned-empty-config.json> --headed false \
  --session festapp-price-20261004 open http://127.0.0.1:56780/login
```

The fixture guards the loopback backend and runs the real app. Existing Chrome
windows were not used. Production domains were blocked; external OneSignal
resolve/reject callbacks were stubbed. This validates local password Auth and
REST, not live push, OAuth or production connectivity.

Observed sequence:

1. Login through real local Auth and open `/price-e2e/reservations`.
2. Open Products and the action inside its price-change cell.
3. Create 550 on 15 October 09:00, 650 on 1 November 00:00 and 500 on
   10 November 18:00. DB instants match Europe/Prague offsets; cell shows `+2`.
4. Edit only the first to 575 on 16 October, revision 2; the other targets remain
   650 and 500. Cancel the middle plan through the confirmation dialog; others
   remain and the cell shows `+1`.
5. Inspect desktop and 390x844 fullscreen dialog. Screenshots are in this folder.
6. Leave Products for Report, make only the synthetic first plan due, and run the
   existing `apply_planned_changes()` on the disposable DB. Return to Products:
   automatic reload shows current 575 and the remaining absolute target 500.
7. Hot restart and physical browser reload preserve local authenticated access;
   the Products tab reads the confirmed current price and remaining plan again.

The Flutter accessibility tree sometimes lagged native pointer actions. Precisely
scoped DOM semantic button clicks invoked the real Flutter handlers where needed;
no router/history mutation or mocked scheduling RPC replaced the flow. Keyboard
Enter is covered deterministically by the widget test. Visual captures:
`products-desktop.png`, `timeline-desktop.png`, `timeline-mobile.png`,
`products-after-application.png`.

Owned browser/server/backend are stopped after verification.

## Remaining operational step

Production is not verified. After separate deployment authorization, apply
`supabase/migrations/20261004150000_product_price_scheduling.sql` through the
canonical self-hosted release workflow, inspect retained legacy failures, deploy
the updated Flutter administration for one selected tenant, and verify exactly
one existing minute cron calls `public.apply_planned_changes()` with the correct
service identity/database and successful recent runs. Do not add another cron or
scheduler. Perform an authorized production smoke check without creating test
prices on real products. Shared changes still need normal integration into main
before the tenant release; this task performed no publication.


## Deployment preparation, 2026-10-04

User authorized deployment to vstupenky.online. The feature was ported onto current canonical main in an isolated checkout, preserving the latest report, routed tabs, form deletion/performance rules and library updates. A nested routed-tab regression reproduced missing outer-tab activity notifications; the final boundary propagates both controller and parent activity changes.

Release checks: 113 SQL test files passed; 1080 Flutter tests passed with one existing skip; 242 Deno tests passed; web and automation checks passed. Three local worker integration tests passed; 27 external credential-dependent cases skipped. The first full run caught the nested-tab regression and missing local worker dependencies; the corrected Flutter suite and initialized worker integration suite passed separately. Migration legacy-preservation and real-connection concurrency harnesses passed on an isolated PostgreSQL 15 database at 127.0.0.1:56722. Changed-code analysis has no errors or warnings.

Read-only production verification: tenant festapptickets, canonical activation generation 1, organization 3, runtime festapp_rehearsal_20260909220601. Existing control-plane job 10 is active every minute and targets public.apply_planned_changes() in that runtime. There were no pending production plans at inspection. Required form-deletion migrations 20261004120000 and 20261004133000 are present.

Deployment is pending protected-main publication and production migration/frontend rollout. Local build preflight correctly requires the private release manifest; the established GitHub Deploy workflow supplies it. No private contract is fabricated. No other tenant release is authorized.
