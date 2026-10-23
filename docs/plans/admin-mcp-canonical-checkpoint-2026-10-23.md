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

## Next stage 1 - bounded investigation

UI `DbEshop.saveNewProductWaveTarget` uses receipt; existing target, move/cancel,
and standalone price changes use raw RPCs. Existing target receipt supports
`wave_id` plus `expected_wave_revision`; keep this domain owner. Wave operations
currently lock wave -> sorted products -> plans; scheduler order requires a
real two-connection qualification. Business revision conflicts currently raise
40001; distinguish them from infrastructure serialization/deadlock retries.
Next: complete stage 1 owner/typed contract/caller ledger, then implement together
and validate PostgreSQL + affected client adapter tests in one coherent batch.
