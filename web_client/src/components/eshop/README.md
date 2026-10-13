# Eshop Feature (Web Client)

**Purpose**: Manages Orders and checkout flow in the web client context.

## Core Files

- `db_orders.js`: Database interaction layer for Orders.
- `orders_strings.js`: Localization strings for the Eshop feature.

## Split Brain Logic (CRITICAL)

**Warning**: Similar to the Flutter app, the web client handles the _view_ and
_fetching_, but **write logic** is often in SQL.

### 1. Order Creation & Storno

`db_orders.js` submits to `send-ticket-order`. New orders use
`create_ticket_order_client_sync_v1`; authenticated seat replacement uses
`replace_blueprint_order_client_sync_v1`. SQL owns validation, cancellations,
allocations, ticket changes and transactional confirmation intents under one
receipted command. Do not split replacement into frontend requests.

The replacement RPC still calls the internal preparation logic sourced from
`database/functions/eshop/confirm_blueprint_order_change.sql`; it is not dead
code merely because the frontend invokes a different RPC.

The HTTP response confirms the committed order with `delivery: queued` and an
optional confirmation receipt. Only the global `process-email-queue` sends;
provider acceptance and delivery feedback are separate evidence.

## Database Layers

1. **JS (`db_orders.js`)**: Thin authenticated request wrapper.
2. **Edge (`send-ticket-order`)**: Request boundary selecting the receipted RPC.
3. **PostgreSQL (`database/functions`)**: Atomic business logic and durable effects.
4. **Queue worker (`process-email-queue`)**: Globally gated SES sending.

## Critical Implementation Details

- **Transactions**: Relies on Postgres functions for atomicity.
- **Data Structure**: Orders are often handled as raw JSON/Objects matching the
  database structure.
