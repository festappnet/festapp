# Canonical administration and MCP

UI visibility is not authorization. The current ordinary user's typed SQL
operation predicates remain authoritative. Delegation additionally narrows
organization, units/occasions and explicitly consented functional scopes.
Existing issued grants are never expanded by adding tools.

## First cutover: product catalog

- Seam: catalog reads and immediate product configuration, deletion and stock
  assignment. Scheduled price/visibility changes are a subsequent slice.
- Shared boundary: `get_product_catalog` and `manage_product`. Flutter and MCP
  call these same RPCs. Inputs pin organization, occasion and optional unit;
  reads also accept the UI's occasion link. Writes accept a fixed action,
  original product version, payload and immutable command UUID.
- Owners retained: `get_product_catalog_data_internal`, product client-sync
  commands and their internal domain functions. They alone calculate prices,
  enforce product/plan/order usage, update inventory and publish sync receipts.
- One product save may contain the complete inventory assignment. Both clients
  submit one domain request; no adapter saves the product then stock separately.
  Authentication/session validation remains separate from the domain request.
- Result: existing command receipt, conflict or rejection, without an outer
  receipt, extra commit, duplicate publication or independent calculation.
  An uncertain response is retried with the identical UUID and payload.
- Scope is checked before execution and locked/rechecked after domain locking,
  including receipt replay, before returning. Failed final checks roll back the
  complete transaction. No external delivery occurs in these product commands.
- Removal set: direct current-UI calls to the three product write RPCs and the
  old catalog read, order-specific permission-registry naming and copied
  permission label maps. Order item editing remains a different operation.
- Compatibility: published product RPCs remain callable by released clients
  and canonical SQL facades. Their implementations are the single existing
  domain owners, not alternate engines. Remove exposed legacy entry points only
  after the released-client upgrade gate and SQL caller migration are proven.
  Historical forward migrations are immutable.

MCP uses `get_product_catalog_page` with server-side ID keysets (1-100 rows);
UI's explicit complete bundle and the compatibility reader share the same
`get_product_catalog_data_internal` projection. Types and stock contexts cover
only the returned page. No full-catalog sort/filter/slice remains in Node.
Concurrent inserts after the cursor appear, deleted rows disappear; traversal
is not a frozen snapshot. See the [measured SQL/data evidence](../reports/admin-data-network-keyset-2026-10-23.json).
It carries the same operational counts as the table: `purchased_count` includes
paid and sent relationships, plus distinct form references and readable stock
pool/context metadata. See the [exact semantics and UI mapping](product-admin-read-contract.md).
It never returns form links/keys, QR codes or customer records. `data` and stock lists
are whole replacements: adapters must preserve entries outside the requested
change. Immediate price edits never rewrite purchased order prices.

The [MCP design practices](mcp-design-practices.md) distinguish protocol
requirements, published implementation experience and Festapp decisions.

## Administration inventory and sequence

The authoritative next-wave order, acceptance criteria and execution guidance
are in the [canonical administration execution plan](../plans/admin-mcp-canonical-plan-2026-10-23.md).
Those future waves are planned, not implemented. The [human-readable action
catalog](../reports/admin-capabilities-2026-10-23.html) lists concrete UI actions,
settings and current remote MCP tools separately.

Inventory follows `AdministrationTabs` and the actual unit administration tabs.
Features vary by tenant and occasion. This is a capability map, not a promise
that every row is exposed by the current MCP catalog.

| Area | Canonical owner / current UI | MCP coverage / next cutover |
| --- | --- | --- |
| Identity, live access, organizers | user-permission predicates, operator access | Available, narrowed by consent |
| Occasion creation | occasion client-sync command and setup finalization | Hidden occasion creation available; advanced setup remains |
| Orders, customer responses and ticket products | operator order adapters over existing order commands | Available; changes, cancellation, paid state and reports |
| Payments and ticket delivery | payment pairing and canonical mail queue | Manual payment and queued tickets available; no implied provider refund |
| Products, stock assignments | product catalog and client-sync product owners | First slice: read/create/update/delete and combined stock save |
| Scheduled product prices/visibility, waves | shared schedule command adapter and existing wave/plan owners | Local: wave list, ensure/target/move/cancel and standalone price changes; explicit new consent |
| Email templates, previews, inheritance | email template domain and shared renderer; unit/occasion template tabs | Next area after products; retain exact inheritance and rendering rules |
| Forms, fields, form access/sales | form aggregate commands; forms tab | Pending, audit draft/save/publication boundaries together |
| Seating plans, spots and ticket artwork | blueprint aggregate, seating/capacity commands and canonical PDF renderer | Artwork read available; full editor operations pending |
| Stock pools, contexts, resources | inventory domain commands; pools tab | Catalog assignments included; pool/resource administration pending |
| Occasion info, features, settings | occasion aggregate commands; info/settings tabs | Pending, combine related settings in their aggregate save |
| Users, roles, groups and volunteers | canonical user-permission and group commands | Pending; role changes require particular care and live checks |
| Schedule, places, speakers, services, game | corresponding domain commands and feature tabs | Pending, enabled only where normal administration supports them |
| Reports and history | report and audit projections | Order report available; other reports/change history pending |
| Unit settings, occasion lists and quotes | unit/occasion/quote domain; unit admin tabs | Pending, unit scope must not be inferred from a single event grant |
| Bank accounts and card connections | bank typed predicates, linked-unit rules and payment-provider owners | Pending; preserve the explicit bank account-admin AND unit-manager rule |
| Account connections and revocation | ordinary session + canonical delegation revoke | Available at `/settings/connections` |

For each subsequent row: trace every actual UI entry point, identify its domain
owner and side effects, then move UI and MCP together. A user intent involving
multiple database mutations belongs in one transactional domain wrapper. Do not
bundle unrelated actions merely to reduce HTTP counts. Asset/provider work
cannot become atomic through a SQL wrapper: preserve the existing outbox or
explicit recovery protocol instead of claiming a single-request transaction.

Standing-area stock preparation now has one transaction and one receipt:
`prepare_standing_inventory`. The UI setup dialog and MCP delegate to it via
typed inventory command adapters. `save_inventory_pool_internal` and
`save_inventory_resource_internal` own mutation rules; existing full-editor and
resource receipt APIs delegate to them. Product assignment/allocation stays in
`update_product_inventory_contexts_internal_v1` and its existing allocator.
The former `BlueprintStandingInventory` client saga was deleted, together with
partial-success state and the post-save full catalog reload. The response pins
the product's actual occasion/type/version and new stock IDs/versions, while
one sync publication preserves the union of existing child audiences.
[Stage 2A evidence](../reports/admin-standing-inventory-evidence-2026-10-23.json)
includes failure after pool and resource creation, insufficient-capacity rollback,
existing sales/addressed seats, competing commands and overlapping same-UUID replay.
General pool/resource reads and edits plus operational seat commands remain
separate next cuts; 2A does not claim that all inventory administration is exposed.

## Product scheduling cutover

The wave matrix and MCP wave list share `get_product_price_waves_internal` via
`get_product_catalog` / `get_product_schedule`. Counts distinguish pending
products, pending changes and applied changes. Product target values/revisions
remain in the same product read model; no raw plans-table dump or Node price engine.

`SupabaseProductScheduleCommands` and MCP use `manage_product_schedule`.
The target branch retains `save_product_wave_target_client_sync_v1` as its sole
receipt owner, including atomic term creation/adoption and first target.
Other actions have one receipt in the schedule domain adapter and call the
existing wave/price owners. Known business revision conflicts produce a durable
409 outcome; genuine serialization/deadlock errors remain retryable with the
same command UUID. Null explicitly removes a target; false means visible.

Removed all six raw current-UI price/wave mutation RPC calls in DbEshop.
The setup draft action saves a new term and target in one local draft update;
SQL finalization remains its own existing aggregate transaction. The scheduler
locks due products by ID before its time/ID loop, matching wave move/cancel.
Released RPCs remain compatible because supported older clients and
`occasion_setup/finalize.sql` consume them; contraction requires their upgrade
and a separate SQL-owner migration, not removal of the single domain engine.
New schedule scopes require explicit consent; old product grants stay unchanged.
Local validation and byte/request evidence are in
[the stage 1 report](../reports/admin-product-schedule-evidence-2026-10-23.json).
Publication and production deployment are tracked by the execution checkpoint.

## Shared inventory administration summaries

Current `InventoryPoolsTab` and MCP stock readers use `inventory_catalog.sql`.
UI explicitly requests `get_inventory_catalog` summary mode; MCP requests bounded
pool and context ID pages (maximum 100). Pool/context summaries contain SQL-owned
physical, allocated, unassigned allocated and separately held spot counts.
Resource-slot assignments count as assigned. Counts are not unique orders or
people; resource supply and the saved sellable ceiling are not checkout availability.
Independent resource/context aggregates avoid multiplying child counts.

Current readers never transfer raw spots, temporary hold secrets or order IDs.
The historical `get_inventory_pools_by_occasion_link` retains its released full
payload and original explicit order-view gate, delegating shared summary metadata.
Full pool editor bundles and all mutation semantics remain their existing owners.
New read consent is explicit and does not expand old product/standing grants.
Actual organization/unit/occasion scope and rights are checked again after reading;
context pages lock the actual pool against a concurrent move.

[Measured summary read evidence](../reports/admin-inventory-summary-network-2026-10-23.json)
compares the exact prior RPC with the current UI and MCP on the same marked fixtures.
These are serialized JSON bytes, not HTTP traffic or production latency measurements.
Pool/resource authoring and operational seat commands remain subsequent cuts.

Pool/resource authoring now uses scoped `manage_inventory` from both typed
InventoryCommands and MCP. It delegates exactly one existing receipt owner with
a late live occasion/entity scope check, including replay. The pool receipt body
is owned by `save_inventory_pool_command_internal`; the historical public API
is a compatibility adapter. Its editor mode preserves old payload hashes and
full snapshots; compact mode binds its distinct snapshot choice into the hash,
builds only pool/context settings and skips unused private replacement hydration.
Resource commands preserve their existing owners; MCP's SQL response excludes
unrelated resource fields and private sync replacements.

`get_inventory_pool_settings_data_internal` and
`get_inventory_resource_rows_internal` are the shared projections used by full
UI editor bundles and compact MCP authoring reads. Current UI reads use an
explicitly scoped `get_inventory_pool_for_edit` boundary. Complete MCP pool
settings refuse more than 2000 contexts or a payload above the save limit, rather
than truncating a replacement aggregate. Full editor reads retain their existing
boundary. Resource settings use bounded ID pages, with a payload ceiling.
Untitled pool deletion now checks row existence rather than a nullable label.
New inventory-write consent requires inventory-read and expands no old grant.

[Authoring evidence](../reports/admin-inventory-authoring-evidence-2026-10-23.json)
covers pre-upgrade receipts, rollback, capacity guards, foreign scope and shared
source parity. Operational seat commands and unused product editor choices remain
subsequent cuts; this is not completion of the entire administration plan.

Product authoring choices are now available as separately consented
`products.options`: bounded type or context pages, including currently unused
choices. They reuse metadata projections with the full UI catalog. The UI already
had complete choices; the discovery gap was in the bounded MCP product view.
No extra UI request or second authoring-selection rule was introduced. See the
[product read contract](product-admin-read-contract.md). Operational seat cut 2B
and stages 3-10 remain pending, with production still gated by required main review.

## Operational seats 2B - inspection and blocking

First 2B slice implements bounded seats.list, expanded seats.preview_block and
seats.block. Lifecycle facts are shared with the private UI reader. Blocking is
an independent binding setting, not a temporary hold, order or checked-in state.
No hold secret, customer identity or order relationship is exposed by MCP.

The confirmed requested/expanded IDs and original layout revision bind a single
new receipt to the existing non-receipted canonical blueprint aggregate owner.
The full editor now enforces complete atomic block-selection units server-side,
including protected companions. It retains local draft/Save/Cancel. A shared lock
helper preserves the existing financial and spot lock sequence. Incoming JSON
changes and memberships are materialized once and joined, avoiding repeated
whole-array scans. No direct new path updates blocked flags. Canonical full-layout
validation remains; narrow operations do not bypass it.

[Seat evidence](../reports/admin-seat-block-evidence-2026-10-23.json) records actual
checkout contention in both directions, live revocation, old/new source controls
and the four inherited fresh-database suite failures. Release holds, swaps,
seat-based order creation and selected-ticket cancellation remain separate cuts.


## Operational seats 2B - confirmed temporary-hold release

Current UI and MCP preview through `preview_blueprint_hold_release`, confirm all
expanded atomic-unit seats and call `release_blueprint_holds`. Immutable preview
captures actual scope, IDs, layout revision and an opaque digest of reservation
identity/expiry. The single private `release_blueprint_holds_command_internal`
owns the existing receipt, locks, release and finalizer. Replay precedes current
snapshot validation so it preserves a subsequent buyer. Live scope/rights are
checked again after execution/replay. Ordered/used members reject the whole intent.

Removal ledger: current UI's post-confirmation re-filtering and unversioned input
are removed. The deployed `release_blueprint_holds_client_sync_v1` name remains
only a thin adapter for already-released clients and their original receipt hash;
remove it only after their verified upgrade gate, not by breaking replay. No
Cloudflare diff transport/flag is enabled. Existing receipt publication remains
compatible; optional client projection failure cannot invalidate DB success.

The new explicit seats:release-holds consent does not expand older order/block
grants. MCP has no checkout secrets or private sync response. Each preview/write
attempt is one scoped RPC; actual serialized two-seat SQL JSON was 379/347 bytes,
excluding HTTP headers/TLS. See [hold evidence](../reports/admin-seat-hold-release-evidence-2026-10-23.json).
Twelve seat PG cases, three selected Flutter cases and consent/transport tests
pass; full MCP is 122 PASS/1 FAIL with no skips. The remaining failure is the known
separate PDF validator readiness mismatch; its seal remains unchanged. Earlier
three fixture/expectation failures were fixed with explicit approved additions
and verified production function ownership, not a broad ACL rebaseline.
New hold migration 2300 is locally verified on main d978; publication/deployment
waits for the preceding release to finish. Swaps, seat orders and ticket
cancellation remain next 2B cuts, and stages 3-10 are not complete.


## Operational seats 2B - confirmed financial swaps

Current source: feat/admin-mcp-confirmed-swap-20261023, parent546d37f90.
Authoritative origin/main fetched: ee0287419 (ticket-delivery changes use2310;
no swap helper/financial owner overlap; translation additions require merging).
Migration2330 is NOT deployed. Hold PR571 head0c1431d9 has six green CI checks
but remains review-gated and engineering-stopped until the preview identity fix
is included in a newly validated source. Earlier bundle is deployed as
festapptickets0.20.367+864, tenant8a390d70/main d97835e.

One aggregate apply_blueprint_seat_swap_internal owns actual price/order updates,
full atomic groups, lifecycle and semantic money projection. Preview executes it
inside rollback. Confirmed command validates original hash/IDs/revision inside
an effect rollback scope, then finalizes the existing inventory.spots.swap receipt.
Old public adapters preserve fingerprints/replay. Both superseded private swap
owners are dropped; the two-argument private lock helper is only a thin arity
adapter to the single canonical parent-graph implementation. Existing financial
calculation helpers remain unchanged. Missing order header money rejects the new
quote/confirmed write, never defaults to zero or commits before typed decoding.

Final real disposable PostgreSQL MCP batch:135 tests,134 PASS,1 known PDF readiness
FAIL,0 skips. Seat suite23 PASS including three inherited blueprint SQL regressions.
Source parity28 owners, helper ACL, legacy pre-upgrade receipts, checkout and role
revocation, actual used-ticket race, foreign parent rejection and four-seat
second-member rollback all PASS. Actual form/order-before-blueprint deadlock
regression reproduced RED (57014), then GREEN after aggregate lock correction.
Measured four-seat preview parent-graph calls3->1, pair applications2; no latency
claim. Actual serialized SQL JSON preview653/write530/replay530 bytes (no HTTP/TLS).

UI uses immutable complete preview and displays affected seats/products/tickets,
customer facts only in authorized editor mode, and actual per-order price changes.
MCP omits customer facts. Dedicated seats:swap consent requires seats:read and
orders:read. Normal path is one preview RPC and one write RPC. Uncertain durable
write is resumed with original UUID/payload before a new preview; expired recovery
retains the original intent. Changed local selection cannot alter approved input.
Preview discards a response after actor identity changes (RED/GREEN verified).
Three final recovery/identity port cases PASS; prior actual workspace UI PASS.
Final workspace UI rerun after identity guard awaits the shared Flutter slot.
No Cloudflare diff-cache flag/transport has been enabled.

Protected production read-only scope audit:4182 org3 spots on canonical layouts,
zero occasion/product/product-type/order/ticket parent mismatches; no IDs or PII
returned. No production fixture or new migration was executed.

Next: final short UI/analyzer gate when workstation slot is released, freeze
source, update PR571 with exact validated scope/revision and preserve required
review. Rebase onto current authoritative main and rerun affected checks before
publication. Then continue seat-order creation and ticket cancellation (2B),
followed by stages3-10. This is not completion of the whole plan.


## Final confirmed-seat local gate complete

Final integrated Flutter batch7 PASS including real reservation workspace,
immutable hold/swap confirmations and durable recovery. Targeted Dart analyze:
0 errors,0 warnings,51 existing brace-style infos. Previous dedicated actor-change
negative test remains PASS. Slot immediately returned to the coordinated queue.

Before publication authoritative main advanced to061201c3d with ticket profiles.
Rebase had no conflicts and no changes to the covered blueprint/ticket consumers;
passing Flutter evidence retained. Detected duplicate migration version2300
between our unpublished hold and newly authoritative profile migration. Moved
ONLY our hold file to20261023232000_confirmed_blueprint_hold_release.sql (identical
SQL digest ac66b3559a038aa2c53ae6d8c36a61778ebd82f9dd0f3d46e81a69cd43fc124f).
Swap2330 remains after it. English owner confirmed profile2300 stays authoritative
and their temporary rename was reverted before publication/application. Neither
new hold nor swap migration has run on production. Old PR571 source0c1431d9 must
not deploy. Generated source parity follows actual current main; no PDF readiness
seal changed. Final report marks swap locally verified/pending deployment.
