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


## Publication / stage 2 start

Stages 0/0B/1 are published in PR https://github.com/festappnet/festapp/pull/564,
frozen head `aa2a191e5f82bcfbbaf8f556d8087a1136202762`, refreshed base
`9eef213f2b664b2b7f4978f51b43a90535ab7c8a` (only organization entry guard
changed upstream; no overlap with tested owners). Main currently requires one
approving review. No administrative bypass or production deployment performed.
Stage 2 continues on `feat/admin-mcp-standing-20261023`, stacked on that frozen head.

Delegated read-only release preflight verified canonical activation generation 1,
organization 3 and matching host/runtime/database assertions. Legacy names contain
rehearsal but are the actual canonical production target documented in the current
admin-dashboard guide; names alone are not a mismatch. Current tenant build is
0.20.365+860. MCP issuer is healthy at the prior 4cfc9b7 image. Candidate SQL
versions are absent from the live ledger. Private operational details and exact
commands are in `/tmp/festapp-admin-mcp-release-preflight-20261023.md`.

Stage 2A boundary before implementation:
- prepare_standing_inventory: existing product ID/version, actual occasion,
  organization/unit selection, capacity 0-1000000, immutable command ID.
- Existing owners: update_inventory_pool_bundle_internal_v1, resource rules
  extracted from save_resource_client_sync_v1 into one internal domain function,
  update_product_inventory_contexts_internal_v1 and apply_allocations.
- One outer receipt and one sync publication; no nested pool/resource/link
  receipt calls. Locks: receipt -> sorted existing order dependencies -> product
  -> newly created pool/context/resource/spots -> existing allocator reentry.
- UI BlueprintStandingInventory.prepare and setup dialog switch to one typed
  durable RPC; remove _pool/_resource/_linked/_capacity partial-success state and
  post-save catalog reload. Return authoritative product (including occasion,
  type, new aggregate version), new pool/context/resource snapshots/versions.
- Relevant UI read RPCs inventoried: get_inventory_pools_by_occasion_link,
  get_inventory_pool_bundle, get_resources_for_inventory_pool_v1. Their existing
  stock/allocation semantics remain owners for follow-on inventory read cuts;
  raw spots/hold secrets are not a general MCP read DTO.
- Targeted final batch: real PostgreSQL atomic rollback after pool/resource,
  lost-response replay and single receipt, version conflict and competing
  preparations via two connections, existing sold-item/addressed-seat allocation
  preservation and insufficient capacity. Resource command regressions, targeted
  standing adapter/dialog tests. No full suite after each edit.
- Follow-on read issue found: page-related types/contexts omit unused editor
  choices, including a type with no products. Supply a separate bounded choices
  read through the same projections before declaring full product authoring
  coverage; do not restore full-catalog transfer as a workaround.


## Stage 2A - locally complete

One `prepare_standing_inventory` transaction/receipt now creates pool, context,
resource and the existing product assignment. Shared mutation owners extracted:
`save_inventory_pool_internal` and `save_inventory_resource_internal`. Existing
pool full-editor snapshot and resource receipt APIs delegate to those rules.
Standing avoids constructing the unused full pool-editor bundle, and returns
one authoritative product/pool/context/resource snapshot (including product
occasion/type/version and existing form references). Sync publishes once to the
union of existing pool/resource/assignment audiences.

Removed `lib/components/blueprint/blueprint_standing_inventory.dart`, its
_pool/_resource/_linked partial-success memory, preparedCapacity state, retained
partial-operation text/getter, and setup dialog's post-command catalog reload.
Current UI `SupabaseInventoryCommands.prepareStanding` and MCP
`inventory.prepare_standing` use the same RPC. A separate explicit standing
consent never expands existing product-edit grants.

Final validation: 7 real PostgreSQL tests, no skips, including injected failures
after pool and resource, insufficient-capacity terminal rejection, authoritative
versions, existing paid item/addressed blueprint seat preservation, two-connection
competing command conflict and overlapping same-UUID replay, 3 existing inventory
regressions and source parity/ACL for 5 owners. 34 Flutter inventory/blueprint
checks, 15 remote and 30 consent tests passed. Targeted Dart analysis has no
errors/warnings (4 existing informational style/deprecation diagnostics).
Exact source digest and actual request/JSON-byte measurements:
`docs/reports/admin-standing-inventory-evidence-2026-10-23.json`.

Still local on stacked standing branch. PR #564 was updated independently to
head 6b7ce25f973aafb7b75e981077ee517e93df1cfc after the scoped deploy-gate test
correction and merge of main's unrelated public-link change (14a2f091f).
Review/merge is still required before production release; no live mutation ran.

Next: bounded inventory administration reads using the RPC behind actual stock
cards, including per-context physical/allocated/unassigned counts; then typed
pool/resource save/delete adapters. Preserve published client RPC boundaries.
Also close the unused product-type/context editor-choice gap with a bounded read,
not a whole catalog transfer. Operational seat cut 2B remains pending.
