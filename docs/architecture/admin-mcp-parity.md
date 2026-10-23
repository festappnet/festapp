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

A concrete remaining compound workflow is standing-area stock preparation
(`blueprint_standing_inventory.dart` and the setup dialog): inventory preparation,
product linkage and catalog refresh cross domain boundaries. It belongs to the
inventory/blueprint cutover, and is not advertised as a new atomic product save.
Each such workflow must be traced and migrated as a whole before its MCP write
is exposed.

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
