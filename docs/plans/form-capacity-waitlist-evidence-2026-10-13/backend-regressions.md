> Historical evidence of the pre-correction build, not current ticket-only validation.
> Obsolete participant-ledger smoke scripts were removed; use canonical database/tests.

# Backend waitlist regression evidence - 2026-10-13

Target: dedicated disposable PostgreSQL localhost:56922; no reset, production access, provider calls, commit or push.

SQL runner: `web_client/tests/database/run_waitlist_sql.js`, requiring explicit `DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:56922/postgres?sslmode=disable`. It executes the repository assertion helpers and each file in rollback transactions, without globally resetting sequences.

New SQL results (all PASS after coordinator fixes):
- database/tests/eshop_forms/form_capacity_schema_test.sql
- database/tests/eshop_forms/form_capacity_test.sql
- database/tests/eshop_orders/waitlist_lifecycle_test.sql
- database/tests/eshop_orders/waitlist_capabilities_test.sql
- database/tests/eshop_orders/waitlist_fakturoid_recovery_test.sql
- database/tests/eshop_orders/waitlist_email_queue_test.sql

Invocation: `DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:56922/postgres?sslmode=disable' node web_client/tests/database/run_waitlist_sql.js <one or more exact SQL paths above>`.

Existing targeted SQL results (all 12 PASS):
- database/tests/eshop/create_ticket_order_test.sql
- database/tests/eshop/create_ticket_order_errors_test.sql
- database/tests/eshop/orders/create_free_order_test.sql
- database/tests/eshop/deposit/deposit_order_creation_test.sql
- database/tests/eshop/deposit/backward_compatibility_test.sql
- database/tests/eshop/deposit/deposit_payment_status_test.sql
- database/tests/eshop/orders/cancelled_order_read_only_test.sql
- database/tests/eshop/orders/update_order_state_test.sql
- database/tests/eshop/orders/update_ticket_products_ws_test.sql
- database/tests/eshop/integration/full_deposit_flow_test.sql
- database/tests/eshop/integration/product_price_scheduling_flow_test.sql
- database/tests/eshop/product_price_scheduling_test.sql

Existing fixture change: create_free_order_test.sql adds the missing `form_fields(form,product_type,type) VALUES(800,900,'product_type')` binding. No scope guard was removed. All other preexisting test edits remain untouched.

Node invocation: `DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:56922/postgres?sslmode=disable' node --test web_client/tests/database/waitlist_concurrency.test.js`.

Latest Node output: 8 tests, 8 pass, 0 fail, 0 skipped.
- last person: exactly one ordinary order succeeds
- shared product across two forms: exactly one succeeds
- shared inventory pool: exactly one succeeds, exactly one spot allocated
- accept vs cancel
- cancel vs accept
- accept vs expiry
- canonical schema backfill statements: two product rows count as one person; identities/history preserved; ambiguous linkage blocks activation
- canonical template seeding twice preserves tenant custom content and default counts

Concurrency evidence uses two separate server connections with both backend PIDs observed waiting for SQL locks. Successful writers commit; FK descendants of only their dedicated synthetic tenant and its bank account are removed afterward. Cleanup also handled fixtures left by the runner's first development failure. Final check: no organizations titled 'Waitlist regression %' remain; email_capacity remains paused with worker_url NULL.

Two concrete defects found and repaired by coordinator:
- Domain product error code 1017 was passed as HTTP outcome status, producing `invalid mutation outcome`. Receipt HTTP status now maps separately while PRODUCT_CAPACITY_EXCEEDED remains in the domain body.
- The enabled waitlist CHECK allowed a NULL offer duration because PostgreSQL permits NULL CHECK results. Explicit duration IS NOT NULL added; regression now passes.

Behavior coverage: C/O/R/W/P (five released, two waiting yields public three); settings/blueprint/disable guards; schema defaults, CHECK, ACL, RLS and composite cross-form linkage; unlimited compatibility; active registration has NULL finance and no products/tickets; full identity/symbol/sequence and fresh payment deadline; partial child identity/person swap/remaining slot preservation; decline/cancel/expiry and queue tail; selective withdrawal; valid offers on closed forms; product-capacity failure atomically rolls back acceptance; GET/replay/tampering/cross-tenant/read-only actor/service auth/email dedupe; minimal revoked/expired capability reads; full/split Fakturoid abort twice, complete twice, expiry during prepare, late completion, prepare edit/cancel guards, preservation of independently changed unoffered remainder; queued snapshot refresh and expiry fencing; renderer recipient/offer/hash/envelope/ACL; template inheritance and idempotent seeding.

No unresolved backend regression blocker. UI/Edge renderer tests and integrated E2E belong to other workers/coordinator.

Final integration additions (all PASS):
- `database/tests/eshop_orders/waitlist_fakturoid_swap_recovery_test.sql`: 6 targeted recovery scenarios.
- `web_client/tests/database/waitlist_fakturoid_swap_recovery.test.js`: 3 real separate-connection scenarios.
- `database/tests/eshop_orders/waitlist_history_snapshots_test.sql`: original registration answers, full/partial snapshots, selected-person swaps, immutable history and secret exclusion.
- `database/tests/get_orders_tab_data_tenant_scope_test.sql`: scoped form lookup with duplicate occasion links and order-view permissions.
- Final canonical migration assembled and applied in one transaction; affected history/capability suites passed afterward.

No production migration, real provider send or publication performed.
