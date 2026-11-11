# Copied seated-ball regression

Business-function source: deployed main `5a16ef20b16c64967c348505ad72bb0a7c566de3`. Synthetic data only, through the guarded disposable PostgreSQL 15 runtime (`festapp-sql-runtime`, loopback port 55542). Each fixture transaction rolls back; failed differential databases are released by the runtime. No production operations.

Run from this checkout:

```sh
python3 automation/local_db/runtime.py exec -- node web_client/scripts/run_db_tests.js database/tests/eshop_forms/primary_product_guard_test.sql
```

The added integration case uses the actual public `start_occasion_lifecycle` copy command, loads the copied form with `get_form_for_edit`, and saves its complete nested field/product snapshot through `update_form_client_sync_v1`, including aggregate and product version baselines. It asserts opening persisted, source form remained closed and unchanged, copied products/plan have independent identities, and all four seats copied. It then closes the copied form and uses actual `preview_blueprint_seat_order` plus `create_blueprint_seat_order` to persist an order and ticket in the copy while leaving the source untouched. Source includes the ticket-owned primary admission group, dinner and transport.

Current result: PASS, one SQL test file containing the existing guard cases and the new full-copy case. Initial paired execution: 418 ms. Final execution with an explicit unit-administration viewer fixture precondition: 382 ms, concurrency 1, on the guarded local UI database (56522, project festapp-copy-e2e-20261110).

Differential controls run the identical full-copy case on independent disposable databases with exactly one previous function owner substituted transactionally from `5a16ef20^1`:

- Previous primary guard: expected failure during actual copied-form save, `FORM_DELETE_primary_product`, rejected receipt.
- Previous order analyzer: expected failure during actual closed-form order quote, HTTP/domain code 409.

Both controls fail at their intended assertions (psql exit 3). With deployed owners, the entire case passes. Logs are alongside this file. The fixture has no image/banner, so external asset copying is outside this regression.

A separate native-runtime rerun lost its connection when another PostgreSQL server process crashed; this produced no application assertion verdict. The final regression was run successfully on the disposable UI database afterward. This infrastructure failure is retained alongside the passing logs. Canonical installed function audit on the UI database matched all 972 checked signatures/body hashes.
