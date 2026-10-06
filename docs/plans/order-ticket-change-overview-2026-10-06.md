# Ticket identity in order update previews and emails

## Outcome and evidence

Cancelling a ticket must appear as **Cancelled tickets**, identified by its ticket
symbol and including its products. Removing a product from a surviving ticket
must remain a product change. Mixed changes must show both without counting a
cancelled ticket's products twice.

Current `OrderCalcHelper` and `changeOverview.ts` flatten all tickets before
matching products. They lose identity and can pair a cancelled ticket's product
with a price change on another ticket. `extract_history_products_with_price`
uses DISTINCT, hiding quantity changes between identical tickets. The product
editor currently previews unsaved products although email preparation reads the
persisted order. These are the concrete correctness gaps in this change.

## Canonical owner and contract

1. Add one internal SQL read function, `get_order_change_summary_v1`, which owns
   baseline selection, ticket classification, product matching and totals.
   The baseline is the latest history marked `is_sent_to_customer`, with
   deterministic `created_at, id` ordering; when none was sent, preserve the
   existing oldest-history fallback. No reference means no invented changes.
2. Compare ticket IDs before comparing their products. A missing historical
   ticket is labelled cancelled only if its actual ticket belongs to this order
   and has state `storno`. Otherwise show a neutral removed-ticket category.
   Added tickets are their own category. Compare products only on surviving
   tickets, preserving duplicate instances and matching ID, title and price.
   Empty/free tickets are still ticket changes.
3. Return a typed, presentation-independent JSON summary: cancelled/removed/
   added tickets, added/removed/changed products with ticket context, old/new
   totals, changed ticket IDs, and `has_changes`. Keep historical identity for
   labels, fall back to the actual ticket symbol where appropriate. Never
   expose another order's ticket metadata.
4. Add the summary to the existing protected `get_products_for_ticket` and
   service email-detail responses. Their signatures and existing fields remain
   compatible. Derive the existing newer-version flag from the same summary.
   The internal helper has no anonymous/authenticated execution privilege.
5. Replace Dart and TypeScript comparison algorithms with parsers/renderers of
   this same summary. Retain the shared confirmation dialog. Refresh persisted
   preview data before confirmation and disable sending from an editor with
   unsaved product changes. Queue preparation continues using its existing
   current-snapshot contract; no new email producer, queue or cancellation path.

## Validation and release

Use SQL rollback fixtures on the existing disposable database; no production
fixtures and no local Docker. Cover identical tickets, cancellation plus a
price edit on the survivor, product removal without cancellation, empty/free
cancelled tickets, duplicate products, ticket addition/removal, missing IDs,
wrong-order cancellation metadata, no history, latest sent baseline, tied
history timestamps, and unchanged state after successful email post-action.

Test Dart rendering and English/Czech email rendering against the structured
contract, including no double counting and no HTML injection through labels.
Run the repository full suite and relevant migration/layout/translation checks.
Publish shared code to authoritative main using the existing authorization.
Deploy canonical SQL first, then the reviewed complete Edge bundle, then the
Festapp Tickets tenant overlay. Keep database/function rollback evidence and
verify the live version and queue health. Use a new owner test order only when
necessary; any real email goes exclusively to the already authorized owner.
