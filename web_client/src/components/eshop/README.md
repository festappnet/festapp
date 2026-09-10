# Eshop Feature (Web Client)

**Purpose**: Manages Orders and checkout flow in the web client context.

## Core Files

- `db_orders.js`: Database interaction layer for Orders.
- `orders_strings.js`: Localization strings for the Eshop feature.

## Split Brain Logic (CRITICAL)

**Warning**: Similar to the Flutter app, the web client handles the _view_ and
_fetching_, but **write logic** is often in SQL.

### 1. Order Creation & Storno

The web client relies on the same SQL backend functions as the Flutter app:

- `database/functions/eshop/confirm_blueprint_order_change.sql`

**Logic**:

1. **Analyze**: Checks for spot occupancy.
2. **Storno**: Cancels old tickets if necessary.
3. **Unlock**: Clears secrets.
4. **Prepare**: Constructs new order payload.

**Risk**: Modifying the order creation flow must be done with awareness of the
SQL "heavy lifting".

## Database Layers

1. **JS (`db_orders.js`)**: Wrapper calling Supabase RPCs.
2. **Supabase (`database/functions`)**: Business logic.
3. **Edge Functions**: Emailing/Payments.

## Critical Implementation Details

- **Transactions**: Relies on Postgres functions for atomicity.
- **Data Structure**: Orders are often handled as raw JSON/Objects matching the
  database structure.
