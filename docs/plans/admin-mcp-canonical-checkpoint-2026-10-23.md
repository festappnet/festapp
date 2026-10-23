# Execution checkpoint - admin UI/MCP

Base: GitHub origin/main `4cfc9b7bc66f48c2d6e42155f08e905dde112d0d`.
Workspace: `/private/tmp/festapp-admin-mcp-canonical-20261023`.
Main dirty checkout untouched. Verification: standard.

## Stage 0 - locally complete

Migration: `20261023160000_product_catalog_keyset.sql`.
SHA-256: `f13603e3ae3a76f94d7212d237e21171875b7abdeb5774e275d1e4dc4e07f5fa`.
Source owners: `get_product_catalog_data_internal`, `get_product_catalog`,
`get_product_catalog_page`; released-client adapter `get_products_and_types_for_edit`.
Callers: Flutter `DbEshop.getProductsAndTypes` keeps full bundle; MCP
`invokeProductOperation` now requests server pages. No write/receipt change.
Removed: Node full catalog sorting/filtering/slicing and per-product link scans.

Evidence: `docs/reports/admin-data-network-keyset-2026-10-23.json` includes actual
executor output sizes and inner SELECT EXPLAIN ANALYZE, all audit DDL/data rolled back.
3 product PostgreSQL tests and 14 remote HTTP/OAuth/consent tests passed, 0 skipped.
Canonical SQL source parity generator check and catalog generation passed (94 actions / 15 remote tools). Concurrent fixture is committed
only inside the marked, mail-fenced disposable DB, then explicitly cleaned up.
No new index: page reduces correlated subplan loops from 1000 to 50.
No production writes, no build/deploy, no publication yet.

## Stage 0B - administration meaning, locally complete

User explicitly requested the operational administration view, including useful
relations and aggregate semantics. See `docs/architecture/product-admin-read-contract.md`.
SQL purchased_count now owns paid+sent totals; current UI consumes it and retains
counts during edits. MCP exposes form IDs/titles and stock pool names/type/date,
with no public form links. Three independent count scans became one lateral
aggregate; forms/inventory joins cannot multiply the counts.
Migration `20261023163000_product_admin_read_semantics.sql` SHA-256:
`a61747a53d860161f1e3d0cf451f3a794cd9d0eac8ba38fc5814e5980935fa11`.
Tests: 3 real SQL tests, 0 skipped, include 2 paid tickets in one order, sent and
storno relationships, duplicate form fields and 2 inventory assignments; actual
MCP executor returns purchased_count=3, ordered_count=4. 4 Flutter grid tests
passed, including preservation of canonical counts through local edits/copyWith.
Evidence: `admin-data-network-admin-view-2026-10-23.json`; previous files retained.
Publication/deployment still pending; no production writes.

## Stage 1 - locally complete

Owners/callers:
- UI DbEshop -> SupabaseProductScheduleCommands -> manage_product_schedule.
- MCP product_schedules.list/change -> get_product_schedule/manage_product_schedule.
- Shared wave matrix projection: get_product_price_waves_internal, consumed by
  the full administration catalog and bounded schedule list.
- save_target delegates to the existing target receipt with no outer receipt.
  ensure/move/cancel and standalone price save/cancel each have one domain receipt.
- Existing raw wave/price functions retain their actual rules. Current UI raw
  calls removed; occasion_setup/finalize.sql still uses create/target inside its
  own existing transaction. Published old clients retain compatibility RPCs.
  Removal gate: last supported client upgraded plus SQL caller migration.

Conflicts are receipted 409 outcomes; true 40001/40P01 remain retryable with the
same identity. Failure after new term creation rolls back term/adoption/targets.
Scheduler prelocks due products by ID to eliminate time-order inversion against
wave move. Target edit preserves separate price/visibility revisions and explicit
null/false semantics. Setup draft new target uses one onChanged, not create+save.
No historical purchased prices, payments, ticket lifecycle or email effects change.

Migration: `20261023170000_product_schedule_commands.sql` (digest and exact request/
byte evidence in `docs/reports/admin-product-schedule-evidence-2026-10-23.json`).
Verification: all 87 MCP tests passed with real DB, 0 skipped; final targeted
10 schedule SQL tests passed, including 6 canonical regressions, actual
checkout/history/payment price preservation, sync-failure rollback and source
parity for 8 changed owners. 18 scheduling/setup Flutter tests passed; final
13 setup/transport tests passed after adding the atomic draft test; 29 consent
web tests passed. Targeted Dart analysis: no errors/warnings, 10 existing style
infos. New test registered in eshop_unit_cases for the shared client runner.

Disposable fixture corrections: regression tests run as their intended postgres
role with service JWT for scheduler probes; checkout fixture now supplies the
canonical form/blueprint/seat binding and hold expiration, like the supported
checkout tests. The disposable DB has unrelated older `_swap_spots_update_ticket`
body drift, so runtime source checks are limited to the 8 affected owners;
authored-vs-effective whole-repository generator check still passes. No readiness
hash regenerated. No production writes, no publication or release yet.

## Exact next steps

1. Publish verified stages 0/0B/1 to fresh authoritative main; reconcile any
   intervening commits and rerun only affected checks.
2. Delegate routine frozen-source festapptickets release: target/org/activation,
   backup and atomic SQL+ledger, consent web build/direct deployment, then issuer
   image using the same MCP registry. Preserve known rollback images and probe
   exact live SQL/ACL, issuer health and coherent tenant version/build/legal.
3. Continue stage 2: replace BlueprintStandingInventory.prepare's three writes
   and _pool/_resource/_linked memory with one durable domain transaction, first
   reusing the internal owners behind inventory pool/resource/product commands.
   Preserve actual existing-order allocations; inspect the relevant inventory
   administration RPCs and table meaning before extending MCP.
