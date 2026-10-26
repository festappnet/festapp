# Current Festapp data boundary - read-only evidence, 2026-10-18

Inspected the current dirty Festapp working tree as a reference, not a live DB
snapshot. No production rows were queried and no Festapp runtime file was changed. The execution plan separately records the evidenced geometry magnitude limit.
This records semantics needed for later B; it does not implement B.

| Current owner | Observed contract | Standalone A consequence / later B requirement |
| --- | --- | --- |
| `BlueprintModel`, `eshop.blueprints` | `data` is separate nullable metadata; `configuration`, `objects`, `groups`, `background_svg` are distinct fields | Do not repurpose arbitrary `data` as a second geometry authority. New layout owns geometry only; existing host metadata must be inventoried and preserved in B. |
| `BlueprintObjectModel` | `x/y` are integer column/row indices; spot objects carry the existing spot ID and a group reference | New world coordinates are not reinterpretations of grid indices. Stable node identity and DB spot identity remain separate; B requires explicit scale and bindings. |
| `BlueprintGroupModel.toJson()` | Saves only `{id,title}`. `product` is explicitly transient. Membership is reconstructed from each object's `group`. | One persisted relationship authority; never save contradictory group item lists. A uses parent references for spatial hierarchy; host pricing defaults and selection units have distinct meanings. |
| `GetOrdersHelper.enrichObjects` | Joins geometry object to spot by spot ID and product by product ID; currently drops unknown types and defaults unresolved state to available | New import must reject unsupported kinds, broken references and invalid states before mutation. An absent live state is never evidence of availability in a future production adapter. |
| `eshop.spots` | Owns product, title, hold secret/expiry, order_product_ticket and blueprint scope, with foreign keys | Prices/occupancy/secrets/orders never enter portable geometry, presets or thumbnails. B must preserve IDs and delegate reservations to the existing owner. |
| Group price dialog | Setting group product assigns all its seats; individual seat product is an exception | Demo host stores explicit table default and per-seat override outside geometry. Automatic reflow preserves overrides. Reparent inherits target default in the same history transaction. |
| `_handleAddAvailable` | New seat inherits transient group product, then first group seat, then first product | B must persist an explicit default, preserving known historical values; mixed groups without a known default cannot infer it from an arbitrary seat. A does not copy this fallback ambiguity. |
| `DbForms.updateBlueprint` | Client Sync v1 calls `update_blueprint_client_sync_v1`; legacy facade remains in source. Migration renames internal owner `update_blueprint_internal_v1` | Do not infer live behavior from an old SQL source file alone. B must trace actual deployed wrapper/internal owner, grants, receipt and lock ordering afresh. A does no SQL changes. |

Relevant reference files:
`lib/components/blueprint/{blueprint_model,blueprint_group,blueprint_object_model,blueprint_configuration,get_orders_helper}.dart`,
`lib/components/blueprint/views/{blueprint_editor_tab,blueprint_product_dialogs}.dart`,
`lib/components/forms/{db_forms,supabase_form_commands}.dart`,
`database/tables/tables.sql`, `database/functions/eshop/{get_blueprint_for_edit,update_blueprint,select_spot}.sql`,
`supabase/migrations/20260802234000_client_sync_v1_expansion.sql`.

Data gates in A: immutable validated geometry, explicit identifiers/relationships,
complete reference remapping on copy, no hidden business payload, canonical JSON,
version rejection preserving original payload, atomic command rejection, safe
resource imports, and saved-baseline/draft separation across reload. These are
package guarantees; SQL scope, locking, receipts and spot bindings remain B.
