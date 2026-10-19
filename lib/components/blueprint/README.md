# Blueprint (visual seat selection)

The public `venue_seat_picker` package owns V2 geometry, rendering, gestures,
selection activation and history. Festapp owns products/prices, explicit commercial
group membership, seat-to-spot bindings, permissions, orders and command receipts.
The generic package never receives a Supabase client or private order metadata.

`layout != null` selects the V2 host and public adapters. Unconverted legacy
records retain the explicit V1 route. A V2 load/save failure remains repairable;
it never silently falls back to legacy rendering. `convertLegacyBlueprint` is an
explicit reviewed conversion input, not a reader side effect. Legacy SVG cover
placement requires a ready asset processed by the existing Image Worker.

## Geometry and business state

Geometry and commercial binding changes form one revisioned draft. Selection alone
does not dirty it. Group defaults are explicit; mixed or unassigned groups do not
invent a price. New seats inherit a known group default, while protected ordered,
used or actively held seats cannot be structurally rewritten. Existing `spot.id`
stays stable when geometry changes. Copy creates fresh identities without holds
or order/ticket assignments.

`FormCommands.saveBlueprint` uses `update_blueprint_client_sync_v1`, the existing
receipt and sync boundary. SQL validates the entire geometry/binding aggregate
before commit. An ambiguous retry retains the same command UUID and frozen input;
a late response must not erase newer draft edits. `_v1` names this public protocol,
not the geometry version. Catalog edits and confirmed order commands take effect
immediately and are not reversed by geometry undo or draft discard.

## Reservation and financial authority

Both customer pickers apply optimistic presentation through the package and
rollback rejected callbacks. Only `select_spot` creates/releases the actual
secret/expiry hold. SQL locks the complete atomic unit, validates form offers,
visibility, maximum and shared PIC capacity, then changes all members or none.
An owned retry keeps its original expiry; release remains possible after an
offer closes. Existing active addressed holds count through PIC quantities even
when the held spot has no direct inventory context. They use the existing spot
hold records, not a second reservation ledger.

Standing quantity uses actual offered form product fields and the existing
inventory/finalization owner. Changing quantity does not create a seat hold.
Checkout uses `send-ticket-order` and `create_ticket_order_client_sync_v1`;
admin replacement uses `replace_blueprint_order_client_sync_v1` and the existing
conflict/cancellation owner. Swaps use the existing preview, receipted command,
financial recalculation and history. Clients never calculate authoritative money
or publish a success before the command receipt. Refresh restores server state.

## Fonts, images and setup

Font outlines reuse Ticket Editor's catalog and authorized resolver. Public readers
receive only referenced validated resources. The existing Image Worker processes
backgrounds, and an authorized one-purpose HMAC registers final byte hash, raster
dimensions, MIME and length. Canonical save checks owner scope and readiness;
clients verify/decode bytes into transient renderer resources. Neither source SVG,
private image records nor proof keys enter the public document.

Setup drafts persist typed geometry and commercial bindings without source spot
IDs or binary resources. Unit-scoped resources work before the occasion exists.
Final creation remaps identities through existing product/inventory and aggregate
save owners. Shared configuration-copy helpers preserve exact resources and named
slots, with no reservations. The separately marked offline demo uses package
fixtures only and calls no business commands.
