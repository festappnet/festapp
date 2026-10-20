# Blueprint (Visual Seat Selection)

Visual seat selection/reservation interface for the Eshop.

The reusable viewer, customer picker and venue editor are provided by the public
[`venue_seat_picker`](https://github.com/festappnet/venue_seat_picker) package.
Festapp maps `BlueprintObjectModel` through a read-only `SeatAdapter`; SQL
reservation authority and product/order behavior remain in this feature.

## Split Brain: Dart UI vs SQL Authority (CRITICAL)

Selection state is managed optimistically in Dart but authoritatively in SQL.

- Dart updates UI color immediately on tap.
- `select_spot` RPC does the real work:
  1. Validates Blueprint/Form exists
  2. Checks availability (`order_product_ticket IS NULL`)
  3. On select: sets `secret` + `secret_expiration_time` (temporary lock)
  4. On deselect: verifies secret matches before clearing

**If RPC fails (spot taken by another user), UI must roll back** -- handled by
the package `VenueSeatPicker` around Festapp's `select_spot` callback.

## Gotchas

- **SVG Coordinates**: Do not change `BlueprintModel` parsing without verifying the SVG export format. Coordinate mapping is fragile.
- **Spot -> Product linking**: `BlueprintModel.findObject` locates objects by ID; complex logic links seat coordinates to Product IDs.

## Data Flow

```mermaid
sequenceDiagram
    participant U as User
    participant D as Dart UI
    participant SQL as PostgreSQL
    participant EF as Edge Function

    U->>D: Tap seat
    D->>D: Optimistic UI update (color)
    D->>SQL: select_spot RPC
    SQL-->>SQL: Check availability + set secret + expiration
    SQL-->>D: OK / Error (roll back UI)
    U->>D: Submit order
    D->>EF: send-ticket-order (spots + payload)
    EF->>SQL: Create order + tickets
    EF-->>D: Confirmation
```

## SQL RPCs

- `select_spot` -- locks/unlocks seat with secret and expiration
- `create_ticket_order_client_sync_v1` -- receipted order creation via `send-ticket-order`
- `replace_blueprint_order_client_sync_v1` -- atomic seat/order replacement via the same Edge boundary

Replacement still calls `confirm_blueprint_order_change_internal_v1` inside its
transaction. The original SQL source is retained for that implementation and
historical schema reconstruction; lack of direct frontend calls does not make
the domain logic obsolete.
