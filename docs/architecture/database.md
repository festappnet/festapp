# Database Documentation

## Client sync v1 maintenance contracts

The sole publisher releases failed dirty work by exact claim token.
`live_public entity_id=0` means full event refresh; targeted IDs affect only
those rows. Drift health is read-only and repair is an explicit forward
operation, never a trigger. Artifact retention uses bounded service-role
candidate and exact metadata-ack RPCs with one shared cutoff and current
reference protection. Receipt compaction preserves command IDs as permanent
`expired` tombstones; immutable commit audit is never pruned.

## Occasion-scoped companion relationships

`public.user_companions` stores `(occasion, user, companion)` with a unique
companion per occasion and an explicit `origin` of `self_created` or
`admin_assigned`. Client roles have no table privileges. Reads come from the
occasion-aware legacy projection or the identity-scoped `private_profile`;
writable profile fields, groups, services (including accommodation), and
attendance remain sourced from the companion's normal user/occasion records;
the relationship stores none of them. Reads from `private_profile` resolve
those normal records for the owner UI.
writes use only `create_companion_client_sync_v1`,
`delete_owned_companion_client_sync_v1`,
`assign_existing_companion_client_sync_v1`, and
`unassign_existing_companion_client_sync_v1`. Admin unassignment removes only
the relation; account deletion is restricted to self-created companions.

This directory contains the source code for the PostgreSQL database schema,
logic, and security policies.

## Structure

- **`functions/`**: Programmable logic (Stored Procedures/RPCs). This is where
  the core backend business logic resides (e.g., Order creation, User
  management).
  - **Naming Convention**: `verb_noun` (e.g., `scan_ticket`, `calculate_price`).
  - **Security**: Most functions use `SECURITY DEFINER` to run with owner
    privileges, bypassing RLS for complex multi-table operations.
- **`policies/`**: Row Level Security (RLS) policies defining who can see/edit
  what data.
- **`seed/`**: Initial data for setting up a fresh environment.
- **`tests/`**: SQL regression tests.
- **`tables/`**: Table definitions (though often managed via migrations).

## Architecture Patterns

### Split Brain Logic

A significant portion of the application's business logic resides here in SQL,
not in the client (Flutter/Web).

- **Write Operations**: Complex writes (like creating an order) are atomic SQL
  functions.
- **Read Operations**: Often use specialized views or RPCs to return "Frontend
  Ready" JSON.

## Testing

Database logic is tested using a dedicated runner that executes SQL test files
in a transaction and rolls them back.

Run tests via the root automation script:

```bash
./automation/test_all.sh
```

Or specific DB tests:

```bash
node web_client/scripts/run_db_tests.js database/tests/my_test.sql
```

See **[CONTRIBUTING.md](../../CONTRIBUTING.md)** for detailed testing patterns.

---

## Function Inventory

SQL functions organized by domain:

| Directory | Purpose | Key Functions |
|-----------|---------|---------------|
| `account_deletion/` | Account deletion lifecycle | Request/confirm deletion contracts |
| `activities/` | Volunteer shift management | Task CRUD, assignment logic |
| `cleaning/` | Cleaning reports | Status, report and resolution commands |
| `cron/` | Scheduled jobs | Automated cleanup, notifications |
| `emails/` | Email operations | Template rendering, logging |
| `eshop/` | Product management | `update_product`, product queries |
| `eshop_bank_accounts/` | Payment pairing | Bank account sync, matching |
| `eshop_forms/` | Form-order bridge | `create_form`, `get_form_by_link`, form CRUD |
| `eshop_orders/` | Order lifecycle | `scan_ticket`, `get_orders`, status transitions |
| `eshop_transactions/` | Transactions | `add_transaction_to_payment_info_ws` |
| `events/` | Schedule events | Event CRUD, sign-up logic, event feedback |
| `inventory/` | Capacity pools | Pool allocation, availability checks |
| `notifications/` | Notification delivery | Queue and provider delivery helpers |
| `organization/` | Domain ops | Org settings, admin management |
| `others/` | Cross-cutting | `duplicate_occasion`, `check_is_*` guards, image records, email templates |
| `places/` | Map data | Place and path commands |
| `seed/` | Data seeding | Initial data setup |
| `speakers/` | Speakers and counselling | Speaker/topic commands and search |
| `support/` | Help operations | Support requests |
| `synchronization/` | Data sync | Sync state management |
| `units/` | Unit management | Unit CRUD, user-unit linking |
| `user_permissions/` | RBAC | `get_is_*` permission checks (boolean returns) |
| `user_services/` | Service assignments | User-service linking |
| `users/` | User management | `create_user_in_organization_with_data_pure`, `delete_user`, `import_user_group_assignments` |
| `utilities/` | Shared utilities | Helper functions |
| `utils/` | Additional utils | Format helpers |

---

## Security Audit Summary

### SECURITY DEFINER

- Many functions use `SECURITY DEFINER`, which bypasses Row Level Security and
  runs with owner privileges
- All must follow the mandatory checklist in
  **[CONTRIBUTING.md](../../CONTRIBUTING.md)**

### Permission Check Patterns

The codebase uses two permission function families:

1. **`check_is_*`** - Raises exception on failure (for write operations)
   - `check_is_editor_order_on_occasion(oc_id)` - Verifies order editor
   - `check_is_editor_order_view_on_occasion(oc_id)` - Verifies order viewer
   - `check_is_editor_on_unit(unit_id)` - Verifies unit editor
   - `check_is_manager_on_unit(unit_id)` - Verifies unit manager
   - `check_is_admin_for_bank_account(account_id)` - Verifies bank admin
   - `check_is_admin_of_organization(org_id)` - Verifies org admin

2. **`get_is_*`** - Returns boolean (for conditional logic)
   - `get_is_admin_on_occasion(oc_id)` - Returns true/false
   - `get_is_manager_on_occasion(oc_id)` - Returns true/false
   - `get_exists_on_occasion_user(user_id, oc_id)` - User exists check

### Search Path Discipline

Application RPCs use:
```sql
SET search_path = public, extensions
SELECT ... FROM eshop.orders; -- explicitly qualify non-public schemas
```

Never add `eshop` or another writable schema to a `SECURITY DEFINER` search
path. Keep non-public objects schema-qualified and enforce authorization inside
the function.

---

## Schema Overview

Key tables (defined in `lib/database_tables/tb.dart`):

```mermaid
erDiagram
    organizations ||--o{ units : has
    units ||--o{ occasions : has
    occasions ||--o{ events : has
    occasions ||--o{ forms : has
    occasions ||--o{ information : has
    occasions ||--o{ activities : has
    occasions ||--o{ occasion_users : has
    user_info ||--o{ occasion_users : joins
    user_info ||--o{ unit_users : joins
    user_info ||--o{ organization_users : joins
    events ||--o{ event_users : signups
    forms ||--o{ form_fields : contains
    forms ||--o{ products : offers
    inventory_pools ||--o{ resources : contains
    resources ||--o{ resource_slots : contains
    inventory_pools ||--o{ inventory_contexts : scoped_by
```

### Core Hierarchy

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `organizations` | Domain-level container | `id`, `data` (JSONB config) |
| `units` | Real-world organizations | `id`, `organization` |
| `occasions` | Event instances | `id`, `unit`, `link`, `features` (JSONB) |

### User System

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `user_info` | User profiles | `id`, `email_readonly` (canonical account email), `email_delivery` (optional mail override), `organization` |
| `occasion_users` | User-occasion link | `user`, `occasion`, `is_editor_view` |
| `unit_users` | User-unit link | `user`, `unit` |
| `organization_users` | User-org link | `user`, `organization` |
| `user_companions` | Occasion-scoped companion relationships | `occasion`, `user`, `companion`, `origin`, `created_by` |
| `user_groups` | Group membership | `user`, `group` |
| `user_group_info` | Group metadata | `id`, `occasion`, `title` |
| `user_reset_token` | Password reset | `user`, `token` |

### Content

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `events` | Schedule entries | `id`, `occasion`, time fields |
| `event_users` | Event sign-ups | `user`, `event` |
| `event_users_saved` | My schedule items | `user`, `event` |
| `event_feedback` | Per-event rating/comment owned by a user or anonymous client ID | `event`, `occasion`, `user`, `client_id`, `rating` |
| `information` | CMS pages | `id`, `occasion` |
| `news` | Announcements | `id`, `occasion`, `created_by` |
| `places` | Map locations | `id`, `occasion` |
| `path_groups` | Map path groups | `id`, `occasion` |
| `icons` | Custom map icons | `id` |

### Forms

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `forms` | Form definitions | `id`, `occasion` |
| `form_fields` | Form field definitions | `id`, `form` |
| `products` | Purchasable items | `id` |
| `email_templates` | Email templates | `id`, `occasion` |
| `images` | Image records | `id` |

### Inventory & Activities

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `inventory_pools` | Capacity pools | `id` |
| `resources` | Inventory resources | `id` |
| `resource_slots` | Time-based slots | `id` |
| `inventory_contexts` | Pool contexts | `id` |
| `activities` | Volunteer tasks | `id`, `occasion` |
| `activity_assignments` | Task assignments | `id`, `activity_id` |

---

## RPC Call Map

Key SQL functions called from client code (search for `supabase.rpc(...)` in
Dart or `supabase.rpc(...)` in JS):

| RPC Function | Called From | Purpose |
|-------------|-------------|---------|
| `send-ticket-order` (Edge Function) | Web Client, Flutter | Receipted order create/replace + transactional effect queue |
| `replace_blueprint_order_client_sync_v1` | Edge Function | Atomic seat replacement and new order |
| `scan_ticket` | Flutter | Ticket verification |
| `delete_user` | Flutter | User deletion |
| `create_user_in_organization_with_data_pure` | SQL Functions (internal) | User creation |
| `get_ticket_details_for_generating` | Edge Functions | Ticket PDF data |
| `get_occasion_seo_data` | Cloudflare Pages Worker | SEO metadata |
| `get_available_occasions` | Cloudflare Pages Worker | Sitemap data |
