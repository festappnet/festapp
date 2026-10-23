# Product administration read contract

The product table is an operational projection, not a raw products-table dump.
`get_product_catalog_data_internal` owns its joins and counts for the full UI
bundle and bounded MCP pages. `ProductsTab.columnIdentifiers` and
`ProductGridRecord.toTrinaRow` identify the relevant UI facts.

| UI fact / question | Shared source and meaning | MCP field |
| --- | --- | --- |
| Product, type, price, currency, visibility, limit, order | Saved product plus its actual occasion-owned product type | product fields and productTypes |
| How many items have relationships to orders? | COUNT of order_product_ticket rows, all order states, preserving current UI semantics | ordered_count |
| How many were bought / administration paid column? | COUNT of those rows whose order is paid or sent | purchased_count |
| Payment/delivery state breakdown | Same relationship rows filtered to paid or sent separately | paid_count, sent_count |
| Which forms use this product type? | Distinct actual form IDs in this occasion; duplicate fields do not duplicate forms | form_ids plus forms (id, title) |
| What stock does this product include? | Product-context quantity plus actual pool name/type and context title/date | inventory_contexts plus inventoryContexts |
| What changes are pending? | Existing planned_changes queue for this product, retaining revision, wave, time and failure metadata | price_changes, visibility_changes |
| Short title, deposit and surcharge | Existing product data and canonical money/currency rules | short_title, data |
| Is it used by a seating plan? | Existing actual spot-product binding in this occasion | is_used_in_blueprint |

Purchased items are not distinct orders or unique attendees. Two tickets in one
paid order count as two purchased items. Sent orders still count as purchased.
Storno rows are not purchased; historical all-state ordered_count remains an
all-state relationship count. It is not presented as completed sales or revenue.
No monetary total, refund state, dynamic stock availability or people count is
inferred by subtracting these fields. Those questions belong to their existing
report/inventory/financial owners.

Form references mean that a field references the product's type. They include
hidden fields, as the UI does; they do not assert that checkout is currently
open or that the product can be bought now. MCP receives no form public links,
keys, order symbols, QR codes or customer records in this view. Context names
retain pool/date information needed to interpret otherwise anonymous IDs.

SQL computes the counts in one lateral aggregate per selected product, before
joining any form/context collections, preventing multiplication of counts.
The current UI reads purchased_count directly and retains all counts during
local editing. Node only adapts names, decimal transport and relation indexing.
Released clients retain paid_count and sent_count and their old display adapter;
there is no second current calculation. Public compatibility readers delegate
to the same projection until the last supported caller has upgraded.

Server keysets select at most 100 products before projection (plus one ID for
lookahead). Related types/contexts/forms cover only returned rows. Inventory
assignments are capped by the existing 1000-item product DTO, and page form
references have a 1000-reference ceiling; oversized historical data fails
explicitly rather than silently dropping relationships. The complete editor
mode retains the full editing choices. See measured results in
[admin-view evidence](../reports/admin-data-network-admin-view-2026-10-23.json).

Unused authoring choices use `products.options` / `get_product_catalog_options`.
Each request selects one kind (product_types or inventory_contexts), at most 100
IDs before projection, with a 1 MiB result ceiling and an ID cursor. Empty product
pages keep empty related metadata; options independently discover unused types
and contexts even when there are no products. The full UI editor already offered
all those choices and continues to make its existing single catalog request.
Both views now reuse get_product_type_rows_internal and
get_product_context_rows_internal. MCP context choices retain actual group
names/types/dates, never raw spots, context data, customer records or form links.

New product-options consent requires product-read in both grant and token;
previously issued product grants gain no extra operation. Scope and live rights
are checked again after each read. Actual product occasion also participates in
catalog selection, so a mismatched legacy product/type pair cannot expose a
foreign occasion product through a local type.
